import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/data_providers.dart';
import '../utils/glass_container.dart';
import '../utils/app_colors.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../screens/sales_history_screen.dart';
import '../utils/print_utils.dart';

import 'sidebar_history.dart';
import 'sidebar_details.dart';

class CartSidebar extends ConsumerWidget {
  final VoidCallback? onPaymentSuccess;

  const CartSidebar({super.key, this.onPaymentSuccess});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(sidebarViewProvider);

    switch (view) {
      case SidebarView.history:
        return const GlassContainer(
          padding: EdgeInsets.all(0),
          child: SidebarHistory(),
        );
      case SidebarView.details:
        return const GlassContainer(
          padding: EdgeInsets.all(0),
          child: SidebarDetails(),
        );
      case SidebarView.cart:
        return _buildCartView(context, ref);
    }
  }

  Widget _buildCartView(BuildContext context, WidgetRef ref) {
    final cartItems = ref.watch(cartProvider);
    final total = ref.read(cartProvider.notifier).total;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currencyFormatter = NumberFormat('#,##0', 'en_US');
    final editingSaleId = ref.watch(editingSaleIdProvider);

    return GlassContainer(
      padding: const EdgeInsets.all(0),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                const Icon(PhosphorIconsRegular.shoppingCart, size: 28),
                const SizedBox(width: 12),
                Text(
                  editingSaleId != null
                      ? 'تعديل فاتورة #$editingSaleId'
                      : 'الفاتورة الحالية',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (editingSaleId == null)
                  IconButton(
                    icon: const Icon(
                      PhosphorIconsRegular.clockCounterClockwise,
                    ),
                    onPressed: () {
                      final isMobile = ref.read(isMobileProvider);
                      if (isMobile) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SalesHistoryScreen(),
                          ),
                        );
                      } else {
                        ref
                            .read(sidebarViewProvider.notifier)
                            .set(SidebarView.history);
                      }
                    },
                    tooltip: 'سجل الفواتير',
                  )
                else
                  IconButton(
                    icon: const Icon(
                      PhosphorIconsRegular.xCircle,
                      color: Colors.redAccent,
                    ),
                    onPressed: () => ref.read(cartProvider.notifier).clear(),
                    tooltip: 'إلغاء التعديل',
                  ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${cartItems.length}',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (editingSaleId == null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      PhosphorIconsRegular.trash,
                      color: Colors.redAccent,
                    ),
                    onPressed: () => ref.read(cartProvider.notifier).clear(),
                    tooltip: 'تفريغ السلة',
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: cartItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          PhosphorIconsLight.shoppingCart,
                          size: 64,
                          color: Colors.grey.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'السلة فارغة',
                          style: TextStyle(
                            color: Colors.grey.withValues(alpha: 0.8),
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: cartItems.length,
                    separatorBuilder: (c, i) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = cartItems[index];
                      return _CartItemTile(item: item);
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
                      'المجموع الكلي',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${currencyFormatter.format(total)} د.ع',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _PaymentButton(
                        icon: PhosphorIconsRegular.money,
                        label: editingSaleId != null ? 'حفظ (نقدي)' : 'نقدي',
                        color: AppColors.primary,
                        textColor: AppColors.secondary,
                        onPressed: cartItems.isEmpty
                            ? null
                            : () => _processPayment(context, ref, 'cash'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: _PaymentButton(
                        icon: PhosphorIconsRegular.creditCard,
                        label: editingSaleId != null ? 'حفظ (بطاقة)' : 'بطاقة',
                        color: AppColors.secondary,
                        textColor: Colors.white,
                        onPressed: cartItems.isEmpty
                            ? null
                            : () => _processPayment(context, ref, 'card'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _processPayment(
    BuildContext context,
    WidgetRef ref,
    String method,
  ) async {
    final cartItems = ref.read(cartProvider);
    final total = ref.read(cartProvider.notifier).total;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter) {
              Navigator.pop(ctx, true);
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.pop(ctx, false);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: AlertDialog(
          title: Text(
            method == 'cash' ? 'تأكيد الدفع نقداً' : 'تأكيد الدفع بالبطاقة',
          ),
          content: const Text(
            'هل أنت متأكد من إتمام هذه العملية؟\n\n- اضغط (Enter) للتأكيد\n- اضغط (Esc) للإلغاء',
            style: TextStyle(fontSize: 18),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء (Esc)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: const Text(
                'تأكيد (Enter)',
                style: TextStyle(color: AppColors.secondary),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final editingSaleId = ref.read(editingSaleIdProvider);
    bool success;

    if (editingSaleId != null) {
      success = await ref.read(checkoutProvider).updateSale(method);
    } else {
      success = await ref.read(checkoutProvider).processCheckout(method);
    }

    if (context.mounted) {
      Navigator.of(context).pop();

      if (success) {
        if (onPaymentSuccess != null) {
          onPaymentSuccess!();
        }

        // Show Print Receipt Dialog only on Computer
        final isMobile = ref.read(isMobileProvider);
        if (!isMobile) {
          _showPrintDialog(context, ref, cartItems, total);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم الحفظ بنجاح!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فشلت العملية! يرجى المحاولة مرة أخرى.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showPrintDialog(
    BuildContext context,
    WidgetRef ref,
    List<CartItem> cartItems,
    double total,
  ) {
    PrintUtils.showPrintDialog(
      context: context,
      ref: ref,
      cartItems: cartItems,
      total: total,
      saleId: ref.read(editingSaleIdProvider),
    );
  }
}

class _CartItemTile extends ConsumerWidget {
  final CartItem item;

  const _CartItemTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currencyFormatter = NumberFormat('#,##0', 'en_US');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white24 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    item.product.name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.product.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${currencyFormatter.format(item.product.price)} د.ع',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(PhosphorIconsRegular.minusCircle),
                    iconSize: 20,
                    color: Colors.grey,
                    onPressed: () => ref
                        .read(cartProvider.notifier)
                        .updateQuantity(item.product.id, item.quantity - 1),
                  ),
                  Text(
                    '${item.quantity}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(PhosphorIconsRegular.plusCircle),
                    iconSize: 20,
                    color: AppColors.primary,
                    onPressed: () => ref
                        .read(cartProvider.notifier)
                        .updateQuantity(item.product.id, item.quantity + 1),
                  ),
                  IconButton(
                    icon: const Icon(
                      PhosphorIconsRegular.trash,
                      color: Colors.redAccent,
                    ),
                    iconSize: 20,
                    onPressed: () => ref
                        .read(cartProvider.notifier)
                        .removeProduct(item.product.id),
                    tooltip: 'إزالة من السلة',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [1, 0.75, 0.5, 0.25, 0.125, 0.1, 0.05, 0.025].map((
                preset,
              ) {
                return Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: InkWell(
                    onTap: () => ref
                        .read(cartProvider.notifier)
                        .updateQuantity(item.product.id, preset.toDouble()),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: item.quantity == preset
                            ? AppColors.primary
                            : AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$preset',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: item.quantity == preset
                              ? AppColors.secondary
                              : AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback? onPressed;

  const _PaymentButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.textColor,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: textColor,
        disabledBackgroundColor: color.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
      icon: Icon(icon, size: 24),
      label: Text(
        label,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      onPressed: onPressed,
    );
  }
}
