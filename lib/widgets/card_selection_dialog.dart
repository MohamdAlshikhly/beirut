import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../providers/data_providers.dart';
import '../utils/app_colors.dart';

/// Shows a dialog listing all cards linked to [product].
/// When user picks a card, it is added to the cart and the dialog closes.
Future<void> showCardSelectionDialog(
  BuildContext context,
  WidgetRef ref,
  Product product,
) async {
  await showDialog(
    context: context,
    builder: (_) => _CardSelectionDialog(product: product, ref: ref),
  );
}

class _CardSelectionDialog extends ConsumerWidget {
  final Product product;
  final WidgetRef ref;

  const _CardSelectionDialog({required this.product, required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef widgetRef) {
    final cardsAsync = widgetRef.watch(cardsProvider(product.id));
    final formatter = NumberFormat('#,##0', 'en_US');

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.credit_card, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              product.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: cardsAsync.when(
          data: (cards) {
            if (cards.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'لا توجد كروت متاحة لهذا المنتج.\nأضف كروتاً من تطبيق الهاتف.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              itemCount: cards.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final card = cards[i];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.credit_card,
                      color: AppColors.primary,
                    ),
                  ),
                  title: Text(
                    card.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'المُنفق: ${formatter.format(card.spendedBalance)} د.ع',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  trailing: Text(
                    '${formatter.format(card.price)} د.ع',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  onTap: () {
                    ref.read(cartProvider.notifier).addProduct(
                      product,
                      priceOverride: card.price.toDouble(),
                      cardId: card.id,
                    );
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'تمت إضافة ${card.name} — ${formatter.format(card.price)} د.ع',
                        ),
                        duration: const Duration(seconds: 2),
                        backgroundColor: AppColors.primary,
                      ),
                    );
                  },
                );
              },
            );
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (e, _) => Text('خطأ في تحميل الكروت: $e'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
      ],
    );
  }
}
