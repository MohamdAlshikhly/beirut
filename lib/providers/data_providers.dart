import 'package:flutter/foundation.dart' hide Category; // also provides kIsWeb
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
import '../services/stock_service.dart';
import 'package:uuid/uuid.dart';

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

/// Centralized read/write helper for the two cash-drawer / card balances.
/// The balance table is a single-row variable pinned at id=1:
///   - `currentBalance` → physical cash drawer.
///   - `cardBalance`    → accumulated card-payment revenue.
/// Every mutation upserts the same row rather than inserting history, and
/// card sales only ever touch `cardBalance` (drawer untouched).
class BalanceRepo {
  static const int _rowId = 1;
  static const String _kCash = 'currentBalance';
  static const String _kCard = 'cardBalance';

  // ── Cash (drawer) ───────────────────────────────────────────────────────
  static Future<int> getRemote(SupabaseClient supabase) =>
      _getRemoteCol(supabase, _kCash);
  static Future<void> setRemote(SupabaseClient supabase, int value) =>
      _setRemoteCol(supabase, _kCash, value);
  static Future<void> addRemote(SupabaseClient supabase, int delta) =>
      _addRemoteCol(supabase, _kCash, delta);
  static Future<int> getLocal(Database db) => _getLocalCol(db, _kCash);
  static Future<void> setLocal(Database db, int value,
          {required bool isSynced}) =>
      _setLocalCol(db, _kCash, value, isSynced: isSynced);
  static Future<void> addLocal(Database db, int delta,
          {required bool isSynced}) =>
      _addLocalCol(db, _kCash, delta, isSynced: isSynced);

  // ── Card (processor revenue) ────────────────────────────────────────────
  static Future<int> getCardRemote(SupabaseClient supabase) =>
      _getRemoteCol(supabase, _kCard);
  static Future<void> setCardRemote(SupabaseClient supabase, int value) =>
      _setRemoteCol(supabase, _kCard, value);
  static Future<void> addCardRemote(SupabaseClient supabase, int delta) =>
      _addRemoteCol(supabase, _kCard, delta);
  static Future<int> getCardLocal(Database db) => _getLocalCol(db, _kCard);
  static Future<void> setCardLocal(Database db, int value,
          {required bool isSynced}) =>
      _setLocalCol(db, _kCard, value, isSynced: isSynced);
  static Future<void> addCardLocal(Database db, int delta,
          {required bool isSynced}) =>
      _addLocalCol(db, _kCard, delta, isSynced: isSynced);

  // ── Shared implementation ───────────────────────────────────────────────
  static Future<int> _getRemoteCol(
      SupabaseClient supabase, String column) async {
    try {
      final res = await supabase
          .from('balance')
          .select(column)
          .eq('id', _rowId)
          .maybeSingle();
      if (res != null) return (res[column] as num?)?.toInt() ?? 0;
      // Legacy fallback: older schemas with id != 1 — use the latest row.
      final fallback = await supabase
          .from('balance')
          .select(column)
          .order('id', ascending: false)
          .limit(1)
          .maybeSingle();
      return (fallback?[column] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> _setRemoteCol(
      SupabaseClient supabase, String column, int value) async {
    await supabase
        .from('balance')
        .upsert({'id': _rowId, column: value});
  }

  static Future<void> _addRemoteCol(
      SupabaseClient supabase, String column, int delta) async {
    if (delta == 0) return;
    final current = await _getRemoteCol(supabase, column);
    await _setRemoteCol(supabase, column, current + delta);
  }

  static Future<int> _getLocalCol(Database db, String column) async {
    final rows = await db.query(
      'balance',
      columns: [column],
      where: 'id = ?',
      whereArgs: [_rowId],
      limit: 1,
    );
    if (rows.isNotEmpty) return (rows.first[column] as int?) ?? 0;
    final any = await db.query(
      'balance',
      columns: [column],
      orderBy: 'id DESC',
      limit: 1,
    );
    return any.isEmpty ? 0 : ((any.first[column] as int?) ?? 0);
  }

  static Future<void> _setLocalCol(
    Database db,
    String column,
    int value, {
    required bool isSynced,
  }) async {
    // UPDATE-or-INSERT so we only touch the specified column and never
    // clobber the other balance field (cash / card are independent).
    final exists = await db.query(
      'balance',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [_rowId],
      limit: 1,
    );
    if (exists.isNotEmpty) {
      await db.update(
        'balance',
        {column: value, 'is_synced': isSynced ? 1 : 0},
        where: 'id = ?',
        whereArgs: [_rowId],
      );
    } else {
      await db.insert('balance', {
        'id': _rowId,
        column: value,
        'is_synced': isSynced ? 1 : 0,
      });
    }
  }

  static Future<void> _addLocalCol(
    Database db,
    String column,
    int delta, {
    required bool isSynced,
  }) async {
    if (delta == 0) return;
    final current = await _getLocalCol(db, column);
    await _setLocalCol(db, column, current + delta, isSynced: isSynced);
  }
}

/// Fetches every row from [table] by paginating with `.range()`. Supabase's
/// default PostgREST max_rows is 1000, so `.limit(N)` caps at 1000 on the
/// server regardless of the client value. Pagination is the only way to
/// retrieve more.
Future<List<Map<String, dynamic>>> _fetchAllRows(
  SupabaseClient supabase,
  String table, {
  int pageSize = 1000,
}) async {
  final List<Map<String, dynamic>> all = [];
  int from = 0;
  while (true) {
    final chunk = await supabase
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
    // Reconcile remote quantity against unsynced local stock_movements and
    // preserve rows the local user has edited but not yet pushed. Without
    // this, a remote refetch right after a desktop sale would overwrite the
    // locally-decremented quantity (and clear is_synced) before syncUp had a
    // chance to push the movement, leaving local and remote permanently out
    // of sync. Mirrors the logic in SyncService.syncDown.
    final localProdRows = await db.query(
      'products',
      columns: ['id', 'is_synced'],
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

    // Disable FK checks during mirror — categories may not be local yet
    await db.execute('PRAGMA foreign_keys = OFF');
    for (var prod in data) {
      try {
        final pid = prod['id'] as int;
        final remoteQty = (prod['quantity'] as num?)?.toDouble() ?? 0.0;
        final reconciledQty = remoteQty + (unsyncedAdjustMap[pid] ?? 0);

        final local = localProdMap[pid];
        if (local != null && local['is_synced'] == 0) {
          // Preserve pending local edits (price/name/etc); only refresh
          // quantity, reconciled with any unsynced movements.
          await db.update(
            'products',
            {'quantity': reconciledQty},
            where: 'id = ?',
            whereArgs: [pid],
          );
          continue;
        }

        await db.insert(
          'products',
          {
            'id': pid,
            'name': prod['name'],
            'barcode': prod['barcode'],
            'price': (prod['price'] as num).toDouble(),
            'cost_price': prod['cost_price'] != null
                ? (prod['cost_price'] as num).toDouble()
                : null,
            'quantity': reconciledQty,
            'category_id': prod['category_id'],
            'image_url': prod['image_url'],
            'base_unit_id': prod['base_unit_id'],
            'base_unit_conversion': prod['base_unit_conversion'] != null
                ? (prod['base_unit_conversion'] as num).toDouble()
                : 1.0,
            'is_card': (prod['is_card'] as num?)?.toInt() ?? 0,
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
    // Single-row variable pinned at id=1 — stream just that row so remote
    // updates push down instantly without legacy history noise.
    return supabase
        .from('balance')
        .stream(primaryKey: ['id'])
        .eq('id', 1)
        .map((data) =>
            data.isEmpty ? 0 : (data.first['currentBalance'] as int? ?? 0));
  }

  ref.watch(dbUpdateTriggerProvider);

  return (() async* {
    try {
      if (isOnline) {
        final value = await BalanceRepo.getRemote(supabase)
            .timeout(const Duration(seconds: 5));
        yield value;
        return;
      }
      throw Exception('Offline');
    } catch (e) {
      debugPrint('Balance fetch failed/offline: $e');
      final db = await LocalDatabase.instance.database;
      yield await BalanceRepo.getLocal(db);
    }
  })();
});

/// Accumulated card-payment revenue. Stored on the same single-row
/// balance record as the drawer balance (column `cardBalance`) so card
/// sales never touch the drawer and vice versa.
final cardBalanceProvider = StreamProvider<int>((ref) {
  final supabase = ref.read(supabaseProvider);
  final isOnline = ref.watch(isOnlineProvider);
  final isDesktop = !kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  if (isOnline && isDesktop) {
    return supabase
        .from('balance')
        .stream(primaryKey: ['id'])
        .eq('id', 1)
        .map((data) =>
            data.isEmpty ? 0 : (data.first['cardBalance'] as int? ?? 0));
  }

  ref.watch(dbUpdateTriggerProvider);

  return (() async* {
    try {
      if (isOnline) {
        final value = await BalanceRepo.getCardRemote(supabase)
            .timeout(const Duration(seconds: 5));
        yield value;
        return;
      }
      throw Exception('Offline');
    } catch (e) {
      debugPrint('Card balance fetch failed/offline: $e');
      final db = await LocalDatabase.instance.database;
      yield await BalanceRepo.getCardLocal(db);
    }
  })();
});

/// Subscribes to realtime changes on [table] and bumps the global trigger on
/// any change, causing providers that depend on it to re-fetch. Replaces the
/// previous `.stream()` approach, which silently capped at the server's
/// max_rows (1000) regardless of client-side `.limit()`.
void _watchTableForRefresh(Ref ref, String table, String channelName) {
  final supabase = ref.read(supabaseProvider);
  final isDesktop = !kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  if (!isDesktop) return;

  final channel = supabase.channel(channelName);
  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) {
          ref.read(dbUpdateTriggerProvider.notifier).trigger();
        },
      )
      .subscribe();
  ref.onDispose(() => channel.unsubscribe());
}

final categoriesProvider = StreamProvider<List<Category>>((ref) {
  final supabase = ref.read(supabaseProvider);
  final isOnline = ref.watch(isOnlineProvider);
  ref.watch(dbUpdateTriggerProvider);

  return (() async* {
    try {
      if (isOnline) {
        final response = await _fetchAllRows(supabase, 'categories')
            .timeout(const Duration(seconds: 20));
        final categories =
            response.map((json) => Category.fromJson(json)).toList();
        _mirrorCategoriesToLocal(response);
        yield categories;
        _watchTableForRefresh(ref, 'categories', 'categories_auto_refresh');
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
  ref.watch(dbUpdateTriggerProvider);

  return (() async* {
    try {
      if (isOnline) {
        final response = await _fetchAllRows(supabase, 'products')
            .timeout(const Duration(seconds: 30));
        final products =
            response.map((json) => Product.fromJson(json)).toList();
        _mirrorProductsToLocal(response);
        yield products;
        _watchTableForRefresh(ref, 'products', 'products_auto_refresh');
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
  final int? cardId; // set when product.isCard, tracks which card was selected

  CartItem({
    required this.product,
    required this.quantity,
    this.priceOverride,
    this.cardId,
  });

  CartItem copyWith({
    Product? product,
    double? quantity,
    double? priceOverride,
    int? cardId,
  }) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      priceOverride: priceOverride ?? this.priceOverride,
      cardId: cardId ?? this.cardId,
    );
  }
}

class CartNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() => [];

  void addProduct(Product product, {double? priceOverride, int? cardId}) {
    // Card items are always separate entries (each card is a distinct item)
    if (cardId != null) {
      state = [
        CartItem(
          product: product,
          quantity: 1,
          priceOverride: priceOverride,
          cardId: cardId,
        ),
        ...state,
      ];
      return;
    }
    final existingIndex = state.indexWhere(
      (item) =>
          item.product.id == product.id && item.priceOverride == priceOverride,
    );
    if (existingIndex >= 0) {
      final item = state[existingIndex];
      final updatedItem = item.copyWith(quantity: item.quantity + 1);
      final newState = [...state];
      newState.removeAt(existingIndex);
      state = [updatedItem, ...newState];
    } else {
      state = [
        CartItem(product: product, quantity: 1, priceOverride: priceOverride),
        ...state,
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

  /// Load an arbitrary set of items (used when switching between carts).
  void loadItems(List<CartItem> items) {
    state = items;
    ref.read(editingSaleIdProvider.notifier).set(null);
    ref.read(originalCartItemsProvider.notifier).set([]);
  }

  void clear() {
    state = ref.read(multiCartProvider.notifier).removeActiveCart();
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

// ── Multi-Cart System ────────────────────────────────────────────────────────

class MultiCartState {
  /// Snapshots of every open cart.
  /// The active cart's snapshot may be stale; live items are in [cartProvider].
  final List<List<CartItem>> snapshots;

  /// Display labels (1, 2, 3 …) – never reset so numbers stay unique.
  final List<int> labels;

  /// Index of the currently active cart (-1 = no carts).
  final int activeIndex;

  /// The number to assign to the next created cart.
  final int nextLabel;

  const MultiCartState({
    required this.snapshots,
    required this.labels,
    required this.activeIndex,
    required this.nextLabel,
  });

  int get count => snapshots.length;
  bool get hasCarts => snapshots.isNotEmpty;

  MultiCartState copyWith({
    List<List<CartItem>>? snapshots,
    List<int>? labels,
    int? activeIndex,
    int? nextLabel,
  }) {
    return MultiCartState(
      snapshots: snapshots ?? this.snapshots,
      labels: labels ?? this.labels,
      activeIndex: activeIndex ?? this.activeIndex,
      nextLabel: nextLabel ?? this.nextLabel,
    );
  }
}

class MultiCartNotifier extends Notifier<MultiCartState> {
  @override
  MultiCartState build() => const MultiCartState(
    snapshots: [[]],
    labels: [1],
    activeIndex: 0,
    nextLabel: 2,
  );

  /// Switch to cart [toIndex], saving [currentItems] for the current cart.
  /// Returns the items that should be loaded into [cartProvider].
  List<CartItem> switchTo(int toIndex, List<CartItem> currentItems) {
    if (toIndex == state.activeIndex) return currentItems;
    final updated = [...state.snapshots.map((s) => List<CartItem>.from(s))];
    updated[state.activeIndex] = currentItems;
    state = state.copyWith(snapshots: updated, activeIndex: toIndex);
    return List<CartItem>.from(updated[toIndex]);
  }

  /// Create a new empty cart, saving [currentItems] first.
  /// Returns the new cart's index.
  int addCart(List<CartItem> currentItems) {
    final updated = [...state.snapshots.map((s) => List<CartItem>.from(s))];
    updated[state.activeIndex] = currentItems;
    updated.add([]);
    final newLabels = [...state.labels, state.nextLabel];
    final newIndex = updated.length - 1;
    state = state.copyWith(
      snapshots: updated,
      labels: newLabels,
      activeIndex: newIndex,
      nextLabel: state.nextLabel + 1,
    );
    return newIndex;
  }

  /// Remove the active cart (after checkout or when cleared).
  /// Always keeps at least one empty cart so the UI never hits index -1.
  /// Returns the items to load into [cartProvider].
  List<CartItem> removeActiveCart() {
    final updated = [...state.snapshots.map((s) => List<CartItem>.from(s))];
    final updatedLabels = [...state.labels];
    updated.removeAt(state.activeIndex);
    updatedLabels.removeAt(state.activeIndex);

    // Always keep a minimum of one cart
    if (updated.isEmpty) {
      updated.add([]);
      updatedLabels.add(state.nextLabel);
      state = MultiCartState(
        snapshots: updated,
        labels: updatedLabels,
        activeIndex: 0,
        nextLabel: state.nextLabel + 1,
      );
      return [];
    }

    final newIndex = state.activeIndex > 0 ? state.activeIndex - 1 : 0;
    state = state.copyWith(
      snapshots: updated,
      labels: updatedLabels,
      activeIndex: newIndex,
    );
    return List<CartItem>.from(updated[newIndex]);
  }
}

final multiCartProvider =
    NotifierProvider<MultiCartNotifier, MultiCartState>(() {
      return MultiCartNotifier();
    });

final checkoutProvider = Provider((ref) => CheckoutRepository(ref));

class CheckoutRepository {
  final Ref ref;
  CheckoutRepository(this.ref);

  /// Backwards-compatible thin wrapper around [StockService.apply].
  ///
  /// All stock writes now go through one path: append a `stock_movement`
  /// (with a fresh `client_id` UUID) and adjust `products.quantity` in
  /// the same SQLite transaction. The remote write happens later in
  /// `SyncService.syncUp` via UPSERT keyed on `client_id`, which is
  /// idempotent — a network retry no longer multiplies the change.
  ///
  /// `isOnline` is accepted but ignored; the new design always writes
  /// locally first and lets the sync service propagate to Supabase.
  Future<void> updateStockWithLinkage({
    required int productId,
    required double change,
    required String reason,
    bool isOnline = true,
    int? localSaleId,
  }) async {
    await ref.read(stockServiceProvider).apply(
      inputs: [StockChange(productId: productId, change: change)],
      reason: reason,
      localSaleId: localSaleId,
    );
  }

  Future<void> _updateDrawerBalance(Database db, double amountChange) async {
    await BalanceRepo.addLocal(db, amountChange.toInt(), isSynced: false);
    ref.invalidate(balanceProvider);
  }

  Future<int?> processCheckout(String paymentType) async {
    final cartItems = ref.read(cartProvider);
    if (cartItems.isEmpty) return null;

    final total = ref.read(cartProvider.notifier).total;
    final currentUser = ref.read(authProvider);
    final db = await LocalDatabase.instance.database;
    final stock = ref.read(stockServiceProvider);
    final saleClientId = const Uuid().v4();

    // Atomic local-first checkout. Sale, sale_items, and stock_movements
    // commit together inside one SQLite transaction, so we cannot end up
    // with a sale on Supabase that has no matching stock movement (the
    // 4286-row mismatch we recovered from). Sync to Supabase happens
    // out-of-band via SyncService.syncUp using UPSERT on client_id, so
    // retries are idempotent and a network blip can no longer create
    // duplicate or missing movements.
    int localSaleId;
    try {
      localSaleId = await db.transaction<int>((txn) async {
        final saleId = await txn.insert('sales', {
          'total_price': total,
          'payment_type': paymentType,
          if (currentUser != null) 'user_id': currentUser.id,
          'client_id': saleClientId,
          'is_synced': 0,
        });

        for (final item in cartItems) {
          final itemPrice = item.priceOverride ?? item.product.price;
          await txn.insert('sale_items', {
            'sale_id': saleId,
            'product_id': item.product.id,
            'quantity': item.quantity.toInt(),
            'price': itemPrice,
          });
        }

        await stock.applyInTransaction(
          txn: txn,
          inputs: [
            for (final item in cartItems)
              StockChange(
                productId: item.product.id,
                change: -item.quantity.toDouble(),
              ),
          ],
          reason: 'بيع',
          localSaleId: saleId,
        );

        return saleId;
      });
    } catch (e) {
      debugPrint('Checkout transaction failed: $e');
      return null;
    }

    // Side effects after the transaction commits — these are best-effort
    // and never block the sale from succeeding.
    if (paymentType == 'cash') {
      try {
        await ref.read(printingServiceProvider).openCashDrawer();
      } catch (e) {
        debugPrint('Cash drawer open failed: $e');
      }
      try {
        await db.insert('cash_drawer_logs', {
          'type': 'open',
          'reason': 'بيع في فاتورة #$localSaleId',
          'amount': total,
          'user_id': currentUser?.id,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'is_synced': 0,
        });
      } catch (_) {}
    } else if (paymentType == 'card') {
      try {
        await BalanceRepo.addCardLocal(db, total.toInt(), isSynced: false);
      } catch (e) {
        debugPrint('Local card balance update failed: $e');
      }
    }

    final cardItems = cartItems.where((i) => i.cardId != null).toList();
    if (cardItems.isNotEmpty && ref.read(isOnlineProvider)) {
      Future.delayed(
        Duration.zero,
        () => ref
            .read(cardsRepositoryProvider)
            .incrementSpendedBalance(cardItems),
      );
    }

    ref.read(cartProvider.notifier).clear();
    ref.read(dbUpdateTriggerProvider.notifier).trigger();
    ref.invalidate(todaySalesProvider);
    ref.invalidate(todaySalesCountProvider);

    return localSaleId;
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

      // 2. Reverse the old payment from its corresponding balance variable.
      if (oldPaymentType == 'cash') {
        await BalanceRepo.addRemote(supabase, -oldTotal.toInt());
      } else if (oldPaymentType == 'card') {
        await BalanceRepo.addCardRemote(supabase, -oldTotal.toInt());
      }

      // 3. Update Sale (Online)
      await supabase
          .from('sales')
          .update({'total_price': total, 'payment_type': paymentType})
          .eq('id', saleId);

      // Apply the new total to the correct balance — cash → drawer,
      // card → card accumulator. Card payments never touch the drawer
      // and cash never touches the card balance.
      if (paymentType == 'cash') {
        await BalanceRepo.addRemote(supabase, total.toInt());
      } else if (paymentType == 'card') {
        await BalanceRepo.addCardRemote(supabase, total.toInt());
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

      // Revert the balance on the side the sale actually touched:
      // cash → drawer, card → cardBalance accumulator.
      if (paymentType == 'cash') {
        await BalanceRepo.addRemote(supabase, -total.toInt());
      } else if (paymentType == 'card') {
        await BalanceRepo.addCardRemote(supabase, -total.toInt());
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
// ── Cards (Recharge Cards) ─────────────────────────────────────────────────

final cardsProvider = FutureProvider.family<List<CardItem>, int>((
  ref,
  productId,
) async {
  final supabase = ref.read(supabaseProvider);
  final isOnline = ref.read(isOnlineProvider);
  if (isOnline) {
    try {
      final data = await supabase
          .from('cards')
          .select()
          .eq('productId', productId)
          .order('price');
      // Mirror to local
      _mirrorCardsToLocal(data);
      return data.map((j) => CardItem.fromJson(j)).toList();
    } catch (_) {}
  }
  // Fallback: local SQLite
  final db = await LocalDatabase.instance.database;
  final rows = await db.query(
    'cards',
    where: 'product_id = ?',
    whereArgs: [productId],
    orderBy: 'price ASC',
  );
  return rows.map((j) => CardItem.fromJson({...j, 'productId': j['product_id']})).toList();
});

Future<void> _mirrorCardsToLocal(List<Map<String, dynamic>> data) async {
  try {
    final db = await LocalDatabase.instance.database;
    for (var card in data) {
      await db.insert('cards', {
        'id': card['id'],
        'name': card['name'],
        'product_id': card['productId'],
        'price': (card['price'] as num?)?.toInt() ?? 0,
        'spended_balance': (card['spended_balance'] as num?)?.toInt() ?? 0,
        'created_at': card['created_at'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  } catch (e) {
    debugPrint('Mirror cards to local failed: $e');
  }
}

final cardsRepositoryProvider = Provider((ref) => CardsRepository(ref));

class CardsRepository {
  final Ref ref;
  CardsRepository(this.ref);

  Future<void> addCard({
    required String name,
    required int productId,
    required int price,
  }) async {
    final supabase = ref.read(supabaseProvider);
    final result = await supabase.from('cards').insert({
      'name': name,
      'productId': productId,
      'price': price,
      'spended_balance': 0,
    }).select().single();
    // Mirror locally
    final db = await LocalDatabase.instance.database;
    await db.insert('cards', {
      'id': result['id'],
      'name': name,
      'product_id': productId,
      'price': price,
      'spended_balance': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    ref.invalidate(cardsProvider(productId));
  }

  Future<void> resetCardBalance(int cardId, int productId) async {
    final supabase = ref.read(supabaseProvider);
    await supabase.from('cards').update({'spended_balance': 0}).eq('id', cardId);
    final db = await LocalDatabase.instance.database;
    await db.update('cards', {'spended_balance': 0},
        where: 'id = ?', whereArgs: [cardId]);
    ref.invalidate(cardsProvider(productId));
  }

  /// Called after a sale — increments spended_balance for each card item
  Future<void> incrementSpendedBalance(List<CartItem> items) async {
    final supabase = ref.read(supabaseProvider);
    for (final item in items) {
      if (item.cardId == null) continue;
      final price = (item.priceOverride ?? item.product.price).toInt();
      try {
        // Read current then increment (Supabase doesn't support += directly)
        final current = await supabase
            .from('cards')
            .select('spended_balance')
            .eq('id', item.cardId!)
            .single();
        final newBal =
            ((current['spended_balance'] as num?)?.toInt() ?? 0) + price;
        await supabase
            .from('cards')
            .update({'spended_balance': newBal})
            .eq('id', item.cardId!);
        // Update local
        final db = await LocalDatabase.instance.database;
        await db.update('cards', {'spended_balance': newBal},
            where: 'id = ?', whereArgs: [item.cardId]);
        ref.invalidate(cardsProvider(item.product.id));
      } catch (e) {
        debugPrint('Failed to update card spended_balance: $e');
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

    bool onlineLogged = false;
    if (isOnline) {
      try {
        await supabase.from('cash_drawer_logs').insert(
              Map<String, dynamic>.from(logMap)..['user_id'] = currentUser?.id,
            );
        onlineLogged = true;
      } catch (e) {
        debugPrint('Failed to log cash drawer online: $e');
      }
    }
    logMap['is_synced'] = onlineLogged ? 1 : 0;

    try {
      await db.insert('cash_drawer_logs', logMap);
    } catch (e) {
      debugPrint('Failed to log cash drawer locally: $e');
    }

    // 3. Apply the effective balance change in a single place.
    //    - 'open' with amount==0: a pure drawer open (e.g. remote open),
    //      no balance movement.
    //    - 'open' with amount!=0: cash-sale proceeds entering the drawer.
    //    - 'add': deposit into the drawer.
    //    - 'withdraw': withdrawal from the drawer.
    //    Card sales never call this method for their totals, so card money
    //    can never touch the drawer balance here.
    int balanceChange = 0;
    if (type == 'withdraw') {
      balanceChange = -amount.toInt();
    } else if (amount != 0) {
      balanceChange = amount.toInt();
    }
    if (balanceChange == 0) return;

    bool remoteOk = false;
    if (isOnline) {
      try {
        await BalanceRepo.addRemote(supabase, balanceChange);
        remoteOk = true;
      } catch (e) {
        debugPrint('Failed to update remote balance: $e');
      }
    }
    await BalanceRepo.addLocal(db, balanceChange, isSynced: remoteOk);
    ref.invalidate(balanceProvider);
  }
}
