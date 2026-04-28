import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import 'local_database.dart';

/// Single entry point for every change to a product's stock level.
///
/// Invariant: a stock change always means **one row in `stock_movements`**
/// per affected product. The accompanying update to `products.quantity`
/// happens in the same SQLite transaction. Sync to Supabase is handled
/// out-of-band by `SyncService.syncUp` via UPSERT on `client_id`, so
/// retries are idempotent (no more 58x duplicate decrements).
///
/// Linkage (Box ⇄ Can via `base_unit_id`) is expanded here: a single
/// caller-supplied change may produce multiple stock_movements, each
/// with its own UUID, all inside the same transaction.
class StockService {
  StockService(this.ref);

  final Ref ref;
  static const _uuid = Uuid();

  /// Apply [inputs] inside an existing [txn]. Returns the local row ids
  /// of every stock_movement inserted. Use this from `processCheckout`
  /// so the sale, sale_items, and stock changes commit atomically.
  Future<List<int>> applyInTransaction({
    required Transaction txn,
    required List<StockChange> inputs,
    required String reason,
    int? localSaleId,
  }) {
    return _applyInternal(
      executor: txn,
      inputs: inputs,
      reason: reason,
      localSaleId: localSaleId,
    );
  }

  /// Standalone (non-transactional caller) variant. Opens its own
  /// transaction. Use from screens (edit product, delete/return sale).
  Future<List<int>> apply({
    required List<StockChange> inputs,
    required String reason,
    int? localSaleId,
  }) async {
    final db = await LocalDatabase.instance.database;
    return db.transaction((txn) => _applyInternal(
          executor: txn,
          inputs: inputs,
          reason: reason,
          localSaleId: localSaleId,
        ));
  }

  Future<List<int>> _applyInternal({
    required DatabaseExecutor executor,
    required List<StockChange> inputs,
    required String reason,
    required int? localSaleId,
  }) async {
    if (inputs.isEmpty) return const [];

    // Load all products once so linkage lookups are O(1).
    final rows = await executor.query('products');
    final products = rows.map(Product.fromJson).toList();
    final byId = <int, Product>{for (final p in products) p.id: p};

    // Expand linkage and aggregate changes per product, so a single
    // movement is recorded per affected product even if multiple inputs
    // touch the same chain.
    final delta = <int, double>{};
    for (final inp in inputs) {
      final product = byId[inp.productId];
      if (product == null) {
        debugPrint(
          'StockService: product ${inp.productId} not found, skipping',
        );
        continue;
      }
      delta[inp.productId] = (delta[inp.productId] ?? 0) + inp.change;
      if (product.baseUnitId != null) {
        delta[product.baseUnitId!] = (delta[product.baseUnitId!] ?? 0) +
            inp.change * product.baseUnitConversion;
      }
      for (final p in products) {
        if (p.baseUnitId == inp.productId && p.baseUnitConversion != 0) {
          delta[p.id] =
              (delta[p.id] ?? 0) + inp.change / p.baseUnitConversion;
        }
      }
    }

    final localIds = <int>[];
    for (final entry in delta.entries) {
      final pid = entry.key;
      final change = entry.value;
      if (change == 0) continue;

      final qRow = await executor.query(
        'products',
        columns: ['quantity'],
        where: 'id = ?',
        whereArgs: [pid],
      );
      if (qRow.isEmpty) continue;
      final current = (qRow.first['quantity'] as num).toDouble();
      await executor.update(
        'products',
        {'quantity': current + change},
        where: 'id = ?',
        whereArgs: [pid],
      );

      final id = await executor.insert('stock_movements', {
        'client_id': _uuid.v4(),
        'product_id': pid,
        'change': change,
        'reason': reason,
        'sale_id': localSaleId,
        'is_synced': 0,
      });
      localIds.add(id);
    }
    return localIds;
  }
}

/// A single requested stock change (positive = stock in, negative = stock out).
@immutable
class StockChange {
  const StockChange({required this.productId, required this.change});
  final int productId;
  final double change;
}

final stockServiceProvider = Provider<StockService>(
  (ref) => StockService(ref),
);
