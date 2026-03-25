import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../providers/data_providers.dart';
import '../utils/app_colors.dart';
import '../utils/glass_container.dart';

class RetireMoneyScreen extends ConsumerStatefulWidget {
  const RetireMoneyScreen({super.key});

  @override
  ConsumerState<RetireMoneyScreen> createState() => _RetireMoneyScreenState();
}

class _RetireMoneyScreenState extends ConsumerState<RetireMoneyScreen> {
  final _amountController = TextEditingController();
  bool _isLoading = false;

  void _save(double maxAmount) async {
    if (_amountController.text.isEmpty) return;
    final amount = double.tryParse(_amountController.text) ?? 0;

    if (amount <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('يرجى إدخال مبلغ صحيح')));
      return;
    }

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
          .limit(1)
          .maybeSingle();

      double currentBal = (res?['currentBalance'] as num?)?.toDouble() ?? 0.0;
      currentBal -= amount;

      await client.from('balance').insert({
        'currentBalance': currentBal.toInt(),
      });

      ref.invalidate(balanceProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم سحب المبلغ بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final balanceAsync = ref.watch(balanceProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currencyFormatter = NumberFormat('#,##0', 'en_US');

    return Scaffold(
      appBar: AppBar(title: const Text('سحب أموال'), centerTitle: true),
      body: Container(
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                : [const Color(0xFFF1F5F9), const Color(0xFFE2E8F0)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: balanceAsync.when(
          data: (curBal) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlassContainer(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      const Icon(
                        PhosphorIconsFill.wallet,
                        size: 64,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'الرصيد الحالي في الدرج',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${currencyFormatter.format(curBal)} د.ع',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    labelText: 'ادخل المبلغ المراد سحبه',
                    hintText: '0.00',
                    prefixIcon: const Icon(PhosphorIconsRegular.money),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    filled: true,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () => setState(
                        () => _amountController.text = curBal.toString(),
                      ),
                      icon: const Icon(
                        PhosphorIconsRegular.arrowsOutLineHorizontal,
                      ),
                      label: const Text(
                        'سحب الكل',
                        style: TextStyle(fontSize: 18),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 48),
                ElevatedButton(
                  onPressed: _isLoading ? null : () => _save(curBal.toDouble()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 8,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'تأكيد عملية السحب',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('خطأ في تحميل الرصيد: $e')),
        ),
      ),
    );
  }
}
