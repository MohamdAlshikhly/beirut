import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../providers/data_providers.dart';
import '../utils/app_colors.dart';
import '../services/local_database.dart';
import '../utils/print_utils.dart';
import '../models/models.dart';

class SidebarDetails extends ConsumerStatefulWidget {
  const SidebarDetails({super.key});

  @override
  ConsumerState<SidebarDetails> createState() => _SidebarDetailsState();
}

class _SidebarDetailsState extends ConsumerState<SidebarDetails> {
  List<CartItem> _items = [];
  bool _isLoading = true;
  final _currencyFormatter = NumberFormat('#,##0', 'en_US');

  @override
  void initState() {
    super.initState();
    _fetchItems();
  }

  Future<void> _fetchItems() async {
    final sale = ref.read(selectedHistorySaleProvider);
    if (sale == null) return;

    setState(() => _isLoading = true);
    try {
      final db = await LocalDatabase.instance.database;
      final res = await db.rawQuery(
        '''
        SELECT items.*, products.name as product_name, products.price as product_price,
               products.barcode as product_barcode, products.quantity as product_stock,
               products.image_url as product_image_url
        FROM sale_items items
        JOIN products ON items.product_id = products.id
        WHERE items.sale_id = ?
      ''',
        [sale['id']],
      );

      final items = res.map((row) {
        final product = Product(
          id: row['product_id'] as int,
          name: row['product_name'] as String,
          price: (row['product_price'] as num).toDouble(),
          barcode: row['product_barcode'] as String?,
          quantity: (row['product_stock'] as num).toDouble(),
          imageUrl: row['product_image_url'] as String?,
        );

        return CartItem(
          product: product,
          quantity: (row['quantity'] as num).toDouble(),
        );
      }).toList();

      if (mounted) {
        setState(() {
          _items = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching sidebar items: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sale = ref.watch(selectedHistorySaleProvider);
    if (sale == null) return const Center(child: Text('لم يتم اختيار فاتورة'));

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = (sale['total_price'] as num).toDouble();
    final saleId = sale['id'];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(PhosphorIconsRegular.caretRight),
                onPressed: () => ref
                    .read(sidebarViewProvider.notifier)
                    .set(SidebarView.history),
              ),
              Text(
                'تفاصيل فاتورة #$saleId',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.product.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${item.quantity} × ${_currencyFormatter.format(item.product.price)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${_currencyFormatter.format(item.quantity * item.product.price)} د.ع',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.02),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'المجموع',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${_currencyFormatter.format(total)} د.ع',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.secondary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(PhosphorIconsBold.pencilSimple),
                      label: const Text(
                        'تعديل وإرجاع',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        // Switch back to cart view and load sale
                        ref
                            .read(cartProvider.notifier)
                            .loadSale(saleId, _items);
                        ref
                            .read(sidebarViewProvider.notifier)
                            .set(SidebarView.cart);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent.withValues(alpha: 0.1),
                    foregroundColor: Colors.blueAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Colors.blueAccent),
                    ),
                  ),
                  icon: const Icon(PhosphorIconsBold.printer),
                  label: const Text(
                    'طباعة الفاتورة',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    PrintUtils.showPrintDialog(
                      context: context,
                      ref: ref,
                      cartItems: _items,
                      total: total,
                      saleId: saleId,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
