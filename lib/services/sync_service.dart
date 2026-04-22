import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'local_database.dart';
import '../providers/data_providers.dart';
import 'printing_service.dart';

final syncServiceProvider = Provider((ref) => SyncService(ref));

class SyncService {
  final Ref ref;
  SyncService(this.ref) {
    _initRealtimeListener();
  }

  final _supabase = Supabase.instance.client;

  // Prevent concurrent syncUp calls (avoids duplicate uploads)
  bool _isSyncing = false;

  /// Returns true if there is any local data waiting to be pushed to Supabase.
  Future<bool> hasUnsyncedData() async {
    try {
      final db = await LocalDatabase.instance.database;
      final sales = await db.query(
        'sales',
        where: 'is_synced = ?',
        whereArgs: [0],
        limit: 1,
      );
      if (sales.isNotEmpty) return true;
      final movements = await db.query(
        'stock_movements',
        where: 'is_synced = ?',
        whereArgs: [0],
        limit: 1,
      );
      if (movements.isNotEmpty) return true;
      final products = await db.query(
        'products',
        where: 'is_synced = ?',
        whereArgs: [0],
        limit: 1,
      );
      if (products.isNotEmpty) return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  void _initRealtimeListener() {
    // Only listen on Desktop (Mac/Windows/Linux) as they are the primary POS terminals
    if (kIsWeb) return;
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) return;

    debugPrint('Initializing Realtime Listeners...');

    // Cash drawer: remote open command from mobile
    _supabase
        .channel('cash_drawer_commands')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'cash_drawer_logs',
          callback: (payload) {
            final newRecord = payload.newRecord;
            if (newRecord['type'] == 'open' &&
                newRecord['reason'] == 'remote_open') {
              debugPrint('Received remote open command!');
              ref.read(printingServiceProvider).openCashDrawer();
            }
          },
        )
        .subscribe();

    // Sales: trigger refresh of today's sales stats on any change
    _supabase
        .channel('sales_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'sales',
          callback: (_) {
            debugPrint('Sales change detected, refreshing stats...');
            ref.read(dbUpdateTriggerProvider.notifier).trigger();
          },
        )
        .subscribe();
  }

  /// Fetches every row from [table] by paginating with `.range()`. Supabase's
  /// default PostgREST max_rows is 1000, so `.limit(N)` caps at 1000 on the
  /// server regardless of the client value. Pagination is the only way to
  /// retrieve more.
  Future<List<Map<String, dynamic>>> _fetchAllRows(
    String table, {
    int pageSize = 1000,
  }) async {
    final List<Map<String, dynamic>> all = [];
    int from = 0;
    while (true) {
      final chunk = await _supabase
          .from(table)
          .select()
          .order('id', ascending: true)
          .range(from, from + pageSize - 1);
      if (chunk.isEmpty) break;
      all.addAll(List<Map<String, dynamic>>.from(chunk));
      if (chunk.length < pageSize) break;
      from += pageSize;
    }
    return all;
  }

  Future<void> syncDown() async {
    try {
      final db = await LocalDatabase.instance.database;

      // ── Categories ──
      final categories = await _fetchAllRows('categories');
      await db.transaction((txn) async {
        for (var cat in categories) {
          cat['is_synced'] = 1;
          await txn.insert(
            'categories',
            cat,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });

      // ── Products (Smart Reconciliation, batched) ──
      // Paginate: Supabase's PostgREST default caps a single query at 1000
      // rows regardless of .limit(), so >1000 products were silently dropped.
      final products = await _fetchAllRows('products');

      // Preload local state in bulk to avoid N+1 queries on mobile.
      final localProdRows = await db.query(
        'products',
        columns: ['id', 'is_synced', 'image_url'],
      );
      final localProdMap = <int, Map<String, Object?>>{
        for (var r in localProdRows) r['id'] as int: r,
      };

      final unsyncedMovementRows = await db.query(
        'stock_movements',
        columns: ['product_id', 'change'],
        where: 'is_synced = 0',
      );
      final unsyncedAdjustMap = <int, double>{};
      for (var m in unsyncedMovementRows) {
        final pid = m['product_id'] as int?;
        if (pid == null) continue;
        unsyncedAdjustMap[pid] =
            (unsyncedAdjustMap[pid] ?? 0) + (m['change'] as num).toDouble();
      }

      // FK off: categories/base_unit may not all be local yet.
      await db.execute('PRAGMA foreign_keys = OFF');
      try {
        await db.transaction((txn) async {
          for (var prod in products) {
            final pid = prod['id'] as int;
            final remoteQty = (prod['quantity'] as num?)?.toDouble() ?? 0.0;
            final reconciledQty = remoteQty + (unsyncedAdjustMap[pid] ?? 0);

            final local = localProdMap[pid];
            if (local != null && local['is_synced'] == 0) {
              // Preserve pending local edits (price, name, etc.); only
              // refresh quantity and image if local lacks one.
              final updateMap = <String, dynamic>{'quantity': reconciledQty};
              final localImg = local['image_url'] as String?;
              if (localImg == null || localImg.isEmpty) {
                updateMap['image_url'] = prod['image_url'];
              }
              await txn.update(
                'products',
                updateMap,
                where: 'id = ?',
                whereArgs: [pid],
              );
              continue;
            }

            final row = Map<String, dynamic>.from(prod);
            row['quantity'] = reconciledQty;
            row['is_synced'] = 1;
            await txn.insert(
              'products',
              row,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        });
      } finally {
        await db.execute('PRAGMA foreign_keys = ON');
      }

      // ── Users ──
      final users = await _supabase.from('users').select().limit(1000);
      await db.transaction((txn) async {
        for (var user in users) {
          await txn.insert(
            'users',
            user,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });

      // ── Balance ── (single-row variable pinned at id=1, two columns)
      // Only mirror remote → local if there are no pending local changes
      // (is_synced=0 means the local value hasn't been pushed up yet).
      final localBalRow = await db.query(
        'balance',
        columns: ['is_synced'],
        where: 'id = 1',
        limit: 1,
      );
      final pendingLocal =
          localBalRow.isNotEmpty && (localBalRow.first['is_synced'] == 0);
      if (!pendingLocal) {
        final remoteCash = await BalanceRepo.getRemote(_supabase);
        final remoteCard = await BalanceRepo.getCardRemote(_supabase);
        await BalanceRepo.setLocal(db, remoteCash, isSynced: true);
        await BalanceRepo.setCardLocal(db, remoteCard, isSynced: true);
      }

      // ── Recent Sales (last 100) and their items, fetched in one query ──
      final remoteSales = await _supabase
          .from('sales')
          .select()
          .order('created_at', ascending: false)
          .limit(100);

      final saleIds = remoteSales.map((s) => s['id']).toList();
      List<dynamic> remoteItems = [];
      if (saleIds.isNotEmpty) {
        remoteItems = await _supabase
            .from('sale_items')
            .select()
            .inFilter('sale_id', saleIds);
      }

      // FK off: some referenced products may not have synced locally yet
      // (e.g. product deleted remotely, or partial previous sync).
      await db.execute('PRAGMA foreign_keys = OFF');
      try {
        await db.transaction((txn) async {
          for (var sale in remoteSales) {
            sale['is_synced'] = 1;
            await txn.insert(
              'sales',
              sale,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          for (var item in remoteItems) {
            await txn.insert(
              'sale_items',
              item,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        });
      } finally {
        await db.execute('PRAGMA foreign_keys = ON');
      }

      // ── Cards ──
      final remoteCards = await _fetchAllRows('cards');
      await db.execute('PRAGMA foreign_keys = OFF');
      try {
        await db.transaction((txn) async {
          for (var card in remoteCards) {
            await txn.insert('cards', {
              'id': card['id'],
              'name': card['name'],
              'product_id': card['productId'],
              'price': (card['price'] as num?)?.toInt() ?? 0,
              'spended_balance':
                  (card['spended_balance'] as num?)?.toInt() ?? 0,
              'created_at': card['created_at'],
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        });
      } finally {
        await db.execute('PRAGMA foreign_keys = ON');
      }

      debugPrint('✅ Sync Down Completed');
      ref.read(dbUpdateTriggerProvider.notifier).trigger();
    } on SocketException {
      debugPrint('ℹ️ Sync Down: Device is offline (Skipped)');
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup')) {
        debugPrint('ℹ️ Sync Down: No internet connection');
      } else {
        debugPrint('❌ Sync Down Error: $e');
      }
    }
  }

  Future<void> syncUp() async {
    if (_isSyncing) return; // Prevent concurrent/duplicate sync runs
    _isSyncing = true;
    try {
      final db = await LocalDatabase.instance.database;

      // 1. Sync Sales & Sale Items
      final unsyncedSales = await db.query(
        'sales',
        where: 'is_synced = ?',
        whereArgs: [0],
      );

      for (var sale in unsyncedSales) {
        final saleMap = Map<String, dynamic>.from(sale);
        final localSaleId = saleMap['id'];
        final existingRemoteId = saleMap['remote_id'];

        int remoteSaleId;

        if (existingRemoteId == null) {
          // ── Fresh upload ──
          saleMap.remove('id');
          saleMap.remove('is_synced');
          saleMap.remove('remote_id');

          // Insert Sale to Supabase
          final remoteSale = await _supabase
              .from('sales')
              .insert(saleMap)
              .select()
              .single();
          remoteSaleId = remoteSale['id'];

          // Save remote_id IMMEDIATELY — prevents duplicate insert if app
          // crashes before is_synced is set to 1.
          await db.update(
            'sales',
            {'remote_id': remoteSaleId},
            where: 'id = ?',
            whereArgs: [localSaleId],
          );

          // Cash → drawer; Card → card accumulator. Card money never
          // touches the drawer; cash never touches the card variable.
          final totalPriceNum = saleMap['total_price'] as num;
          try {
            if (saleMap['payment_type'] == 'cash') {
              await BalanceRepo.addRemote(_supabase, totalPriceNum.toInt());
            } else if (saleMap['payment_type'] == 'card') {
              await BalanceRepo.addCardRemote(_supabase, totalPriceNum.toInt());
            }
          } catch (balErr) {
            debugPrint(
              '⚠️ Error updating remote balance during syncUp: $balErr',
            );
          }
        } else {
          // ── Crash recovery: sale already uploaded, skip insert & balance ──
          remoteSaleId = existingRemoteId as int;
          debugPrint(
            'ℹ️ Sale $localSaleId already uploaded (remote: $remoteSaleId), skipping insert.',
          );
        }

        // Fetch local sale items
        final localItems = await db.query(
          'sale_items',
          where: 'sale_id = ?',
          whereArgs: [localSaleId],
        );

        for (var item in localItems) {
          final itemMap = Map<String, dynamic>.from(item);
          itemMap.remove('id');
          itemMap['sale_id'] = remoteSaleId;

          final mapToSync = Map<String, dynamic>.from(itemMap);
          mapToSync['quantity'] = (mapToSync['quantity'] as num).toInt();
          try {
            await _supabase.from('sale_items').insert(mapToSync);
          } catch (itemErr) {
            // May already exist in crash-recovery scenario — safe to ignore
            debugPrint('ℹ️ Sale item already exists or error: $itemErr');
          }
        }

        // Mark as synced locally
        await db.update(
          'sales',
          {'is_synced': 1},
          where: 'id = ?',
          whereArgs: [localSaleId],
        );
      }

      // 2. Sync Stock Movements
      final unsyncedMovements = await db.query(
        'stock_movements',
        where: 'is_synced = ?',
        whereArgs: [0],
      );
      for (var mov in unsyncedMovements) {
        final movMap = Map<String, dynamic>.from(mov);
        final localMovId = movMap['id'];
        movMap.remove('id');
        movMap.remove('is_synced');

        await _supabase.from('stock_movements').insert(movMap);

        // Update remote stock for ALL movements (Sales and Manual)
        // to ensure linkage and consistency are preserved.
        try {
          final productId = movMap['product_id'];
          final change = (movMap['change'] as num).toDouble();
          final remoteProd = await _supabase
              .from('products')
              .select('quantity')
              .eq('id', productId)
              .single();
          final currentRemoteQty = (remoteProd['quantity'] as num).toDouble();
          await _supabase
              .from('products')
              .update({'quantity': currentRemoteQty + change})
              .eq('id', productId);
        } catch (stkErr) {
          debugPrint('⚠️ Error updating remote stock for movement: $stkErr');
        }

        await db.update(
          'stock_movements',
          {'is_synced': 1},
          where: 'id = ?',
          whereArgs: [localMovId],
        );
      }

      // 3. Update Sync Products
      // If products were added offline
      final unsyncedProducts = await db.query(
        'products',
        where: 'is_synced = ?',
        whereArgs: [0],
      );
      for (var prod in unsyncedProducts) {
        final prodMap = Map<String, dynamic>.from(prod);
        final localId = prodMap['id'];
        prodMap.remove('is_synced');
        prodMap.remove('id');

        // 1. Try to update existing product
        final updateRes = await _supabase
            .from('products')
            .update(prodMap)
            .eq('id', localId)
            .select();

        if (updateRes.isEmpty) {
          // 2. If no rows updated, it's likely a NEW product added offline
          final insertRes = await _supabase
              .from('products')
              .insert(prodMap)
              .select()
              .single();
          // Re-sync local ID with the new remote ID
          await db.delete('products', where: 'id = ?', whereArgs: [localId]);
          insertRes['is_synced'] = 1;
          await db.insert('products', insertRes);
        } else {
          // 3. Successfully updated existing
          await db.update(
            'products',
            {'is_synced': 1},
            where: 'id = ?',
            whereArgs: [localId],
          );
        }
      }

      // 4. Sync Balance — push pending local value into the single remote row.
      final unsyncedBalance = await db.query(
        'balance',
        where: 'is_synced = 0',
        limit: 1,
      );
      if (unsyncedBalance.isNotEmpty) {
        final localVal =
            (unsyncedBalance.first['currentBalance'] as int?) ?? 0;
        try {
          await BalanceRepo.setRemote(_supabase, localVal);
          await db.update(
            'balance',
            {'is_synced': 1},
            where: 'id = 1',
          );
        } catch (e) {
          debugPrint('⚠️ Failed to push balance remotely: $e');
        }
      }

      debugPrint('✅ Sync Up Completed');
      ref.read(dbUpdateTriggerProvider.notifier).trigger();
    } on SocketException {
      debugPrint('ℹ️ Sync Up: Device is offline (Skipped)');
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup')) {
        debugPrint('ℹ️ Sync Up: No internet connection');
      } else {
        debugPrint('❌ Sync Up Error: $e');
      }
    } finally {
      _isSyncing = false;
    }
  }
}
