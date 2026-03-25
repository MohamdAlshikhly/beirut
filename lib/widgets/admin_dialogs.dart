import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/data_providers.dart';

class AddCategoryDialog extends ConsumerStatefulWidget {
  const AddCategoryDialog({super.key});
  @override
  ConsumerState<AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends ConsumerState<AddCategoryDialog> {
  final _nameController = TextEditingController();
  bool _isLoading = false;

  void _save() async {
    if (_nameController.text.trim().isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final client = ref.read(supabaseProvider);
      await client.from('categories').insert({
        'name': _nameController.text.trim(),
      });
      ref.invalidate(categoriesProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('Error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة قسم جديد'),
      content: TextField(
        controller: _nameController,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'اسم القسم'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _save,
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

class AddProductDialog extends ConsumerStatefulWidget {
  const AddProductDialog({super.key});
  @override
  ConsumerState<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends ConsumerState<AddProductDialog> {
  final _nameController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _priceController = TextEditingController();
  final _costPriceController = TextEditingController();
  final _qtyController = TextEditingController();
  int? _selectedCategoryId;
  bool _isLoading = false;

  void _save() async {
    if (_nameController.text.trim().isEmpty || _priceController.text.isEmpty) {
      return;
    }
    setState(() => _isLoading = true);
    try {
      final client = ref.read(supabaseProvider);
      await client.from('products').insert({
        'name': _nameController.text.trim(),
        'barcode': _barcodeController.text.trim(),
        'price': double.parse(_priceController.text),
        'cost_price': _costPriceController.text.isNotEmpty
            ? double.parse(_costPriceController.text)
            : null,
        'quantity': _qtyController.text.isNotEmpty
            ? int.parse(_qtyController.text)
            : 0,
        'category_id': _selectedCategoryId,
      });
      ref.invalidate(productsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('Error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return AlertDialog(
      title: const Text('إضافة منتج جديد'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'اسم المنتج'),
            ),
            TextField(
              controller: _barcodeController,
              decoration: const InputDecoration(labelText: 'الباركود'),
            ),
            TextField(
              controller: _priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'سعر البيع'),
            ),
            TextField(
              controller: _costPriceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'سعر التكلفة'),
            ),
            TextField(
              controller: _qtyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'الكمية الابتدائية'),
            ),
            const SizedBox(height: 8),
            categoriesAsync.when(
              data: (categories) => DropdownButtonFormField<int>(
                initialValue: _selectedCategoryId,
                decoration: const InputDecoration(labelText: 'القسم'),
                items: categories
                    .map(
                      (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedCategoryId = v),
              ),
              loading: () => const CircularProgressIndicator(),
              error: (e, st) => const Text('Error loading categories'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _save,
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

class WithdrawCashDialog extends ConsumerStatefulWidget {
  const WithdrawCashDialog({super.key});
  @override
  ConsumerState<WithdrawCashDialog> createState() => _WithdrawCashDialogState();
}

class _WithdrawCashDialogState extends ConsumerState<WithdrawCashDialog> {
  final _amountController = TextEditingController();
  bool _isLoading = false;

  void _save(int maxAmount) async {
    if (_amountController.text.isEmpty) return;
    final amount = int.tryParse(_amountController.text) ?? 5;
    if (amount > maxAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('المبلغ المطلوب أكبر من الرصيد المتوفر!')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final client = ref.read(supabaseProvider);

      final res = await client
          .from('balance')
          .select()
          .order('id', ascending: false)
          .limit(1);
      int currentBal = res.isNotEmpty
          ? res.first['currentBalance'] as int? ?? 0
          : 0;

      currentBal -= amount;
      if (res.isEmpty) {
        await client.from('balance').insert({'currentBalance': currentBal});
      } else {
        await client
            .from('balance')
            .update({'currentBalance': currentBal})
            .eq('id', res.first['id']);
      }
      ref.invalidate(balanceProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('Error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final balanceAsync = ref.watch(balanceProvider);

    return balanceAsync.when(
      data: (curBal) => AlertDialog(
        title: const Text('سحب أموال من الدرج'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'الرصيد الحالي: ${NumberFormat("#,##0").format(curBal)} د.ع',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'المبلغ المسحوب (بالدينار)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () =>
                  setState(() => _amountController.text = curBal.toString()),
              icon: const Icon(Icons.all_out),
              label: const Text('سحب الرصيد بالكامل'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: _isLoading ? null : () => _save(curBal),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('سحب الأموال'),
          ),
        ],
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => const Center(child: Text('خطأ في تحميل الرصيد')),
    );
  }
}
