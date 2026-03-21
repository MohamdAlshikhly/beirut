import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../main.dart'; // To access global prefs
import '../models/models.dart';
import '../services/local_database.dart';
import '../services/sync_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

final isMobileProvider = Provider<bool>((ref) {
  if (kIsWeb) return false;
  return Platform.isAndroid || Platform.isIOS;
});

final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  final initialResult = await connectivity.checkConnectivity();
  yield !initialResult.contains(ConnectivityResult.none);

  await for (final result in connectivity.onConnectivityChanged) {
    yield !result.contains(ConnectivityResult.none);
  }
});

class AuthNotifier extends Notifier<AppUser?> {
  @override
  AppUser? build() {
    final savedData = prefs.getString('saved_user_data');
    if (savedData != null) {
      try {
        return AppUser.fromJson(jsonDecode(savedData));
      } catch (_) {}
    }
    return null;
  }

  void login(AppUser user) {
    state = user;
    prefs.setString(
      'saved_user_data',
      jsonEncode({
        'id': user.id,
        'name': user.name,
        'role': user.role,
        'password': user.password,
      }),
    );
  }

  void logout() {
    state = null;
    prefs.remove('saved_user_data');
  }
}

final authProvider = NotifierProvider<AuthNotifier, AppUser?>(
  () => AuthNotifier(),
);

class DbUpdateTrigger extends Notifier<int> {
  @override
  int build() => 0;
  void trigger() => state++;
}

final dbUpdateTriggerProvider = NotifierProvider<DbUpdateTrigger, int>(() {
  return DbUpdateTrigger();
});

final balanceProvider = StreamProvider<int>((ref) {
  final isMobile = ref.watch(isMobileProvider);
  final supabase = ref.read(supabaseProvider);

  if (isMobile) {
    // Mobile is ALWAYS Live & REAL-TIME
    return supabase
        .from('balance')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(1)
        .map(
          (list) =>
              list.isEmpty ? 0 : list.first['currentBalance'] as int? ?? 0,
        );
  }

  // Computer is LIVE-FIRST with FALLBACK
  ref.watch(dbUpdateTriggerProvider);

  return Stream.fromFuture(() async {
    try {
      final response = await supabase
          .from('balance')
          .select('currentBalance')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return response?['currentBalance'] as int? ?? 0;
    } catch (e) {
      debugPrint('Live balance fetch failed, falling back to local: $e');
      final db = await LocalDatabase.instance.database;
      final response = await db.query(
        'balance',
        orderBy: 'created_at DESC',
        limit: 1,
      );
      if (response.isEmpty) return 0;
      return response.first['currentBalance'] as int? ?? 0;
    }
  }());
});

final categoriesProvider = StreamProvider<List<Category>>((ref) {
  final isMobile = ref.watch(isMobileProvider);
  final supabase = ref.read(supabaseProvider);

  if (isMobile) {
    return supabase
        .from('categories')
        .stream(primaryKey: ['id'])
        .map((list) => list.map((json) => Category.fromJson(json)).toList());
  }

  return (() async* {
    try {
      yield* supabase
          .from('categories')
          .stream(primaryKey: ['id'])
          .map((list) => list.map((json) => Category.fromJson(json)).toList());
    } catch (e) {
      debugPrint('Desktop Category Stream failed, fallback to local: $e');
      ref.watch(dbUpdateTriggerProvider);
      final db = await LocalDatabase.instance.database;
      final response = await db.query('categories');
      yield response.map((json) => Category.fromJson(json)).toList();
    }
  })();
});

final productsProvider = StreamProvider<List<Product>>((ref) {
  final isMobile = ref.watch(isMobileProvider);
  final supabase = ref.read(supabaseProvider);

  if (isMobile) {
    return supabase
        .from('products')
        .stream(primaryKey: ['id'])
        .map((list) => list.map((json) => Product.fromJson(json)).toList());
  }

  return (() async* {
    try {
      yield* supabase
          .from('products')
          .stream(primaryKey: ['id'])
          .map((list) => list.map((json) => Product.fromJson(json)).toList());
    } catch (e) {
      debugPrint('Desktop Product Stream failed, fallback to local: $e');
      ref.watch(dbUpdateTriggerProvider);
      final db = await LocalDatabase.instance.database;
      final response = await db.query('products');
      yield response.map((json) => Product.fromJson(json)).toList();
    }
  })();
});

final todaySalesProvider = StreamProvider<double>((ref) {
  final isMobile = ref.watch(isMobileProvider);
  final supabase = ref.read(supabaseProvider);
  final now = DateTime.now();
  final startOfDay = DateFormat('yyyy-MM-dd').format(now);

  if (isMobile) {
    debugPrint('DEBUG: MOBILE REAL-TIME STREAM FOR TODAY SALES');
    return supabase
        .from('sales')
        .stream(primaryKey: ['id'])
        .gte('created_at', startOfDay)
        .map((list) {
          double sum = 0;
          for (var sale in list) {
            sum += (sale['total_price'] as num).toDouble();
          }
          return sum;
        });
  }

  ref.watch(dbUpdateTriggerProvider);

  return Stream.fromFuture(() async {
    try {
      final res = await supabase
          .from('sales')
          .select('total_price')
          .gte('created_at', startOfDay);
      double sum = 0;
      for (var sale in res) {
        sum += (sale['total_price'] as num).toDouble();
      }
      return sum;
    } catch (e) {
      debugPrint('Live today sales fetch failed, falling back to local: $e');
      final db = await LocalDatabase.instance.database;
      final response = await db.query(
        'sales',
        where: "date(created_at) = date('now', 'utc')",
      );
      double sum = 0;
      for (var sale in response) {
        sum += (sale['total_price'] as num).toDouble();
      }
      return sum;
    }
  }());
});

final todaySalesCountProvider = StreamProvider<int>((ref) {
  final isMobile = ref.watch(isMobileProvider);
  final supabase = ref.read(supabaseProvider);
  final now = DateTime.now();
  final startOfDay = DateFormat('yyyy-MM-dd').format(now);

  if (isMobile) {
    debugPrint('DEBUG: MOBILE REAL-TIME STREAM FOR TODAY SALES COUNT');
    return supabase
        .from('sales')
        .stream(primaryKey: ['id'])
        .gte('created_at', startOfDay)
        .map((list) => list.length);
  }

  ref.watch(dbUpdateTriggerProvider);

  return Stream.fromFuture(() async {
    try {
      final response = await supabase
          .from('sales')
          .select('id')
          .gte('created_at', startOfDay);
      return response.length;
    } catch (e) {
      debugPrint(
        'Live today sales count fetch failed, falling back to local: $e',
      );
      final db = await LocalDatabase.instance.database;
      final response = await db.query(
        'sales',
        columns: ['id'],
        where: "date(created_at) = date('now', 'utc')",
      );
      return response.length;
    }
  }());
});

class EditingSaleIdNotifier extends Notifier<int?> {
  @override
  int? build() => null;
  void set(int? id) => state = id;
}

final editingSaleIdProvider = NotifierProvider<EditingSaleIdNotifier, int?>(() {
  return EditingSaleIdNotifier();
});

class OriginalCartItemsNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() => [];
  void set(List<CartItem> items) => state = items;
}

final originalCartItemsProvider =
    NotifierProvider<OriginalCartItemsNotifier, List<CartItem>>(() {
      return OriginalCartItemsNotifier();
    });

class CartItem {
  final Product product;
  final double quantity;

  CartItem({required this.product, required this.quantity});

  CartItem copyWith({Product? product, double? quantity}) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
    );
  }
}

class CartNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() => [];

  void addProduct(Product product) {
    final existingIndex = state.indexWhere(
      (item) => item.product.id == product.id,
    );
    if (existingIndex >= 0) {
      final updatedCart = [...state];
      updatedCart[existingIndex] = updatedCart[existingIndex].copyWith(
        quantity: updatedCart[existingIndex].quantity + 1,
      );
      state = updatedCart;
    } else {
      state = [...state, CartItem(product: product, quantity: 1)];
    }
  }

  void removeProduct(int productId) {
    state = state.where((item) => item.product.id != productId).toList();
  }

  void updateQuantity(int productId, double quantity) {
    if (quantity <= 0) {
      removeProduct(productId);
      return;
    }
    final existingIndex = state.indexWhere(
      (item) => item.product.id == productId,
    );
    if (existingIndex >= 0) {
      final updatedCart = [...state];
      updatedCart[existingIndex] = updatedCart[existingIndex].copyWith(
        quantity: quantity,
      );
      state = updatedCart;
    }
  }

  void clear() {
    state = [];
    ref.read(editingSaleIdProvider.notifier).set(null);
    ref.read(originalCartItemsProvider.notifier).set([]);
  }

  void loadSale(int saleId, List<CartItem> items) {
    ref.read(editingSaleIdProvider.notifier).set(saleId);
    ref
        .read(originalCartItemsProvider.notifier)
        .set(items.map((e) => e.copyWith()).toList());
    state = items;
  }

  double get total =>
      state.fold(0, (sum, item) => sum + (item.product.price * item.quantity));
}

final cartProvider = NotifierProvider<CartNotifier, List<CartItem>>(() {
  return CartNotifier();
});

final checkoutProvider = Provider((ref) => CheckoutRepository(ref));

class CheckoutRepository {
  final Ref ref;
  CheckoutRepository(this.ref);

  Future<void> _updateDrawerBalance(Database db, double amountChange) async {
    final res = await db.query('balance', orderBy: 'created_at DESC', limit: 1);
    int currentBal = 0;
    int? id;
    if (res.isNotEmpty) {
      currentBal = res.first['currentBalance'] as int? ?? 0;
      id = res.first['id'] as int;
    }
    currentBal += amountChange.toInt();
    if (id == null) {
      await db.insert('balance', {
        'currentBalance': currentBal,
        'is_synced': 0,
      });
    } else {
      await db.update(
        'balance',
        {'currentBalance': currentBal, 'is_synced': 0},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    ref.invalidate(balanceProvider);
  }

  Future<bool> processCheckout(String paymentType) async {
    final cartItems = ref.read(cartProvider);
    if (cartItems.isEmpty) return false;

    final isMobile = ref.read(isMobileProvider);
    final supabase = ref.read(supabaseProvider);
    final total = ref.read(cartProvider.notifier).total;
    final currentUser = ref.read(authProvider);

    // 1. Try Live Checkout (Always for Mobile, Try for Computer)
    try {
      final saleResponse = await supabase
          .from('sales')
          .insert({
            'total_price': total,
            'payment_type': paymentType,
            if (currentUser != null) 'user_id': currentUser.id,
            'is_synced': true,
          })
          .select()
          .single();

      final saleId = saleResponse['id'];

      for (final item in cartItems) {
        await supabase.from('sale_items').insert({
          'sale_id': saleId,
          'product_id': item.product.id,
          'quantity': item.quantity,
          'price': item.product.price,
        });

        // Update Remote Stock directly
        final remoteProd = await supabase
            .from('products')
            .select('quantity')
            .eq('id', item.product.id)
            .single();
        final currentQty = (remoteProd['quantity'] as num).toDouble();
        await supabase
            .from('products')
            .update({'quantity': currentQty - item.quantity})
            .eq('id', item.product.id);
      }

      if (paymentType == 'cash') {
        final remoteBalRes = await supabase
            .from('balance')
            .select()
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        final currentBal = remoteBalRes?['currentBalance'] as int? ?? 0;
        await supabase.from('balance').insert({
          'currentBalance': currentBal + total.toInt(),
        });
      }

      ref.read(cartProvider.notifier).clear();
      ref.invalidate(balanceProvider);
      ref.invalidate(productsProvider);
      ref.invalidate(todaySalesProvider);
      ref.invalidate(todaySalesCountProvider);
      return true;
    } catch (e) {
      if (isMobile) {
        debugPrint('Mobile LIVE Checkout failed: $e');
        return false;
      }
      debugPrint(
        'Computer LIVE Checkout failed, falling back to Stateless Offline: $e',
      );
    }

    // 2. Stateless Offline Fallback (Computer Only)
    final db = await LocalDatabase.instance.database;

    try {
      final saleId = await db.insert('sales', {
        'total_price': total,
        'payment_type': paymentType,
        if (currentUser != null) 'user_id': currentUser.id,
        'is_synced': 0,
      });

      for (final item in cartItems) {
        await db.insert('sale_items', {
          'sale_id': saleId,
          'product_id': item.product.id,
          'quantity': item.quantity,
          'price': item.product.price,
        });

        // IMPORTANT: No local stock decrement or balance update here
        // as per user's "Stateless" requirement to avoid errors.
      }

      ref.read(cartProvider.notifier).clear();
      // No invalidations needed as we didn't update local state
      return true;
    } catch (e) {
      debugPrint('Stateless Offline Checkout error: $e');
      return false;
    }
  }

  Future<bool> updateSale(String paymentType) async {
    final cartItems = ref.read(cartProvider);
    final originalItems = ref.read(originalCartItemsProvider);
    final saleId = ref.read(editingSaleIdProvider);

    if (saleId == null || cartItems.isEmpty) return false;

    final db = await LocalDatabase.instance.database;
    final total = ref.read(cartProvider.notifier).total;

    try {
      final existingSale = (await db.query(
        'sales',
        columns: ['total_price', 'payment_type'],
        where: 'id = ?',
        whereArgs: [saleId],
      )).first;

      final oldTotal = (existingSale['total_price'] as num).toDouble();
      final oldPaymentType = existingSale['payment_type'] as String;

      if (oldPaymentType == 'cash') {
        await _updateDrawerBalance(db, -oldTotal);
      }

      await db.update(
        'sales',
        {'total_price': total, 'payment_type': paymentType, 'is_synced': 0},
        where: 'id = ?',
        whereArgs: [saleId],
      );

      if (paymentType == 'cash') {
        await _updateDrawerBalance(db, total);
      }

      Map<int, CartItem> originalMap = {
        for (var item in originalItems) item.product.id: item,
      };
      Map<int, CartItem> currentMap = {
        for (var item in cartItems) item.product.id: item,
      };

      Set<int> allProductIds = {...originalMap.keys, ...currentMap.keys};

      for (var productId in allProductIds) {
        final oldItem = originalMap[productId];
        final newItem = currentMap[productId];

        double oldQty = oldItem?.quantity ?? 0.0;
        double newQty = newItem?.quantity ?? 0.0;
        double diff = newQty - oldQty;

        if (diff != 0) {
          if (newQty == 0) {
            await db.delete(
              'sale_items',
              where: 'sale_id = ? AND product_id = ?',
              whereArgs: [saleId, productId],
            );
          } else {
            final existing = await db.query(
              'sale_items',
              where: 'sale_id = ? AND product_id = ?',
              whereArgs: [saleId, productId],
            );
            if (existing.isEmpty) {
              await db.insert('sale_items', {
                'sale_id': saleId,
                'product_id': productId,
                'quantity': newQty,
                'price': newItem!.product.price,
              });
            } else {
              await db.update(
                'sale_items',
                {'quantity': newQty},
                where: 'sale_id = ? AND product_id = ?',
                whereArgs: [saleId, productId],
              );
            }
          }

          final currentProd = (await db.query(
            'products',
            columns: ['quantity'],
            where: 'id = ?',
            whereArgs: [productId],
          )).first;
          final updatedStock =
              (currentProd['quantity'] as num).toDouble() - diff;
          await db.update(
            'products',
            {'quantity': updatedStock},
            where: 'id = ?',
            whereArgs: [productId],
          );

          await db.insert('stock_movements', {
            'product_id': productId,
            'change': -diff,
            'reason': 'تعديل فاتورة #$saleId',
            'is_synced': 0,
          });
        }
      }

      ref.read(cartProvider.notifier).clear();
      ref.invalidate(productsProvider);
      ref.invalidate(todaySalesProvider);
      ref.invalidate(todaySalesCountProvider);

      ref.read(syncServiceProvider).syncUp();

      return true;
    } catch (e) {
      debugPrint('Update sale error: $e');
      return false;
    }
  }

  Future<bool> deleteSale(int saleId) async {
    final db = await LocalDatabase.instance.database;
    try {
      final existingSale = (await db.query(
        'sales',
        where: 'id = ?',
        whereArgs: [saleId],
      )).first;
      final total = (existingSale['total_price'] as num).toDouble();
      final paymentType = existingSale['payment_type'] as String;

      if (paymentType == 'cash') {
        await _updateDrawerBalance(db, -total);
      }

      final items = await db.query(
        'sale_items',
        where: 'sale_id = ?',
        whereArgs: [saleId],
      );
      for (var item in items) {
        final productId = item['product_id'] as int;
        final qty = item['quantity'] as int;

        final prodRes = (await db.query(
          'products',
          columns: ['quantity'],
          where: 'id = ?',
          whereArgs: [productId],
        )).first;
        final currentQty = (prodRes['quantity'] as num).toDouble();
        await db.update(
          'products',
          {'quantity': currentQty + qty},
          where: 'id = ?',
          whereArgs: [productId],
        );

        await db.insert('stock_movements', {
          'product_id': productId,
          'change': qty,
          'reason': 'حذف فاتورة #$saleId',
          'is_synced': 0,
        });
      }

      await db.delete('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
      await db.delete('sales', where: 'id = ?', whereArgs: [saleId]);

      ref.invalidate(productsProvider);
      ref.invalidate(todaySalesProvider);
      ref.invalidate(todaySalesCountProvider);
      ref.read(syncServiceProvider).syncUp();

      return true;
    } catch (e) {
      debugPrint('Error deleting sale: $e');
      return false;
    }
  }
}
