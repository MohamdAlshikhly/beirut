import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../utils/app_colors.dart';

/// Shows a cash payment dialog that asks for the amount the customer gave
/// and displays the change to return.
///
/// Returns 'print', 'no_print', or null (cancelled).
Future<String?> showCashChangeDialog(
  BuildContext context, {
  required double total,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CashChangeDialog(total: total),
  );
}

class _CashChangeDialog extends StatefulWidget {
  final double total;
  const _CashChangeDialog({required this.total});

  @override
  State<_CashChangeDialog> createState() => _CashChangeDialogState();
}

class _CashChangeDialogState extends State<_CashChangeDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  double _given = 0;

  static const _denominations = [
    500, 1000, 2000, 5000, 10000, 25000, 50000,
    100000, 250000, 500000,
  ];

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final parsed = double.tryParse(
            _controller.text.replaceAll(',', '').replaceAll(' ', ''),
          ) ??
          0;
      if (parsed != _given) setState(() => _given = parsed);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _setAmount(double amount) {
    _controller.text = amount.toInt().toString();
    // Move cursor to end
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    setState(() => _given = amount);
  }

  List<double> _quickAmounts() {
    final exact = widget.total;
    final result = <double>[exact];
    for (final d in _denominations) {
      final dbl = d.toDouble();
      if (dbl > exact && result.length < 7) result.add(dbl);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'en_US');
    final change = _given - widget.total;
    final isEnough = _given >= widget.total;
    final hasInput = _given > 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final changeColor = !hasInput
        ? Colors.grey
        : isEnough
            ? Colors.green
            : Colors.red;

    return CallbackShortcuts(
      bindings: {
        // Enter is handled by the TextField's onSubmitted (= إتمام بدون طباعة).
        // F12 is an explicit shortcut for printing; Esc cancels the dialog.
        const SingleActivator(LogicalKeyboardKey.f12): () =>
            Navigator.pop(context, 'print'),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context, null),
      },
      child: Focus(
        autofocus: true,
        child: _buildDialog(fmt, change, isEnough, hasInput, changeColor, isDark),
      ),
    );
  }

  Widget _buildDialog(
    NumberFormat fmt,
    double change,
    bool isEnough,
    bool hasInput,
    Color changeColor,
    bool isDark,
  ) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              PhosphorIconsFill.money,
              color: AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'دفع نقدي',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Total ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'المجموع الكلي',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${fmt.format(widget.total)} د.ع',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Given amount input ────────────────────────────────
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                labelText: 'المبلغ المُعطى من الزبون',
                suffixText: 'د.ع',
                floatingLabelAlignment: FloatingLabelAlignment.center,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary, width: 2),
                ),
              ),
              // Pressing Enter here completes the sale WITHOUT printing.
              // The paid amount is optional — empty input is valid; cashier
              // only fills it in when they want the change calculation.
              onSubmitted: (_) => Navigator.pop(context, 'no_print'),
            ),

            const SizedBox(height: 14),

            // ── Quick amount chips ────────────────────────────────
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _quickAmounts().map((amount) {
                final isExact = amount == widget.total;
                final isSelected = _given == amount;
                return ChoiceChip(
                  label: Text(
                    isExact
                        ? 'الدفع بالكامل'
                        : '${fmt.format(amount)} د.ع',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? AppColors.secondary
                          : (isDark ? Colors.white : AppColors.secondary),
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: AppColors.primary,
                  onSelected: (_) => _setAmount(amount),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // ── Change display ────────────────────────────────────
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: changeColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: changeColor.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        !hasInput
                            ? PhosphorIconsRegular.arrowLeft
                            : isEnough
                                ? PhosphorIconsFill.checkCircle
                                : PhosphorIconsFill.warning,
                        color: changeColor,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        !hasInput
                            ? 'أدخل المبلغ أعلاه'
                            : isEnough
                                ? 'الباقي للزبون'
                                : 'المبلغ غير كافٍ!',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: changeColor,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    !hasInput
                        ? '—'
                        : '${fmt.format(change.abs())} د.ع',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: changeColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('إلغاء (Esc)'),
        ),
        const SizedBox(width: 4),
        // Print is now an explicit action — not the Enter default. The paid
        // amount is optional; the buttons stay enabled even with no input.
        ElevatedButton.icon(
          onPressed: () => Navigator.pop(context, 'print'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.secondary,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(PhosphorIconsRegular.printer, size: 18),
          label: const Text('إتمام وطباعة (F12)'),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.pop(context, 'no_print'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.secondary,
          ),
          icon: const Icon(PhosphorIconsRegular.check, size: 18),
          label: const Text('إتمام (Enter)'),
        ),
      ],
    );
  }
}
