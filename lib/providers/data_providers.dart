import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../main.dart'; // To access global prefs
import '../models/models.dart';
import '../services/local_database.dart';
import '../services/printing_service.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

enum SidebarView { cart, history, details }

final isMobileProvider = Provider<bool>((ref) {
  if (kIsWeb) return false;
  return Platform.isAndroid || Platform.isIOS;
});

final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

class SelectedCategoryNotifier extends Notifier<int?> {
  @override
  int? build() => null;
  void set(int? id) {
    state = id;
  }
}

final selectedCategoryProvider =
    NotifierProvider<SelectedCategoryNotifier, int?>(() {
      return SelectedCategoryNotifier();
    });

class PinnedCategoriesNotifier extends Notifier<List<int>> {
  static const _key = 'pinned_categories';

  @override
  List<int> build() {
    _load();
    return [];
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    state = list.map(int.tryParse).whereType<int>().toList();
  }

  Future<void> togglePin(int id) async {
    final newList = List<int>.from(state);
    if (newList.contains(id)) {
      newList.remove(id);
    } else {
      newList.add(id);
    }
    state = newList;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, newList.map((e) => e.toString()).toList());
  }
}

final pinnedCategoriesProvider =
    NotifierProvider<PinnedCategoriesNotifier, List<int>>(() {
      return PinnedCategoriesNotifier();
    });

final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  final initialResult = await connectivity.checkConnectivity();
  yield !initialResult.contains(ConnectivityResult.none);

  await for (final result in connectivity.onConnectivityChanged) {
    yield !result.contains(ConnectivityResult.none);
  }
});

/// Intermediate provider to deduplicate connectivity signals and prevent unnecessary rebuilds.
/// Uses a Notifier to ensure strict equality check and avoid flickering while online.
class ConnectivityNotifier extends Notifier<bool> {
  @override
  bool build() {
    final connectivity = Connectivity();

    // Initial check
    connectivity.checkConnectivity().then((result) {
      final isOnline = !result.contains(ConnectivityResult.none);
      if (state != isOnline) state = isOnline;
    });

    // Listen for changes
    connectivity.onConnectivityChanged.listen((result) {
      final isOnline = !result.contains(ConnectivityResult.none);
      if (state != isOnline) state = isOnline;
    });

    return true; // Initial assumption
  }
}

final isOnlineProvider = NotifierProvider<ConnectivityNotifier, bool>(() {
  return ConnectivityNotifier();
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

Future<void> _mirrorCategoriesToLocal(List<Map<String, dynamic>> data) async {
  try {
    final db = await LocalDatabase.instance.database;
    for (var cat in data) {
      await db.insert(
        'categories',
        {'id': cat['id'], 'name': cat['name'], 'is_synced': 1},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  } catch (e) {
    debugPrint('Mirror categories to local failed: $e');
  }
}

Future<void> _mirrorProductsToLocal(List<Map<String, dynamic>> data) async {
  final db = await LocalDatabase.instance.database;
  try {
    // Disable FK checks during mirror — categories may not be local yet
    await db.execute('PRAGMA foreign_keys = OFF');
    for (var prod in data) {
      try {
        await db.insert(
          'products',
          {
            'id': prod['id'],
            'name': prod['name'],
            'barcode': prod['barcode'],
            'price': (prod['price'] as num).toDouble(),
            'cost_price': prod['cost_price'] != null
                ? (prod['cost_price'] as num).toDouble()
                : null,
            'quantity': prod['quantity'] != null
                ? (prod['quantity'] as num).toDouble()
                : 0.0,
            'category_id': prod['category_id'],
            'image_url': prod['image_url'],
            'base_unit_id': prod['base_unit_id'],
            'base_unit_conversion': prod['base_unit_conversion'] != null
                ? (prod['base_unit_conversion'] as num).toDouble()
                : 1.0,
            'is_synced': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } catch (e) {
        debugPrint('Mirror single product ${prod['id']} failed: $e');
      }
    }
  } finally {
    await db.execute('PRAGMA foreign_keys = ON');
  }
}

final balanceProvider = StreamProvider<int>((ref) {
  final supabase = ref.read(supabaseProvider);
  final isOnline = ref.watch(isOnlineProvider);
  final isDesktop = !kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  if (isOnline && isDesktop) {
    return supabase
        .from('balance')
        .stream(primaryKey: ['id'])
        .order('id', ascending: false)
        .limit(1)
        .map((data) =>
            data.isEmpty ? 0 : (data.first['currentBalance'] as int? ?? 0));
  }

  ref.watch(dbUpdateTriggerProvider);

  return (() async* {
    try {
      if (isOnline) {
        final response = await supabase
            .from('balance')
            .select('currentBalance')
            .order('id', ascending: false)
            .limit(1)
            .maybeSingle()
            .timeout(const Duration(seconds: 5));

        yield response?['currentBalance'] as int? ?? 0;
        return;
      }
      throw Exception('Offline');
    } catch (e) {
      debugPrint('Balance fetch failed/offline: $e');
      final db = await LocalDatabase.instance.database;
      final response = await db.query('balance', orderBy: 'id DESC', limit: 1);
      yield response.isEmpty
          ? 0
          : response.first['currentBalance'] as int? ?? 0;
    }
  })();
});

final categoriesProvider = StreamProvider<List<Category>>((ref) {
  final supabase = ref.read(supabaseProvider);
  final isOnline = ref.watch(isOnlineProvider);
  final isDesktop = !kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  if (isOnline && isDesktop) {
    return supabase
        .from('categories')
        .stream(primaryKey: ['id'])
        .map((data) {
          _mirrorCategoriesToLocal(data);
          return data.map((json) => Category.fromJson(json)).toList();
        });
  }

  ref.watch(dbUpdateTriggerProvider);

  return (() async* {
    try {
      if (isOnline) {
        final response = await supabase
            .from('categories')
            .select()
            .timeout(const Duration(seconds: 5));
        final categories =
            response.map((json) => Category.fromJson(json)).toList();
        _mirrorCategoriesToLocal(response);
        yield categories;
        return;
      }
      throw Exception('Offline');
    } catch (e) {
      debugPrint('Categories Fetch failed/offline: $e');
      final db = await LocalDatabase.instance.database;
      final response = await db.query('categories');
      yield response.map((json) => Category.fromJson(json)).toList();
    }
  })();
});

final productsProvider = StreamProvider<List<Product>>((ref) {
  final supabase = ref.read(supabaseProvider);
  final isOnline = ref.watch(isOnlineProvider);
  final isDesktop = !kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  if (isOnline && isDesktop) {
    return supabase
        .from('products')
        .stream(primaryKey: ['id'])
        .map((data) {
          _mirrorProductsToLocal(data);
          return data.map((json) => Product.fromJson(json)).toList();
        });
  }

  ref.watch(dbUpdateTriggerProvider);

  return (() async* {
    try {
      if (isOnline) {
        final response = await supabase
            .from('products')
            .select()
            .timeout(const Duration(seconds: 5));
        final products =
            response.map((json) => Product.fromJson(json)).toList();
        _mirrorProductsToLocal(response);
        yield products;
        return;
      }
      throw Exception('Offline');
    } catch (e) {
      debugPrint('Products Fetch failed/offline: $e');
      final db = await LocalDatabase.instance.database;
      final response = await db.query('products');
      yield response.map((json) => Product.fromJson(json)).toList();
    }
  })();
});

class SessionNotifier extends Notifier<int?> {
  @override
  int? build() {
    return prefs.getInt('current_session_id');
  }

  void set(int? id) {
    state = id;
    if (id == null) {
      prefs.remove('current_session_id');
    } else {
      prefs.setInt('current_session_id', id);
    }
  }
}

final currentSessionIdProvider = NotifierProvider<SessionNotifier, int?>(
  () => SessionNotifier(),
);

final todaySalesProvider = StreamProvider<double>((ref) {
  final supabase = ref.read(supabaseProvider);
  final now = DateTime.now();
  // startOfDayUtc: midnight today local -> convert to UTC ISO8601
  final startOfDayUtc = DateTime(
    now.year,
    now.month,
    now.day,
  ).toUtc().toIso8601String();
  final user = ref.watch(authProvider);
  final todayLocal = DateFormat('yyyy-MM-dd').format(now);
  final isOnline = ref.watch(isOnlineProvider);
  // Always watch the trigger for manual refresh
  ref.watch(dbUpdateTriggerProvider);

  return (() async* {
    try {
      if (isOnline) {
        final res = await supabase
            .from('sales')
            .select('total_price')
            .gte('created_at', startOfDayUtc)
            .eq('user_id', user?.id ?? -1)
            .timeout(const Duration(seconds: 5));
        double sum = 0;
        for (var sale in res) {
          sum += (sale['total_price'] as num).toDouble();
        }
        yield sum;
        return;
      }
      throw Exception('Offline');
    } catch (e) {
      debugPrint('Today Sales Fetch failed/offline: $e');
      final db = await LocalDatabase.instance.database;
      final response = await db.query(
        'sales',
        where: "date(created_at, '+3 hours') = date(?) AND user_id = ?",
        whereArgs: [todayLocal, user?.id ?? -1],
      );
      double sum = 0;
      for (var sale in response) {
        sum += (sale['total_price'] as num).toDouble();
      }
      yield sum;
    }
  })();
});

final todaySalesCountProvider = StreamProvider<int>((ref) {
  final supabase = ref.read(supabaseProvider);
  final now = DateTime.now();
  final startOfDayUtc = DateTime(
    now.year,
    now.month,
    now.day,
  ).toUtc().toIso8601String();
  final user = ref.watch(authProvider);
  final todayLocal = DateFormat('yyyy-MM-dd').format(now);
  final isOnline = ref.watch(isOnlineProvider);
  // Always watch the trigger for manual refresh
  ref.watch(dbUpdateTriggerProvider);

  return (() async* {
    try {
      if (isOnline) {
        final res = await supabase
            .from('sales')
            .select('id')
            .gte('created_at', startOfDayUtc)
            .eq('user_id', user?.id ?? -1)
            .timeout(const Duration(seconds: 5));
        yield (res as List).length;
        return;
      }
      throw Exception('Offline');
    } catch (e) {
      debugPrint('Today Sales Count Fetch failed/offline: $e');
      final db = await LocalDatabase.instance.database;
      final response = await db.query(
        'sales',
        columns: ['id'],
        where: "date(created_at, '+3 hours') = date(?) AND user_id = ?",
        whereArgs: [todayLocal, user?.id ?? -1],
      );
      yield response.length;
    }
  })();
});

class EditingSaleIdNotifier extends Notifier<int?> {
  @override
  int? build() => null;
  void set(int? id) => state = id;
}

final editingSaleIdProvider = NotifierProvider<EditingSaleIdNotifier, int?>(() {
  return EditingSaleIdNotifier();
});

class SidebarViewNotifier extends Notifier<SidebarView> {
  @override
  SidebarView build() => SidebarView.cart;
  void set(SidebarView view) => state = view;
}

final sidebarViewProvider = NotifierProvider<SidebarViewNotifier, SidebarView>(
  () {
    return SidebarViewNotifier();
  },
);

class SelectedHistorySaleNotifier extends Notifier<Map<String, dynamic>?> {
  @override
  Map<String, dynamic>? build() => null;
  void set(Map<String, dynamic>? sale) => state = sale;
}

final selectedHistorySaleProvider =
    NotifierProvider<SelectedHistorySaleNotifier, Map<String, dynamic>?>(() {
      return SelectedHistorySaleNotifier();
    });

class PrintingLogsNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => [];
  void add(String log) => state = [
    ...state,
    '[${DateFormat('HH:mm:ss').format(DateTime.now())}] $log',
  ];
  void clear() => state = [];
}

final printingLogsProvider =
    NotifierProvider<PrintingLogsNotifier, List<String>>(() {
      return PrintingLogsNotifier();
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
  final double? priceOverride;

  CartItem({required this.product, required this.quantity, this.priceOverride});

  CartItem copyWith({
    Product? product,
    double? quantity,
    double? priceOverride,
  }) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      priceOverride: priceOverride ?? this.priceOverride,
    );
  }
}

class CartNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() => [];

  void addProduct(Product product, {double? priceOverride}) {
    final existingIndex = state.indexWhere(
      (item) =>
          item.product.id == product.id && item.priceOverride == priceOverride,
    );
    if (existingIndex >= 0) {
      final updatedCart = [...state];
      updatedCart[existingIndex] = updatedCart[existingIndex].copyWith(
        quantity: updatedCart[existingIndex].quantity + 1,
      );
      state = updatedCart;
    } else {
      state = [
        ...state,
        CartItem(product: product, quantity: 1, priceOverride: priceOverride),
      ];
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

  double get total => state.fold(
    0,
    (sum, item) =>
        sum + ((item.priceOverride ?? item.product.price) * item.quantity),
  );
}

final cartProvider = NotifierProvider<CartNotifier, List<CartItem>>(() {
  return CartNotifier();
});

final checkoutProvider = Provider((ref) => CheckoutRepository(ref));

class CheckoutRepository {
  final Ref ref;
  CheckoutRepository(this.ref);

  Future<void> updateStockWithLinkage({
    required int productId,
    required double change,
    required String reason,
    bool isOnline = true,
  }) async {
    final supabase = ref.read(supabaseProvider);
    final db = await LocalDatabase.instance.database;

    // 1. Fetch products involved locally first to get linkage info
    final localProds = await db.query('products');
    final allProducts = localProds
        .map((json) => Product.fromJson(json))
        .toList();
    final product = allProducts.firstWhere((p) => p.id == productId);

    // List of updates to perform: {id: change}
    Map<int, double> updates = {productId: change};

    // Linkage: If this is a Box, update the Can
    if (product.baseUnitId != null) {
      updates[product.baseUnitId!] = change * product.baseUnitConversion;
    }

    // Reverse Linkage: If this is a Can, update all Boxes that link to it
    for (var p in allProducts) {
      if (p.baseUnitId == productId) {
        updates[p.id] = change / p.baseUnitConversion;
      }
    }

    // Execute Updates
    for (var entry in updates.entries) {
      final pid = entry.key;
      final val = entry.value;

      if (isOnline) {
        try {
          final res = await supabase
              .from('products')
              .select('quantity')
              .eq('id', pid)
              .maybeSingle();

          if (res != null) {
            final current = (res['quantity'] as num).toDouble();
            await supabase
                .from('products')
                .update({'quantity': current + val})
                .eq('id', pid);
            await supabase.from('stock_movements').insert({
              'product_id': pid,
              'change': val,
              'reason': reason,
            });
          }
        } catch (e) {
          debugPrint('Online stock update failed for $pid: $e');
        }
      }

      // Always update local for consistency (sync will handle it later if offline)
      try {
        final localRes = await db.query(
          'products',
          where: 'id = ?',
          whereArgs: [pid],
        );
        if (localRes.isNotEmpty) {
          final current = (localRes.first['quantity'] as num).toDouble();
          await db.update(
            'products',
            {'quantity': current + val, 'is_synced': isOnline ? 1 : 0},
            where: 'id = ?',
            whereArgs: [pid],
          );
          await db.insert('stock_movements', {
            'product_id': pid,
            'change': val,
            'reason': reason,
            'is_synced': isOnline ? 1 : 0,
          });
        }
      } catch (e) {
        debugPrint('Local stock update failed for $pid: $e');
      }
    }
  }

  Future<void> _updateDrawerBalance(Database db, double amountChange) async {
    final res = await db.query('balance', orderBy: 'id DESC', limit: 1);
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

  Future<int?> processCheckout(String paymentType) async {
    final cartItems = ref.read(cartProvider);
    if (cartItems.isEmpty) return null;

    final supabase = ref.read(supabaseProvider);
    final total = ref.read(cartProvider.notifier).total;
    final currentUser = ref.read(authProvider);
    final db = await LocalDatabase.instance.database;

    // ONLINE-FIRST TRANSACTION
    try {
      // 1. Insert Sale
      final saleResponse = await supabase
          .from('sales')
          .insert({
            'total_price': total,
            'payment_type': paymentType,
            if (currentUser != null) 'user_id': currentUser.id,
          })
          .select()
          .single();

      final saleId = saleResponse['id'];

      // 2. Insert Sale Items (Synchronously)
      for (final item in cartItems) {
        final itemPrice = item.priceOverride ?? item.product.price;
        await supabase.from('sale_items').insert({
          'sale_id': saleId,
          'product_id': item.product.id,
          'quantity': item.quantity.toInt(),
          'price': itemPrice,
        });

        // 3. Update Stock with Linkage (Remote) - Await each to be sure
        await updateStockWithLinkage(
          productId: item.product.id,
          change: -item.quantity,
          reason: 'بيع في فاتورة #$saleId (Online)',
          isOnline: true,
        );
      }

      // 4. Update Balance and Log (Online)
      if (paymentType == 'cash') {
        // Centralized call to logAndOpen which handles balance update
        await ref.read(cashDrawerProvider).logAndOpen(
          type: 'open',
          reason: 'بيع في فاتورة #$saleId (تلقائي)',
          amount: total,
        );
      }

      // 5. Update Local DB for sync consistency using the remote saleId
      try {
        await db.insert(
          'sales',
          {
            'id': saleId,
            'total_price': total,
            'payment_type': paymentType,
            if (currentUser != null) 'user_id': currentUser.id,
            'is_synced': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        for (final item in cartItems) {
          final itemPrice = item.priceOverride ?? item.product.price;
          await db.insert(
            'sale_items',
            {
              'sale_id': saleId,
              'product_id': item.product.id,
              'quantity': item.quantity.toInt(),
              'price': itemPrice,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      } catch (localError) {
        debugPrint('Local mirror update failed: $localError');
      }

      ref.read(cartProvider.notifier).clear();
      ref.invalidate(balanceProvider);
      // ref.invalidate(productsProvider); // Removed to prevent flickering while online
      ref.invalidate(todaySalesProvider);
      ref.invalidate(todaySalesCountProvider);
      return saleId;
    } catch (onlineError) {
      debugPrint('Online checkout failed: $onlineError');

      // OFFLINE FALLBACK (Only if internet fails)
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

          // In offline mode, we update local stock if possible to keep business running
          await updateStockWithLinkage(
            productId: item.product.id,
            change: -item.quantity,
            reason: 'بيع أوفلاين #$saleId',
            isOnline: false,
          );
        }
        if (paymentType == 'cash') {
          await ref.read(cashDrawerProvider).logAndOpen(
            type: 'open',
            reason: 'بيع أوفلاين #$saleId',
            amount: total.toDouble(),
          );
        }

        ref.read(cartProvider.notifier).clear();
        ref
            .read(dbUpdateTriggerProvider.notifier)
            .trigger(); // Explicitly trigger update for offline UI
        ref.invalidate(balanceProvider);
        ref.invalidate(productsProvider);
        ref.invalidate(todaySalesProvider);
        ref.invalidate(todaySalesCountProvider);
        return saleId;
      } catch (offlineError) {
        debugPrint('Offline checkout also failed: $offlineError');
        return null;
      }
    }
  }

  Future<int?> updateSale(String paymentType) async {
    final cartItems = ref.read(cartProvider);
    final originalItems = ref.read(originalCartItemsProvider);
    final saleId = ref.read(editingSaleIdProvider);

    if (saleId == null || cartItems.isEmpty) return null;

    final supabase = ref.read(supabaseProvider);
    final db = await LocalDatabase.instance.database;
    final total = ref.read(cartProvider.notifier).total;

    // ONLINE-FIRST TRANSACTION
    try {
      // 1. Get original sale from Supabase to calculate diff
      final existingSale = await supabase
          .from('sales')
          .select()
          .eq('id', saleId)
          .single();

      final oldTotal = (existingSale['total_price'] as num).toDouble();
      final oldPaymentType = existingSale['payment_type'] as String;

      // 2. Adjust Balance (Online)
      if (oldPaymentType == 'cash') {
        final remoteBalRes = await supabase
            .from('balance')
            .select()
            .order('id', ascending: false)
            .limit(1)
            .maybeSingle();
        final currentBal = remoteBalRes?['currentBalance'] as int? ?? 0;
        await supabase.from('balance').insert({
          'currentBalance': currentBal - oldTotal.toInt(),
        });
      }

      // 3. Update Sale (Online)
      await supabase
          .from('sales')
          .update({'total_price': total, 'payment_type': paymentType})
          .eq('id', saleId);

      if (paymentType == 'cash') {
        final lastBalRes = await supabase
            .from('balance')
            .select()
            .order('id', ascending: false)
            .limit(1)
            .maybeSingle();
        final lastBal = lastBalRes?['currentBalance'] as int? ?? 0;
        await supabase.from('balance').insert({
          'currentBalance': lastBal + total.toInt(),
        });
      }

      // 4. Update Items (Delete and Re-insert for Online Simplicity)
      bool onlineSuccess = false;
      try {
        await supabase.from('sale_items').delete().eq('sale_id', saleId);
        for (final item in cartItems) {
          final itemPrice = item.priceOverride ?? item.product.price;
          await supabase.from('sale_items').insert({
            'sale_id': saleId,
            'product_id': item.product.id,
            'quantity': item.quantity.toInt(),
            'price': itemPrice,
          });
        }
        onlineSuccess = true;
      } catch (e) {
        debugPrint('Online update failed: $e');
      }
      if (!onlineSuccess) return null;

      // 5. Reconcile Stock (Diff calculation)
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
          await updateStockWithLinkage(
            productId: productId,
            change: -diff,
            reason: 'تعديل فاتورة #$saleId (Online)',
            isOnline: true,
          );
        }
      }

      // 6. Local Mirror Update
      try {
        await db.update(
          'sales',
          {'total_price': total, 'payment_type': paymentType, 'is_synced': 1},
          where: 'id = ?',
          whereArgs: [saleId],
        );
        await db.delete(
          'sale_items',
          where: 'sale_id = ?',
          whereArgs: [saleId],
        );
        for (final item in cartItems) {
          final itemPrice = item.priceOverride ?? item.product.price;
          await db.insert('sale_items', {
            'sale_id': saleId,
            'product_id': item.product.id,
            'quantity': item.quantity,
            'price': itemPrice,
          });
        }
      } catch (lErr) {
        debugPrint('Local mirror update error during edit: $lErr');
      }

      ref.read(cartProvider.notifier).clear();
      ref.invalidate(balanceProvider);
      ref.invalidate(todaySalesProvider);
      ref.invalidate(todaySalesCountProvider);
      return saleId;
    } catch (onlineError) {
      debugPrint('Online sale update failed: $onlineError');
      // OFFLINE FALLBACK
      try {
        final existingSaleRes = (await db.query(
          'sales',
          columns: ['total_price', 'payment_type'],
          where: 'id = ?',
          whereArgs: [saleId],
        ));
        if (existingSaleRes.isEmpty) return null;
        final existingSale = existingSaleRes.first;

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
              final itemPrice = newItem!.priceOverride ?? newItem.product.price;
              if (existing.isEmpty) {
                await db.insert('sale_items', {
                  'sale_id': saleId,
                  'product_id': productId,
                  'quantity': newQty,
                  'price': itemPrice,
                });
              } else {
                await db.update(
                  'sale_items',
                  {'quantity': newQty, 'price': itemPrice},
                  where: 'sale_id = ? AND product_id = ?',
                  whereArgs: [saleId, productId],
                );
              }
            }
            await updateStockWithLinkage(
              productId: productId,
              change: -diff,
              reason: 'تعديل أوفلاين #$saleId',
              isOnline: false,
            );
          }
        }

        ref.read(cartProvider.notifier).clear();
        ref.invalidate(productsProvider);
        ref.invalidate(todaySalesProvider);
        ref.invalidate(todaySalesCountProvider);
        return saleId;
      } catch (offlineError) {
        debugPrint('Offline sale update also failed: $offlineError');
        return null;
      }
    }
  }

  Future<bool> deleteSale(int saleId) async {
    final supabase = ref.read(supabaseProvider);
    final db = await LocalDatabase.instance.database;

    // ONLINE-FIRST TRANSACTION
    try {
      // 1. Revert Balance & Stock Online
      final existingSale = await supabase
          .from('sales')
          .select()
          .eq('id', saleId)
          .single();
      final total = (existingSale['total_price'] as num).toDouble();
      final paymentType = existingSale['payment_type'] as String;

      if (paymentType == 'cash') {
        final remoteBalRes = await supabase
            .from('balance')
            .select()
            .order('id', ascending: false)
            .limit(1)
            .maybeSingle();
        final currentBal = remoteBalRes?['currentBalance'] as int? ?? 0;
        await supabase.from('balance').insert({
          'currentBalance': currentBal - total.toInt(),
        });
      }

      final items = await supabase
          .from('sale_items')
          .select()
          .eq('sale_id', saleId);
      for (var item in items) {
        await updateStockWithLinkage(
          productId: item['product_id'],
          change: (item['quantity'] as num).toDouble(),
          reason: 'إرجاع فاتورة #$saleId (Online)',
          isOnline: true,
        );
      }

      // 2. Delete Online
      await supabase.from('sale_items').delete().eq('sale_id', saleId);
      await supabase.from('sales').delete().eq('id', saleId);

      // 3. Mirror Local
      try {
        await db.delete(
          'sale_items',
          where: 'sale_id = ?',
          whereArgs: [saleId],
        );
        await db.delete('sales', where: 'id = ?', whereArgs: [saleId]);
      } catch (lErr) {
        debugPrint('Local mirror delete error: $lErr');
      }

      ref.invalidate(balanceProvider);
      ref.invalidate(todaySalesProvider);
      ref.invalidate(todaySalesCountProvider);
      return true;
    } catch (onlineError) {
      debugPrint('Online deletion failed: $onlineError');
      // OFFLINE FALLBACK
      try {
        final res = await db.query(
          'sales',
          where: 'id = ?',
          whereArgs: [saleId],
        );
        if (res.isEmpty) return false;
        final total = (res.first['total_price'] as num).toDouble();
        final pType = res.first['payment_type'] as String;

        if (pType == 'cash') await _updateDrawerBalance(db, -total);

        final items = await db.query(
          'sale_items',
          where: 'sale_id = ?',
          whereArgs: [saleId],
        );
        for (var itm in items) {
          await updateStockWithLinkage(
            productId: itm['product_id'] as int,
            change: (itm['quantity'] as num).toDouble(),
            reason: 'إرجاع أوفلاين #$saleId',
            isOnline: false,
          );
        }

        await db.delete(
          'sale_items',
          where: 'sale_id = ?',
          whereArgs: [saleId],
        );
        await db.delete('sales', where: 'id = ?', whereArgs: [saleId]);

        ref.invalidate(balanceProvider);
        ref.invalidate(productsProvider);
        ref.invalidate(todaySalesProvider);
        ref.invalidate(todaySalesCountProvider);
        return true;
      } catch (offErr) {
        debugPrint('Offline deletion also failed: $offErr');
        return false;
      }
    }
  }
}
final cashDrawerProvider = Provider((ref) => CashDrawerRepository(ref));

class CashDrawerRepository {
  final Ref ref;
  CashDrawerRepository(this.ref);

  Future<void> logAndOpen({
    required String type, // 'open', 'add', 'withdraw'
    String? reason,
    double amount = 0,
  }) async {
    final printingService = ref.read(printingServiceProvider);
    final currentUser = ref.read(authProvider);
    final db = await LocalDatabase.instance.database;
    final supabase = ref.read(supabaseProvider);
    final isOnline = ref.read(isOnlineProvider);

    // 1. Open the physical drawer
    try {
      await printingService.openCashDrawer();
    } catch (e) {
      debugPrint('Failed to open cash drawer: $e');
    }

    // 2. Log the transaction
    final logMap = {
      'type': type,
      'reason': reason,
      'amount': amount,
      'user_id': currentUser?.id,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (isOnline) {
      try {
        // Create a copy of the log map for Supabase
        final onlineLogMap = Map<String, dynamic>.from(logMap);
        
        // Use the custom user_id (bigint) instead of auth UUID
        onlineLogMap['user_id'] = currentUser?.id;

        await supabase.from('cash_drawer_logs').insert(onlineLogMap);
        
        // Update balance table if amount is changed
        if (amount != 0) {
          final remoteBalRes = await supabase
              .from('balance')
              .select()
              .order('id', ascending: false)
              .limit(1)
              .maybeSingle();

          final currentBal = remoteBalRes?['currentBalance'] as int? ?? 0;
          await supabase.from('balance').insert({
            'currentBalance': currentBal + amount.toInt(),
          });
        }
        
        logMap['is_synced'] = 1;
      } catch (e) {
        debugPrint('Failed to log cash drawer online: $e');
        logMap['is_synced'] = 0;
      }
    } else {
      logMap['is_synced'] = 0;
    }

    try {
      await db.insert('cash_drawer_logs', logMap);
    } catch (e) {
      debugPrint('Failed to log cash drawer locally: $e');
    }

    // 3. Update balance if it's an add/withdraw
    if (type == 'add' || type == 'withdraw') {
      final change = type == 'add' ? amount : -amount;
      
      final res = await db.query('balance', orderBy: 'id DESC', limit: 1);
      int currentBal = 0;
      int? balId;
      if (res.isNotEmpty) {
        currentBal = res.first['currentBalance'] as int? ?? 0;
        balId = res.first['id'] as int;
      }
      currentBal += change.toInt();
      
      if (balId == null) {
        await db.insert('balance', {'currentBalance': currentBal, 'is_synced': 0});
      } else {
        await db.update('balance', {'currentBalance': currentBal, 'is_synced': 0}, where: 'id = ?', whereArgs: [balId]);
      }

      if (isOnline) {
        try {
          final remoteBalRes = await supabase
              .from('balance')
              .select()
              .order('id', ascending: false)
              .limit(1)
              .maybeSingle();
          final remoteCurrentBal = remoteBalRes?['currentBalance'] as int? ?? 0;
          await supabase.from('balance').insert({
            'currentBalance': remoteCurrentBal + change.toInt(),
          });
        } catch (e) {
          debugPrint('Failed to update remote balance: $e');
        }
      }
      ref.invalidate(balanceProvider);
    }
  }
}
