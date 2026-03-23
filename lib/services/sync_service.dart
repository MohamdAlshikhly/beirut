import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'local_database.dart';
import '../providers/data_providers.dart';

final syncServiceProvider = Provider((ref) => SyncService(ref));

class SyncService {
  final Ref ref;
  SyncService(this.ref);

  final _supabase = Supabase.instance.client;

  Future<void> syncDown() async {
    try {
      final db = await LocalDatabase.instance.database;

      // Sync Categories
      final categories = await _supabase.from('categories').select();
      for (var cat in categories) {
        cat['is_synced'] = 1;
        await db.insert(
          'categories',
          cat,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // Sync Products (Smart Reconciliation: Remote + Unsynced Local Adjustments)
      final products = await _supabase.from('products').select();
      for (var prod in products) {
        final localProdRes = await db.query(
          'products',
          where: 'id = ?',
          whereArgs: [prod['id']],
        );

        // 1. Calculate sum of all local adjustments not yet synced
        double unsyncedAdjust = 0;
        final unsyncedMovements = await db.query(
          'stock_movements',
          where: 'product_id = ? AND is_synced = 0',
          whereArgs: [prod['id']],
        );
        for (var mov in unsyncedMovements) {
          unsyncedAdjust += (mov['change'] as num).toDouble();
        }

        final remoteQty = (prod['quantity'] as num?)?.toDouble() ?? 0.0;
        final reconciledQty = remoteQty + unsyncedAdjust;

        if (localProdRes.isNotEmpty) {
          final localProd = localProdRes.first;
          if (localProd['is_synced'] == 0) {
            // Product has pending local edits (price, name, etc.)
            // We update quantity AND image_url to handle global changes
            final updatedMap = Map<String, dynamic>.from(localProd);
            updatedMap['quantity'] = reconciledQty;
            // Always take the remote image if the local one is null
            if (updatedMap['image_url'] == null ||
                updatedMap['image_url'].toString().isEmpty) {
              updatedMap['image_url'] = prod['image_url'];
            }
            await db.update(
              'products',
              updatedMap,
              where: 'id = ?',
              whereArgs: [prod['id']],
            );
            continue;
          }
        }

        // Default: Update local with remote data but reconciled quantity
        prod['quantity'] = reconciledQty;
        prod['is_synced'] = 1;
        await db.insert(
          'products',
          prod,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // Sync Users
      final users = await _supabase.from('users').select();
      for (var user in users) {
        await db.insert(
          'users',
          user,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // Sync Balance Down
      final remoteBalRes = await _supabase
          .from('balance')
          .select()
          .order('created_at', ascending: false)
          .limit(1);

      if (remoteBalRes.isNotEmpty) {
        final remoteBal = remoteBalRes.first;
        final localBalRes = await db.query('balance', limit: 1);
        if (localBalRes.isNotEmpty) {
          final localBal = localBalRes.first;
          if (localBal['is_synced'] == 1) {
            // Only update if local version is already synced
            await db.update(
              'balance',
              {'currentBalance': remoteBal['currentBalance'], 'is_synced': 1},
              where: 'id = ?',
              whereArgs: [localBal['id']],
            );
          }
        } else {
          // Local balance is empty, insert first record
          await db.insert('balance', {
            'currentBalance': remoteBal['currentBalance'],
            'is_synced': 1,
          });
        }
      }

      // Sync Recent Sales (Last 100 to show on mobile history/dashboard)
      final remoteSales = await _supabase
          .from('sales')
          .select()
          .order('created_at', ascending: false)
          .limit(100);

      for (var sale in remoteSales) {
        sale['is_synced'] = 1;
        await db.insert(
          'sales',
          sale,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        // Fetch and sync sale items for these sales
        final remoteItems = await _supabase
            .from('sale_items')
            .select()
            .eq('sale_id', sale['id']);
        for (var item in remoteItems) {
          await db.insert(
            'sale_items',
            item,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
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

        saleMap.remove('id');
        saleMap.remove('is_synced');

        // Insert Sale to Supabase
        final remoteSale = await _supabase
            .from('sales')
            .insert(saleMap)
            .select()
            .single();
        final remoteSaleId = remoteSale['id'];

        // If cash sale, update remote balance (Stateless Reconciliation)
        if (saleMap['payment_type'] == 'cash') {
          try {
            final totalPriceNum = saleMap['total_price'] as num;
            final remoteBalRes = await _supabase
                .from('balance')
                .select()
                .order('created_at', ascending: false)
                .limit(1)
                .maybeSingle();
            final currentBal = remoteBalRes?['currentBalance'] as int? ?? 0;
            await _supabase.from('balance').insert({
              'currentBalance': currentBal + totalPriceNum.toInt(),
            });
          } catch (balErr) {
            debugPrint(
              '⚠️ Error updating remote balance during syncUp: $balErr',
            );
          }
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
          await _supabase.from('sale_items').insert(mapToSync);

          // Update Remote Stock
          try {
            final productId = itemMap['product_id'];
            final soldQty = (itemMap['quantity'] as num).toDouble();
            final remoteProd = await _supabase
                .from('products')
                .select('quantity')
                .eq('id', productId)
                .single();
            final currentRemoteQty = (remoteProd['quantity'] as num).toDouble();
            await _supabase
                .from('products')
                .update({'quantity': currentRemoteQty - soldQty})
                .eq('id', productId);
          } catch (stkErr) {
            debugPrint('⚠️ Error updating remote stock for sale item: $stkErr');
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

        // If it's a manual stock movement (not from a sale), update remote stock
        // (Movements from sales are already handled above in the sale items loop)
        if (!(movMap['reason']?.toString().startsWith('Sale #') ?? false)) {
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

      // 4. Sync Balance
      final unsyncedBalance = await db.query(
        'balance',
        where: 'is_synced = ?',
        whereArgs: [0],
      );
      for (var bal in unsyncedBalance) {
        final balMap = Map<String, dynamic>.from(bal);
        final localId = balMap['id'];
        balMap.remove('id');
        balMap.remove('is_synced');

        // Check if there's an existing balance record on Supabase (usually just 1)
        final remoteBalRes = await _supabase
            .from('balance')
            .select()
            .order('created_at', ascending: false)
            .limit(1);

        if (remoteBalRes.isNotEmpty) {
          final remoteId = remoteBalRes.first['id'];
          await _supabase.from('balance').update(balMap).eq('id', remoteId);
        } else {
          await _supabase.from('balance').insert(balMap);
        }

        await db.update(
          'balance',
          {'is_synced': 1},
          where: 'id = ?',
          whereArgs: [localId],
        );
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
    }
  }
}
