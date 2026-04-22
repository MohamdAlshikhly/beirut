import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/data_providers.dart';
import '../utils/print_utils.dart';

class CashDrawerDialog extends ConsumerStatefulWidget {
  const CashDrawerDialog({super.key});

  @override
  ConsumerState<CashDrawerDialog> createState() => _CashDrawerDialogState();
}

class _CashDrawerDialogState extends ConsumerState<CashDrawerDialog> {
  final _reasonController = TextEditingController();
  final _amountController = TextEditingController();
  String _type = 'open'; // 'open', 'add', 'withdraw'

  @override
  void dispose() {
    _reasonController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('إدارة درج النقود'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'نوع العملية'),
                items: const [
                  DropdownMenuItem(value: 'open', child: Text('فتح الدرج فقط')),
                  DropdownMenuItem(value: 'add', child: Text('إضافة مبلغ')),
                  DropdownMenuItem(value: 'withdraw', child: Text('سحب مبلغ')),
                ],
                onChanged: (val) => setState(() => _type = val!),
              ),
              const SizedBox(height: 16),
              if (_type != 'open')
                TextField(
                  controller: _amountController,
                  decoration: const InputDecoration(
                    labelText: 'المبلغ (IQD)',
                    hintText: 'أدخل المبلغ...',
                  ),
                  keyboardType: TextInputType.number,
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _reasonController,
                decoration: const InputDecoration(
                  labelText: 'السبب',
                  hintText: 'مثلاً: صرف فكة، دفع للمورد...',
                ),
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
            onPressed: () async {
              final reason = _reasonController.text.trim();
              final amount = double.tryParse(_amountController.text) ?? 0;

              if (_type != 'open' && amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('يرجى إدخال مبلغ صحيح')),
                );
                return;
              }

              await ref.read(cashDrawerProvider).logAndOpen(
                    type: _type,
                    reason: reason.isEmpty ? null : reason,
                    amount: amount,
                  );

              // Print a receipt for add / withdraw / manual-open ops.
              if (mounted) {
                await CashDrawerReceipt.printDrawerReceipt(
                  context: context,
                  ref: ref,
                  type: _type,
                  amount: amount.toInt(),
                  reason: reason.isEmpty ? null : reason,
                );
              }
              if (mounted) Navigator.pop(context);
            },
            child: const Text('تنفيذ'),
          ),
        ],
      ),
    );
  }
}
