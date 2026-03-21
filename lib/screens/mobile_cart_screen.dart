import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../widgets/cart_sidebar.dart';
import '../utils/app_colors.dart';
import '../screens/camera_scanner_screen.dart';
import '../providers/data_providers.dart';

class MobileCartScreen extends ConsumerWidget {
  const MobileCartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final editingSaleId = ref.watch(editingSaleIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          editingSaleId != null
              ? 'تعديل الفاتورة #$editingSaleId'
              : 'السلة / الدفع',
        ),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.secondary,
        actions: [
          FloatingActionButton.extended(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.secondary,
            elevation: 0,
            onPressed: () async {
              final barcode = await Navigator.push<String?>(
                context,
                MaterialPageRoute(
                  builder: (_) => const CameraScannerScreen(
                    title: 'مسح باركود لإضافة منتج',
                  ),
                ),
              );

              if (barcode != null && context.mounted) {
                await Future.delayed(const Duration(milliseconds: 300));
                if (!context.mounted) return;
                final productList = ref.read(productsProvider).value ?? [];
                try {
                  final product = productList.firstWhere(
                    (p) => p.barcode == barcode || p.id.toString() == barcode,
                  );
                  ref.read(cartProvider.notifier).addProduct(product);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('تم إضافة ${product.name} للفاتورة'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('المنتج الممسوح غير موجود!'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            icon: const Icon(PhosphorIconsBold.scan),
            label: Text(''),
          ),
        ],
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
        child: CartSidebar(
          onPaymentSuccess: () {
            if (context.mounted) {
              Navigator.pop(context); // Close mobile cart after success
            }
          },
        ),
      ),
    );
  }
}
