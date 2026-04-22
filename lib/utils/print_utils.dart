import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_pos_printer_platform/flutter_pos_printer_platform.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:barcode_widget/barcode_widget.dart';
import '../services/printing_service.dart';
import '../utils/app_colors.dart';
import '../providers/data_providers.dart';

/// Receipt content body. Renders the full thermal receipt at its natural
/// height (no internal scrolling) so that when wrapped in a RepaintBoundary
/// and captured via toImage(), all items are included — regardless of cart
/// size. Previously a scrollable preview was captured directly, which
/// truncated the image after ~15 items on a 500px-tall dialog.
class _ReceiptBody extends StatelessWidget {
  final List<CartItem> items;
  final double total;
  final int? saleId;

  const _ReceiptBody({
    required this.items,
    required this.total,
    required this.saleId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 230,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/logo.png',
                color: Colors.black,
                width: 40,
                height: 40,
              ),
              const SizedBox(width: 12),
              const Text(
                'دكان بيروت',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 40,
                  fontFamily: 'Alvatan',
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'التاريخ: ${DateTime.now().toString().substring(0, 10)}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.black,
                      ),
                    ),
                    Text(
                      'الوقت: ${DateTime.now().toString().substring(11, 16)}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
                if (saleId != null)
                  Text(
                    '# $saleId',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black, width: 0.7),
              borderRadius: BorderRadius.circular(4),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(3),
                  1: FlexColumnWidth(1),
                  2: FlexColumnWidth(1.5),
                },
                border: TableBorder.all(color: Colors.black, width: 1),
                children: [
                  const TableRow(
                    children: [
                      Padding(
                        padding: EdgeInsets.all(4.0),
                        child: Text(
                          'الصنف',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.all(4.0),
                        child: Text(
                          'الكمية',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.all(4.0),
                        child: Text(
                          'السعر',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  ...items.map(
                    (item) => TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Text(
                            item.product.name,
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Text(
                            '${item.quantity.toInt()}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Text(
                            '${((item.priceOverride ?? item.product.price) * item.quantity).toInt()}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'المجموع الكلي',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${total.toInt()} د.ع',
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'متواجدين ٢٤ ساعة',
                        style: TextStyle(fontSize: 10, color: Colors.black),
                      ),
                      Text(
                        'توصيل مجاني داخل المنطقة',
                        style: TextStyle(fontSize: 10, color: Colors.black),
                      ),
                      Text(
                        'امسح الكود تابعنا على تيك توك',
                        style: TextStyle(fontSize: 10, color: Colors.black),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                QrImageView(
                  data: 'https://linktr.ee/dukanBeirut',
                  version: QrVersions.auto,
                  size: 40.0,
                  padding: EdgeInsets.zero,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (saleId != null)
            Center(
              child: BarcodeWidget(
                barcode: Barcode.code128(),
                data: saleId.toString(),
                width: double.infinity,
                height: 30,
                style: const TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),
          const Center(
            child: Text(
              'شكراً لزيارتكم.. ننتظركم دائماً',
              style: TextStyle(fontSize: 10, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}

class PrintUtils {
  static void showPrintDialog({
    required BuildContext context,
    required WidgetRef ref,
    required List<CartItem> cartItems,
    required double total,
    int? saleId,
  }) {
    final itemsToPrint = [...cartItems];
    final GlobalKey receiptKey = GlobalKey();
    int scanCount = 0;

    showDialog(
      context: context,
      builder: (ctx) {
        PrinterDevice? selectedDevice;
        PrinterProtocol selectedProtocol = PrinterProtocol.escPos;
        bool hasAutoPrinted = false;

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Text('اختيار الطابعة'),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(
                      PhosphorIconsBold.arrowsClockwise,
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() {
                        scanCount++;
                        selectedDevice = null;
                        hasAutoPrinted = false;
                      });
                    },
                    tooltip: 'تحديث البحث',
                  ),
                ],
              ),
              content: SizedBox(
                width: 700,
                height: 500,
                child: FutureBuilder<List<PrinterDevice>>(
                  key: ValueKey(scanCount),
                  future: ref
                      .read(printingServiceProvider)
                      .getAvailablePrinters(),
                  builder: (context, snapshot) {
                    final availablePrinters = snapshot.data ?? [];
                    final isScanning =
                        snapshot.connectionState == ConnectionState.waiting;

                    // Auto-select and print if a printer is found
                    if (!isScanning &&
                        availablePrinters.isNotEmpty &&
                        !hasAutoPrinted) {
                      hasAutoPrinted = true;
                      selectedDevice = availablePrinters.first;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (context.mounted) {
                          _triggerPrint(
                            context,
                            ref,
                            itemsToPrint,
                            total,
                            selectedDevice,
                            saleId,
                            null,
                            selectedProtocol,
                            receiptKey,
                          );
                          Navigator.pop(ctx);
                        }
                      });
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- Left Pane: Premium Thermal Receipt ---
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'معاينة الوصل:',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: Center(
                                  child: Container(
                                    width: 230, // ~72mm at 2.5 pixel ratio
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.1,
                                          ),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: SingleChildScrollView(
                                        child: _ReceiptBody(
                                          items: itemsToPrint,
                                          total: total,
                                          saleId: saleId,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 32),
                        // --- Right Pane: Printer Selection ---
                        Expanded(
                          flex: 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'اختيار الطابعة:',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.all(4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => setState(
                                          () => selectedProtocol =
                                              PrinterProtocol.escPos,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                selectedProtocol ==
                                                    PrinterProtocol.escPos
                                                ? AppColors.primary
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            'وصل (ESC/POS)',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color:
                                                  selectedProtocol ==
                                                      PrinterProtocol.escPos
                                                  ? Colors.white
                                                  : Colors.black54,
                                              fontWeight:
                                                  selectedProtocol ==
                                                      PrinterProtocol.escPos
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => setState(
                                          () => selectedProtocol =
                                              PrinterProtocol.tspl,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                selectedProtocol ==
                                                    PrinterProtocol.tspl
                                                ? AppColors.primary
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            'لاصق (TSPL)',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color:
                                                  selectedProtocol ==
                                                      PrinterProtocol.tspl
                                                  ? Colors.white
                                                  : Colors.black54,
                                              fontWeight:
                                                  selectedProtocol ==
                                                      PrinterProtocol.tspl
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (isScanning)
                                const Expanded(
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              else if (availablePrinters.isNotEmpty)
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: availablePrinters.length,
                                    itemBuilder: (context, index) {
                                      final device = availablePrinters[index];
                                      final isSelected =
                                          selectedDevice == device;
                                      return Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? AppColors.primary.withValues(
                                                  alpha: 0.1,
                                                )
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: isSelected
                                                ? AppColors.primary
                                                : Colors.grey.shade300,
                                            width: isSelected ? 2 : 1,
                                          ),
                                        ),
                                        child: ListTile(
                                          dense: true,
                                          leading: Icon(
                                            PhosphorIconsRegular.printer,
                                            size: 22,
                                            color: isSelected
                                                ? AppColors.primary
                                                : Colors.black54,
                                          ),
                                          title: Text(
                                            device.name,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: isSelected
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                          subtitle: Text(
                                            'V: ${device.vendorId}, P: ${device.productId}',
                                            style: const TextStyle(
                                              fontSize: 10,
                                            ),
                                          ),
                                          onTap: () => setState(
                                            () => selectedDevice = device,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                )
                              else
                                const Expanded(
                                  child: Center(
                                    child: Text(
                                      'لم يتم العثور على طابعات USB',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء'),
                ),
                if (selectedDevice != null)
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _triggerPrint(
                        context,
                        ref,
                        itemsToPrint,
                        total,
                        selectedDevice,
                        saleId,
                        null,
                        selectedProtocol,
                        receiptKey,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    child: const Text(
                      'طباعة الفاتورة',
                      style: TextStyle(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  static void _triggerPrint(
    BuildContext context,
    WidgetRef ref,
    List<CartItem> items,
    double total,
    PrinterDevice? device,
    int? saleId,
    String? networkIp,
    PrinterProtocol protocol,
    GlobalKey _, // kept for signature compatibility; preview key no longer captured
  ) async {
    OverlayEntry? offscreenEntry;
    try {
      // Render the receipt offscreen at its natural (unbounded) height so
      // that all items are included in the captured image — the dialog
      // preview is scrollable and would clip receipts with >~15 items.
      final GlobalKey captureKey = GlobalKey();
      final overlay = Overlay.of(context, rootOverlay: true);
      offscreenEntry = OverlayEntry(
        builder: (_) => Positioned(
          left: -4000,
          top: 0,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Material(
              color: Colors.transparent,
              child: RepaintBoundary(
                key: captureKey,
                child: _ReceiptBody(
                  items: items,
                  total: total,
                  saleId: saleId,
                ),
              ),
            ),
          ),
        ),
      );
      overlay.insert(offscreenEntry);

      // Wait for layout + paint before capturing. Two end-of-frame waits plus
      // a small delay covers asset-image decoding (logo) on the first print
      // and gives the barcode / QR widgets time to paint on very long lists.
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      await Future.delayed(const Duration(milliseconds: 250));

      final RenderRepaintBoundary? boundary =
          captureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Unable to capture receipt image');
      final ui.Image image = await boundary.toImage(pixelRatio: 2.5);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) throw Exception('Unable to convert image to data');
      final Uint8List imgBytes = byteData.buffer.asUint8List();

      // Remove offscreen render before doing the (potentially slow) print.
      offscreenEntry.remove();
      offscreenEntry = null;

      await ref
          .read(printingServiceProvider)
          .printReceiptImage(
            imgBytes,
            selectedDevice: device,
            networkIp: networkIp,
            protocol: protocol,
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في الطباعة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      offscreenEntry?.remove();
    }
  }
}

/// Receipt body for a cash-drawer operation (withdraw / deposit / manual
/// open). Rendered offscreen at its natural height and printed via the
/// same ESC/POS image path as sale receipts.
class _DrawerReceiptBody extends StatelessWidget {
  final String type; // 'withdraw', 'add', 'open'
  final int amount;
  final String? reason;
  final int balanceAfter;
  final String? userName;
  final DateTime timestamp;

  const _DrawerReceiptBody({
    required this.type,
    required this.amount,
    required this.reason,
    required this.balanceAfter,
    required this.userName,
    required this.timestamp,
  });

  String get _titleAr {
    switch (type) {
      case 'withdraw':
        return 'وصل سحب أموال';
      case 'add':
        return 'وصل إيداع أموال';
      default:
        return 'وصل فتح الدرج';
    }
  }

  String _fmtDate() {
    final d = timestamp.toLocal();
    two(int x) => x.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}  ${two(d.hour)}:${two(d.minute)}';
  }

  String _fmtMoney(int v) {
    final s = v.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return (v < 0 ? '-' : '') + buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 230,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/logo.png',
                color: Colors.black,
                width: 36,
                height: 36,
              ),
              const SizedBox(width: 10),
              const Text(
                'دكان بيروت',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 32,
                  fontFamily: 'Alvatan',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black, width: 0.7),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                _titleAr,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _row('التاريخ', _fmtDate()),
          if (userName != null) _row('الموظف', userName!),
          if (reason != null && reason!.isNotEmpty) _row('السبب', reason!),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  type == 'withdraw' ? 'المبلغ المسحوب' : 'المبلغ',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${_fmtMoney(amount)} د.ع',
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'رصيد الدرج بعد العملية',
                  style: TextStyle(color: Colors.black, fontSize: 10),
                ),
                Text(
                  '${_fmtMoney(balanceAfter)} د.ع',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Center(
            child: Text(
              '— نسخة للمحاسبة —',
              style: TextStyle(fontSize: 10, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.black54, fontSize: 10),
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(color: Colors.black, fontSize: 11),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

/// Prints a cash-drawer operation receipt. Uses the same offscreen-overlay +
/// RepaintBoundary capture pattern as sale receipts so the full body is
/// included in the bitmap sent to the printer.
class CashDrawerReceipt {
  static Future<void> printDrawerReceipt({
    required BuildContext context,
    required WidgetRef ref,
    required String type, // 'withdraw', 'add', 'open'
    required int amount,
    String? reason,
  }) async {
    OverlayEntry? offscreenEntry;
    try {
      final supabase = ref.read(supabaseProvider);
      int balanceAfter = 0;
      try {
        balanceAfter = await BalanceRepo.getRemote(supabase);
      } catch (_) {}

      final user = ref.read(authProvider);
      final GlobalKey captureKey = GlobalKey();
      final overlay = Overlay.of(context, rootOverlay: true);
      offscreenEntry = OverlayEntry(
        builder: (_) => Positioned(
          left: -4000,
          top: 0,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Material(
              color: Colors.transparent,
              child: RepaintBoundary(
                key: captureKey,
                child: _DrawerReceiptBody(
                  type: type,
                  amount: amount,
                  reason: reason,
                  balanceAfter: balanceAfter,
                  userName: user?.name,
                  timestamp: DateTime.now(),
                ),
              ),
            ),
          ),
        ),
      );
      overlay.insert(offscreenEntry);

      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      await Future.delayed(const Duration(milliseconds: 250));

      final RenderRepaintBoundary? boundary =
          captureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Unable to capture drawer receipt');
      final ui.Image image = await boundary.toImage(pixelRatio: 2.5);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      offscreenEntry.remove();
      offscreenEntry = null;
      if (byteData == null) return;

      await ref.read(printingServiceProvider).printReceiptImage(
            byteData.buffer.asUint8List(),
          );
    } catch (e) {
      debugPrint('Drawer receipt print failed: $e');
      final messenger = context.mounted
          ? ScaffoldMessenger.maybeOf(context)
          : null;
      messenger?.showSnackBar(
        SnackBar(
          content: Text('تعذّر طباعة وصل العملية: $e'),
          backgroundColor: Colors.orange,
        ),
      );
    } finally {
      offscreenEntry?.remove();
    }
  }
}
