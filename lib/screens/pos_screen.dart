import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/theme_provider.dart';
import '../providers/data_providers.dart';
import '../utils/glass_container.dart';
import '../widgets/product_grid.dart';
import '../widgets/cart_sidebar.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../utils/app_colors.dart';
import '../services/sync_service.dart';
import '../utils/print_utils.dart';

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  String _barcodeBuffer = '';
  DateTime? _lastKeyPress;
  bool _isCheckoutDialogOpen = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleRawKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleRawKey);
    super.dispose();
  }

  bool _handleRawKey(KeyEvent event) {
    if (_isCheckoutDialogOpen) return false;

    if (event is KeyDownEvent) {
      final now = DateTime.now();
      // أجهزة الباركود سريعة جداً وتكتب الحروف في أجزاء من الثانية
      // تم زيادة الوقت إلى 500 ملي ثانية لتجنب تقطيع القراءة في أجهزة الباركود اللاسلكية
      if (_lastKeyPress != null &&
          now.difference(_lastKeyPress!).inMilliseconds > 500) {
        _barcodeBuffer = '';
      }
      _lastKeyPress = now;

      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        if (_barcodeBuffer.isNotEmpty && _barcodeBuffer.length > 2) {
          _processScannedBarcode(_barcodeBuffer);
          _barcodeBuffer = '';
          return true; // Consume event so UI doesn't react to enter if it's a scan
        }
        _barcodeBuffer = '';

        // No barcode, so it's a manual Enter key press signaling cash checkout
        final cartItems = ref.read(cartProvider);
        if (cartItems.isNotEmpty) {
          _showCheckoutConfirmation();
          return true;
        }
      } else if (event.character != null &&
          event.character!.trim().isNotEmpty) {
        _barcodeBuffer += event.character!;
      }
    }
    return false; // Leave normal typing for TextFields
  }

  void _processScannedBarcode(String barcode) {
    final productsAsync = ref.read(productsProvider);
    productsAsync.whenData((products) {
      try {
        final product = products.firstWhere(
          (p) => p.barcode == barcode || p.id.toString() == barcode,
        );
        ref.read(cartProvider.notifier).addProduct(product);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم إضافة: ${product.name} ✔️'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('المنتج غير موجود! ❌'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 1),
            ),
          );
        }
      }
    });
  }

  void _showCheckoutConfirmation() {
    setState(() => _isCheckoutDialogOpen = true);

    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Focus(
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
            title: const Text('تأكيد الدفع نقداً'),
            content: const Text(
              'هل أنت متأكد من إتمام وطباعة هذه العملية نقداً؟\n\n- اضغط (Enter) للتأكيد\n- اضغط (Esc) للإلغاء',
              style: TextStyle(fontSize: 18),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'إلغاء (Esc)',
                  style: TextStyle(color: AppColors.secondary),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                child: const Text(
                  'تأكيد (Enter)',
                  style: TextStyle(color: AppColors.secondary),
                ),
              ),
            ],
          ),
        );
      },
    ).then((confirmed) {
      if (mounted) setState(() => _isCheckoutDialogOpen = false);
      if (confirmed == true) {
        _processPaymentGlobally('cash');
      }
    });
  }

  void _processPaymentGlobally(String method) async {
    final cartItems = ref.read(cartProvider);
    final total = ref.read(cartProvider.notifier).total;

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

    if (mounted) {
      Navigator.of(context).pop();

      if (saleId != null) {
        // Show Print Receipt Dialog only on Computer
        _showPrintDialog(context, ref, cartItems, total, saleId: saleId);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إتمام العملية بنجاح! ✔️'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فشلت العملية! يرجى المحاولة مرة أخرى. ❌'),
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

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.watch(isOnlineProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                    : [const Color(0xFFF1F5F9), const Color(0xFFE2E8F0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  GlassContainer(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          PhosphorIconsBold.treeEvergreen,
                          size: 32,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'دكان بيروت',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isOnline
                                ? Colors.green.withValues(alpha: 0.2)
                                : Colors.red.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isOnline ? Colors.green : Colors.red,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isOnline
                                    ? PhosphorIconsFill.wifiHigh
                                    : PhosphorIconsFill.wifiX,
                                size: 16,
                                color: isOnline ? Colors.green : Colors.red,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isOnline ? 'متصل' : 'غير متصل',
                                style: TextStyle(
                                  color: isOnline ? Colors.green : Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          icon: const Icon(
                            PhosphorIconsBold.arrowsClockwise,
                            color: AppColors.primary,
                          ),
                          tooltip: 'مزامنة البيانات يدوياً',
                          onPressed: () {
                            ref.read(syncServiceProvider).syncUp();
                            ref.read(syncServiceProvider).syncDown();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('جاري بدء المزامنة... 🔄'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(
                            isDark
                                ? PhosphorIconsFill.sun
                                : PhosphorIconsFill.moon,
                          ),
                          onPressed: () {
                            ref.read(themeModeProvider.notifier).toggle();
                          },
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(
                            PhosphorIconsBold.signOut,
                            color: Colors.redAccent,
                          ),
                          tooltip: 'إنهاء الجلسة / تسجيل خروج',
                          onPressed: () async {
                            final user = ref.read(authProvider);
                            if (user != null) {
                              try {
                                await ref
                                    .read(supabaseProvider)
                                    .from('sessions')
                                    .update({
                                      'is_active': false,
                                      'ended_at': DateTime.now()
                                          .toUtc()
                                          .toIso8601String(),
                                    })
                                    .eq('user_id', user.id)
                                    .eq('is_active', true);
                              } catch (_) {}
                            }
                            ref.read(authProvider.notifier).logout();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 7, child: ProductGrid()),
                        SizedBox(width: 24),
                        Expanded(flex: 3, child: CartSidebar()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
