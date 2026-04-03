import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../providers/data_providers.dart';
import '../utils/app_colors.dart';

class CardsManagementScreen extends ConsumerWidget {
  const CardsManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة كروت التعبئة'),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.secondary,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                : [const Color(0xFFF1F5F9), const Color(0xFFE2E8F0)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: productsAsync.when(
          skipLoadingOnReload: true,
          data: (products) {
            final cardProducts =
                products.where((p) => p.isCard).toList();
            if (cardProducts.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.credit_card_off,
                        size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    const Text(
                      'لا توجد منتجات كروت بعد.',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'أضف منتجاً وفعّل خيار "كرت تعبئة".',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: cardProducts.length,
              itemBuilder: (ctx, i) =>
                  _CardProductSection(product: cardProducts[i]),
            );
          },
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('خطأ: $e')),
        ),
      ),
    );
  }
}

class _CardProductSection extends ConsumerWidget {
  final Product product;
  const _CardProductSection({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(cardsProvider(product.id));
    final formatter = NumberFormat('#,##0', 'en_US');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.credit_card,
                      color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    product.name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  onPressed: () =>
                      _showAddCardDialog(context, ref, product.id),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('إضافة كرت'),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary),
                ),
              ],
            ),
            const Divider(height: 24),
            // Cards list
            cardsAsync.when(
              data: (cards) {
                if (cards.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'لا توجد كروت — اضغط "إضافة كرت" لإنشاء كرت جديد.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  );
                }
                return Column(
                  children: cards
                      .map((card) => _CardRow(
                            card: card,
                            productId: product.id,
                            formatter: formatter,
                          ))
                      .toList(),
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('خطأ: $e',
                  style: const TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddCardDialog(
      BuildContext context, WidgetRef ref, int productId) {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    bool loading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('إضافة كرت جديد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'اسم الكرت',
                  hintText: 'مثلاً: كرت اسياسيل 5000',
                  filled: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'السعر (د.ع)',
                  filled: true,
                  suffixText: 'د.ع',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: loading
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      final price = int.tryParse(priceCtrl.text.trim());
                      if (name.isEmpty || price == null || price <= 0) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                              content: Text('أدخل اسم الكرت وسعراً صحيحاً')),
                        );
                        return;
                      }
                      setState(() => loading = true);
                      try {
                        await ref.read(cardsRepositoryProvider).addCard(
                              name: name,
                              productId: productId,
                              price: price,
                            );
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setState(() => loading = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('فشل الحفظ: $e')),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.secondary,
              ),
              child: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.secondary),
                    )
                  : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardRow extends ConsumerWidget {
  final CardItem card;
  final int productId;
  final NumberFormat formatter;

  const _CardRow({
    required this.card,
    required this.productId,
    required this.formatter,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  'السعر: ${formatter.format(card.price)} د.ع  •  المُنفق: ${formatter.format(card.spendedBalance)} د.ع',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'تصفير الرصيد المُنفق',
            icon: const Icon(Icons.refresh, color: Colors.orange),
            onPressed: () => _confirmReset(context, ref),
          ),
        ],
      ),
    );
  }

  void _confirmReset(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تصفير الرصيد'),
        content: Text(
            'هل تريد تصفير الرصيد المُنفق للكرت "${card.name}"؟\nسيصبح المُنفق 0 د.ع.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(cardsRepositoryProvider)
                    .resetCardBalance(card.id, productId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('تم تصفير رصيد "${card.name}"'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('فشل التصفير: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('تصفير',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
