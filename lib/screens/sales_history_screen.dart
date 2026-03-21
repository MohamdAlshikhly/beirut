import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../providers/data_providers.dart';
import '../models/models.dart';
import '../utils/app_colors.dart';
import '../screens/mobile_cart_screen.dart';
import '../screens/camera_scanner_screen.dart';
import '../widgets/skeleton_container.dart';
import '../services/local_database.dart';
import '../services/sync_service.dart';

class SalesHistoryScreen extends ConsumerStatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  ConsumerState<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends ConsumerState<SalesHistoryScreen> {
  List<Map<String, dynamic>> _sales = [];
  List<Map<String, dynamic>> _filteredSales = [];
  bool _isLoading = true;
  final _currencyFormatter = NumberFormat('#,##0', 'en_US');

  @override
  void initState() {
    super.initState();
    _fetchSales();
  }

  Future<void> _fetchSales() async {
    setState(() => _isLoading = true);
    try {
      final isMobile = ref.read(isMobileProvider);
      final user = ref.read(authProvider);

      if (isMobile) {
        debugPrint('DEBUG: MOBILE LIVE FETCH FOR SALES HISTORY');
        final supabase = ref.read(supabaseProvider);

        var query = supabase.from('sales').select('*, users(name)');

        if (user != null && user.role != 'admin') {
          query = query.eq('user_id', user.id);
        }

        final res = await query
            .order('created_at', ascending: false)
            .limit(100);

        if (mounted) {
          setState(() {
            _sales = List<Map<String, dynamic>>.from(res);
            _filteredSales = _sales;
          });
        }
      } else {
        // Desktop/Local Logic
        final db = await LocalDatabase.instance.database;
        String query = '''
          SELECT sales.*, users.name as user_name
          FROM sales
          LEFT JOIN users ON sales.user_id = users.id
        ''';

        List<dynamic> args = [];
        if (user != null && user.role != 'admin') {
          query += ' WHERE sales.user_id = ?';
          args.add(user.id);
        }

        query += ' ORDER BY created_at DESC LIMIT 100';

        final res = await db.rawQuery(query, args);

        if (mounted) {
          setState(() {
            _sales = res.map((row) {
              final map = Map<String, dynamic>.from(row);
              map['users'] = {'name': row['user_name']};
              return map;
            }).toList();
            _filteredSales = _sales;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching sales history: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _filter(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredSales = _sales;
      } else {
        _filteredSales = _sales
            .where((s) => s['id'].toString().contains(query))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsBold.receipt, color: AppColors.secondary),
            SizedBox(width: 8),
            Text('سجل الفواتير'),
          ],
        ),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.secondary,
        actions: [
          IconButton(
            icon: const Icon(PhosphorIconsBold.arrowsClockwise),
            onPressed: () async {
              await ref.read(syncServiceProvider).syncDown();
              _fetchSales();
            },
          ),
        ],
      ),
      body: Container(
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                : [const Color(0xFFF1F5F9), const Color(0xFFE2E8F0)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                decoration: InputDecoration(
                  hintText: 'ابحث برقم الفاتورة...',
                  prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass),
                  suffixIcon: IconButton(
                    icon: const Icon(
                      PhosphorIconsRegular.camera,
                      color: AppColors.primary,
                    ),
                    onPressed: () async {
                      final barcode = await Navigator.push<String?>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CameraScannerScreen(
                            title: 'مسح فاتورة للبحث',
                          ),
                        ),
                      );
                      if (barcode != null) {
                        _filter(barcode);
                      }
                    },
                  ),
                  filled: true,
                  fillColor: isDark ? Colors.white10 : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: _filter,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoading
                    ? ListView.separated(
                        itemCount: 8,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white10 : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.1),
                              ),
                            ),
                            child: const Row(
                              children: [
                                SkeletonContainer(
                                  width: 48,
                                  height: 48,
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(24),
                                  ),
                                ),
                                SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SkeletonContainer(width: 120, height: 18),
                                      SizedBox(height: 8),
                                      SkeletonContainer(width: 160, height: 12),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    SkeletonContainer(width: 80, height: 16),
                                    SizedBox(height: 8),
                                    SkeletonContainer(width: 40, height: 12),
                                  ],
                                ),
                                SizedBox(width: 16),
                                SkeletonContainer(width: 20, height: 20),
                              ],
                            ),
                          );
                        },
                      )
                    : _filteredSales.isEmpty
                    ? const Center(child: Text('لا توجد فواتير مطابقة'))
                    : RefreshIndicator(
                        onRefresh: () async {
                          await ref.read(syncServiceProvider).syncDown();
                          _fetchSales();
                        },
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _filteredSales.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final sale = _filteredSales[index];
                            final saleId = sale['id'];
                            final date = DateTime.parse(
                              sale['created_at'],
                            ).toLocal();
                            final formattedDate = DateFormat(
                              'yyyy-MM-dd HH:mm',
                            ).format(date);
                            final total = (sale['total_price'] as num)
                                .toDouble();
                            final pyType = sale['payment_type'] == 'cash'
                                ? 'نقدي'
                                : 'بطاقة';
                            final cashierName = sale['users'] != null
                                ? sale['users']['name']
                                : 'غير محدد';

                            return InkWell(
                              onTap: () {
                                _showSaleDetails(
                                  context,
                                  saleId,
                                  total,
                                  formattedDate,
                                  pyType,
                                  cashierName,
                                );
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white10 : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.05,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                  border: Border.all(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.1,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.1,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        PhosphorIconsFill.receipt,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'فاتورة #$saleId',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                            ),
                                          ),
                                          Text(
                                            formattedDate,
                                            style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 12,
                                            ),
                                          ),
                                          Text(
                                            'بواسطة: $cashierName',
                                            style: const TextStyle(
                                              color: Colors.blueGrey,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '${_currencyFormatter.format(total)} د.ع',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green,
                                          ),
                                        ),
                                        Text(
                                          pyType,
                                          style: TextStyle(
                                            color: pyType == 'نقدي'
                                                ? Colors.orange
                                                : Colors.blue,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 16),
                                    const Icon(
                                      PhosphorIconsRegular.caretLeft,
                                      color: Colors.grey,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSaleDetails(
    BuildContext ctx,
    int saleId,
    double total,
    String dateStr,
    String pyType,
    String pyCashier,
  ) {
    Navigator.push(
      ctx,
      MaterialPageRoute(
        builder: (_) => SaleDetailsScreen(
          saleId: saleId,
          total: total,
          dateStr: dateStr,
          paymentType: pyType,
          cashierName: pyCashier,
          onDeleted: () {
            Navigator.pop(ctx);
            _fetchSales(); // Refresh list after delete
          },
          onEditRequested: (items) {
            Navigator.pop(ctx); // Close details
            ref.read(cartProvider.notifier).loadSale(saleId, items);
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const MobileCartScreen()),
            );
          },
        ),
      ),
    );
  }
}

class SaleDetailsScreen extends ConsumerStatefulWidget {
  final int saleId;
  final double total;
  final String dateStr;
  final String paymentType;
  final String cashierName;
  final VoidCallback onDeleted;
  final Function(List<CartItem>) onEditRequested;

  const SaleDetailsScreen({
    super.key,
    required this.saleId,
    required this.total,
    required this.dateStr,
    required this.paymentType,
    required this.cashierName,
    required this.onDeleted,
    required this.onEditRequested,
  });

  @override
  ConsumerState<SaleDetailsScreen> createState() => _SaleDetailsScreenState();
}

class _SaleDetailsScreenState extends ConsumerState<SaleDetailsScreen> {
  bool _isLoading = true;
  bool _isProcessing = false;
  List<CartItem> _items = [];

  @override
  void initState() {
    super.initState();
    _fetchItems();
  }

  Future<void> _fetchItems() async {
    try {
      final db = await LocalDatabase.instance.database;
      final response = await db.rawQuery(
        '''
        SELECT 
          sale_items.id as item_id,
          sale_items.sale_id,
          sale_items.product_id,
          sale_items.quantity as sold_quantity,
          sale_items.price as item_price,
          products.name,
          products.barcode,
          products.price as current_price,
          products.cost_price,
          products.quantity as stock_quantity,
          products.category_id
        FROM sale_items
        JOIN products ON sale_items.product_id = products.id
        WHERE sale_items.sale_id = ?
      ''',
        [widget.saleId],
      );

      List<CartItem> loadedItems = [];
      for (var row in response) {
        final prod = Product(
          id: row['product_id'] as int,
          name: row['name'] as String,
          barcode: row['barcode'] as String?,
          price: (row['item_price'] as num).toDouble(),
          costPrice: row['cost_price'] != null
              ? (row['cost_price'] as num).toDouble()
              : null,
          quantity: (row['stock_quantity'] as num).toDouble(),
          categoryId: row['category_id'] as int?,
        );
        loadedItems.add(
          CartItem(
            product: prod,
            quantity: (row['sold_quantity'] as num).toDouble(),
          ),
        );
      }
      if (mounted) {
        setState(() {
          _items = loadedItems;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _delete() async {
    final conf = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text(
          'هل أنت متأكد من حذف هذه الفاتورة بصورة نهائية؟ سيتم إرجاع المنتجات للمخزن وخصم المبلغ من الدرج.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );
    if (conf != true) return;

    setState(() => _isProcessing = true);
    final repo = ref.read(checkoutProvider);
    final success = await repo.deleteSale(widget.saleId);
    if (success) {
      widget.onDeleted();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('فشل الحذف!')));
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final fmt = NumberFormat('#,##0', 'en_US');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text('تفاصيل فاتورة #${widget.saleId}'),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.secondary,
      ),
      body: Container(
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                : [const Color(0xFFF1F5F9), const Color(0xFFE2E8F0)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'تاريخ ووقت الشراء',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        Text(
                          widget.dateStr,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'الكاشير المستلم',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        Text(
                          widget.cashierName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'طريقة الدفع',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        Text(
                          widget.paymentType,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: widget.paymentType == 'نقدي'
                                ? Colors.orange
                                : Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (c, i) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        _items[i].product.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${_items[i].quantity} × ${fmt.format(_items[i].product.price)} د.ع',
                      ),
                      trailing: Text(
                        '${fmt.format(_items[i].quantity * _items[i].product.price)} د.ع',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'الإجمالي الكلي:',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${fmt.format(widget.total)} د.ع',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent.withValues(
                          alpha: 0.1,
                        ),
                        foregroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Colors.redAccent),
                        ),
                      ),
                      icon: const Icon(PhosphorIconsBold.trash),
                      label: const Text(
                        'حذف',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: _isProcessing ? null : _delete,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.secondary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(PhosphorIconsBold.pencilSimple),
                      label: const Text(
                        'تعديل وإرجاع',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: _isProcessing
                          ? null
                          : () => widget.onEditRequested(_items),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
