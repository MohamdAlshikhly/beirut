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
import '../services/printing_service.dart';

import 'sidebar_history.dart';
import 'sidebar_details.dart';

class CartSidebar extends ConsumerStatefulWidget {
  final VoidCallback? onPaymentSuccess;

  const CartSidebar({super.key, this.onPaymentSuccess});

  @override
  ConsumerState<CartSidebar> createState() => _CartSidebarState();
}

class _CartSidebarState extends ConsumerState<CartSidebar> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        return _buildCartView(context);
    }
  }

  Widget _buildCartView(BuildContext context) {
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
                : Column(
                    children: [
                      Expanded(
                        child: Scrollbar(
                          thumbVisibility: true,
                          controller: _scrollController,
                          child: ListView.separated(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: cartItems.length,
                            separatorBuilder: (c, i) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final item = cartItems[index];
                              return _CartItemTile(item: item);
                            },
                          ),
                        ),
                      ),
                      if (cartItems.isNotEmpty) _LinkedProductsSection(cartItems: cartItems),
                    ],
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

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter) {
              Navigator.pop(ctx, 'print');
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.f12) {
              Navigator.pop(ctx, 'no_print');
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.pop(ctx, null);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: AlertDialog(
          title: Text(
            method == 'cash'
                ? 'إتمام الفاتورة (نقدي)'
                : 'إتمام الفاتورة (بطاقة)',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'اختر طريقة الحفظ المناسبة:',
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 20),
              _ShortcutInfo(
                label: 'إتمام وطباعة الفاتورة',
                shortcut: 'Enter',
                icon: PhosphorIconsRegular.printer,
              ),
              const SizedBox(height: 12),
              _ShortcutInfo(
                label: 'إتمام فقط (بدون طباعة)',
                shortcut: 'F12',
                icon: PhosphorIconsRegular.checkCircle,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('إلغاء (Esc)'),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'no_print'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(PhosphorIconsRegular.check),
              label: const Text('إتمام فقط (F12)'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'print'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.secondary,
              ),
              icon: const Icon(PhosphorIconsRegular.printer),
              label: const Text('إتمام وطباعة (Enter)'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    final shouldPrint = result == 'print';
    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final editingSaleId = ref.read(editingSaleIdProvider);
    int? saleId;

    if (editingSaleId != null) {
      saleId = await ref.read(checkoutProvider).updateSale(method);
    } else {
      saleId = await ref.read(checkoutProvider).processCheckout(method);
    }

    if (context.mounted) {
      Navigator.of(context).pop();

      if (saleId != null) {
        // Open drawer for cash payments
        if (method == 'cash') {
          try {
            ref.read(printingServiceProvider).openCashDrawer();
          } catch (e) {
            debugPrint('Auto open drawer failed: $e');
          }
        }

        if (widget.onPaymentSuccess != null) {
          widget.onPaymentSuccess!();
        }

        // Show Print Receipt Dialog only if requested
        final isMobile = ref.read(isMobileProvider);
        if (!isMobile && shouldPrint) {
          _showPrintDialog(context, ref, cartItems, total, saleId: saleId);
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
    double total, {
    int? saleId,
  }) {
    PrintUtils.showPrintDialog(
      context: context,
      ref: ref,
      cartItems: cartItems,
      total: total,
      saleId: saleId ?? ref.read(editingSaleIdProvider),
    );
  }
}

class _CartItemTile extends ConsumerStatefulWidget {
  final CartItem item;

  const _CartItemTile({required this.item});

  @override
  ConsumerState<_CartItemTile> createState() => _CartItemTileState();
}

class _CartItemTileState extends ConsumerState<_CartItemTile> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _formatQuantity(widget.item.quantity),
    );
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_CartItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.quantity != widget.item.quantity &&
        !_focusNode.hasFocus) {
      _controller.text = _formatQuantity(widget.item.quantity);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    } else {
      _submitChange();
    }
  }

  String _formatQuantity(double qty) {
    if (qty == qty.toInt()) return qty.toInt().toString();
    return qty.toString();
  }

  void _submitChange() {
    final newQty = double.tryParse(_controller.text) ?? widget.item.quantity;
    if (newQty != widget.item.quantity) {
      ref
          .read(cartProvider.notifier)
          .updateQuantity(widget.item.product.id, newQty);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    widget.item.product.name.substring(0, 1).toUpperCase(),
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
                      widget.item.product.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${currencyFormatter.format(widget.item.priceOverride ?? widget.item.product.price)} د.ع',
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
                        .updateQuantity(
                          widget.item.product.id,
                          widget.item.quantity - 1,
                        ),
                  ),
                  SizedBox(
                    width: 50,
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: AppColors.primary,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) {
                        _submitChange();
                        _focusNode.unfocus();
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(PhosphorIconsRegular.plusCircle),
                    iconSize: 20,
                    color: AppColors.primary,
                    onPressed: () => ref
                        .read(cartProvider.notifier)
                        .updateQuantity(
                          widget.item.product.id,
                          widget.item.quantity + 1,
                        ),
                  ),
                  IconButton(
                    icon: const Icon(
                      PhosphorIconsRegular.trash,
                      color: Colors.redAccent,
                    ),
                    iconSize: 20,
                    onPressed: () => ref
                        .read(cartProvider.notifier)
                        .removeProduct(widget.item.product.id),
                    tooltip: 'إزالة من السلة',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [1, 0.75, 0.5, 0.25, 0.125, 0.1, 0.05, 0.025].map((
                preset,
              ) {
                return Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: InkWell(
                    onTap: () => ref
                        .read(cartProvider.notifier)
                        .updateQuantity(
                          widget.item.product.id,
                          preset.toDouble(),
                        ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: widget.item.quantity == preset
                            ? AppColors.primary
                            : AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$preset',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: widget.item.quantity == preset
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

class _ShortcutInfo extends StatelessWidget {
  final String label;
  final String shortcut;
  final IconData icon;

  const _ShortcutInfo({
    required this.label,
    required this.shortcut,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            shortcut,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }
}
class _LinkedProductsSection extends ConsumerWidget {
  final List<CartItem> cartItems;
  const _LinkedProductsSection({required this.cartItems});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allProductsAsync = ref.watch(productsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return allProductsAsync.when(
      data: (allProducts) {
        // Collect linked product IDs
        final linkedIds = <int>{};
        for (var item in cartItems) {
          final p = item.product;
          // 1. Add base unit if exists
          if (p.baseUnitId != null) linkedIds.add(p.baseUnitId!);
          // 2. Add any product that lists this cart item as its base unit
          for (var other in allProducts) {
            if (other.baseUnitId == p.id) linkedIds.add(other.id);
          }
        }

        // Deduplicate with items already in cart
        final cartIds = cartItems.map((e) => e.product.id).toSet();
        final suggestionIds = linkedIds.difference(cartIds);

        if (suggestionIds.isEmpty) return const SizedBox.shrink();

        final suggestions = allProducts.where((p) => suggestionIds.contains(p.id)).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                'منتجات مرتبطة متوفرة',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: suggestions.length,
                itemBuilder: (context, index) {
                  final prod = suggestions[index];
                  return Container(
                    width: 160,
                    margin: const EdgeInsets.only(right: 12, bottom: 8),
                    child: InkWell(
                      onTap: () {
                        ref.read(cartProvider.notifier).addProduct(prod);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: GlassContainer(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    prod.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${NumberFormat('#,##0', 'en_US').format(prod.price)} IQD',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isDark ? Colors.white70 : Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                PhosphorIconsRegular.plus,
                                size: 16,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
