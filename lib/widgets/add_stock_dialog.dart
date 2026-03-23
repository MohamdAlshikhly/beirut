import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../providers/data_providers.dart';
import '../utils/app_colors.dart';
import '../services/sync_service.dart';

class AddStockQuantityDialog extends ConsumerStatefulWidget {
  final Product product;
  const AddStockQuantityDialog({super.key, required this.product});

  @override
  ConsumerState<AddStockQuantityDialog> createState() =>
      _AddStockQuantityDialogState();
}

class _AddStockQuantityDialogState
    extends ConsumerState<AddStockQuantityDialog> {
  final _qtyController = TextEditingController();
  bool _isLoading = false;

  void _save() async {
    if (_qtyController.text.trim().isEmpty) return;
    setState(() => _isLoading = true);
    try {
      double addedQty = double.parse(_qtyController.text);
      if (addedQty <= 0) {
        setState(() => _isLoading = false);
        return;
      }

      final isMobile = ref.read(isMobileProvider);

      // Use the centralized updateStockWithLinkage logic
      await ref
          .read(checkoutProvider)
          .updateStockWithLinkage(
            productId: widget.product.id,
            change: addedQty,
            reason: 'تزويد المخزن يدوياً عبر مسح الباركود',
            isOnline: !isMobile || true, // Repository handles online check
          );

      _showSuccess(addedQty);
      ref.invalidate(productsProvider);
      if (!isMobile) {
        ref.read(syncServiceProvider).syncUp();
      }
    } catch (e) {
      debugPrint('Error updating stock: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _showSuccess(double addedQty) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم رفع مخزون ${widget.product.name} بمقدار $addedQty بنجاح!',
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'تزويد المخزن - ${widget.product.name}',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'الكمية الحـالية المتوفرة:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${widget.product.quantity}',
                  style: const TextStyle(
                    fontSize: 20,
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _qtyController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'ما مقدار الكمية المُراد إضافتها؟',
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.add),
          label: const Text(
            'حفظ الزيادة في المخزن',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          onPressed: _isLoading ? null : _save,
        ),
      ],
    );
  }
}
