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
                                  child: RepaintBoundary(
                                    key: receiptKey,
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
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 24,
                                            vertical: 30,
                                          ),
                                          child: Column(
                                            children: [
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
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
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 40,
                                                      fontFamily: 'Alvatan',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 5),
                                              Container(
                                                width: double.infinity,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  border: Border.all(
                                                    color: Colors.black,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          'التاريخ: ${DateTime.now().toString().substring(0, 10)}',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 10,
                                                                color: Colors
                                                                    .black,
                                                              ),
                                                        ),
                                                        Text(
                                                          'الوقت: ${DateTime.now().toString().substring(11, 16)}',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 10,
                                                                color: Colors
                                                                    .black,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                    if (saleId != null)
                                                      Text(
                                                        '# $saleId',
                                                        style: const TextStyle(
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Colors.black,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Container(
                                                decoration: BoxDecoration(
                                                  border: Border.all(
                                                    color: Colors.black,
                                                    width: 0.7,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  child: Table(
                                                    columnWidths: const {
                                                      0: FlexColumnWidth(3),
                                                      1: FlexColumnWidth(1),
                                                      2: FlexColumnWidth(1.5),
                                                    },
                                                    border: TableBorder.all(
                                                      color: Colors.black,
                                                      width: 1,
                                                    ),
                                                    children: [
                                                      const TableRow(
                                                        children: [
                                                          Padding(
                                                            padding:
                                                                EdgeInsets.all(
                                                                  4.0,
                                                                ),
                                                            child: Text(
                                                              'الصنف',
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                color: Colors
                                                                    .black,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                          ),
                                                          Padding(
                                                            padding:
                                                                EdgeInsets.all(
                                                                  4.0,
                                                                ),
                                                            child: Text(
                                                              'الكمية',
                                                              textAlign:
                                                                  TextAlign
                                                                      .center,
                                                              style: TextStyle(
                                                                fontSize: 9,
                                                                color: Colors
                                                                    .black,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                          ),
                                                          Padding(
                                                            padding:
                                                                EdgeInsets.all(
                                                                  4.0,
                                                                ),
                                                            child: Text(
                                                              'السعر',
                                                              textAlign:
                                                                  TextAlign
                                                                      .center,
                                                              style: TextStyle(
                                                                color: Colors
                                                                    .black,
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      ...itemsToPrint.map(
                                                        (item) => TableRow(
                                                          children: [
                                                            Padding(
                                                              padding:
                                                                  const EdgeInsets.all(
                                                                    4.0,
                                                                  ),
                                                              child: Text(
                                                                item
                                                                    .product
                                                                    .name,
                                                                style: const TextStyle(
                                                                  color: Colors
                                                                      .black,
                                                                  fontSize: 10,
                                                                ),
                                                              ),
                                                            ),
                                                            Padding(
                                                              padding:
                                                                  const EdgeInsets.all(
                                                                    4.0,
                                                                  ),
                                                              child: Text(
                                                                '${item.quantity.toInt()}',
                                                                textAlign:
                                                                    TextAlign
                                                                        .center,
                                                                style: const TextStyle(
                                                                  color: Colors
                                                                      .black,
                                                                  fontSize: 10,
                                                                ),
                                                              ),
                                                            ),
                                                            Padding(
                                                              padding:
                                                                  const EdgeInsets.all(
                                                                    4.0,
                                                                  ),
                                                              child: Text(
                                                                '${((item.priceOverride ?? item.product.price) * item.quantity).toInt()}',
                                                                textAlign:
                                                                    TextAlign
                                                                        .center,
                                                                style: const TextStyle(
                                                                  color: Colors
                                                                      .black,
                                                                  fontSize: 10,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
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
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  border: Border.all(
                                                    color: Colors.black,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    const Text(
                                                      'المجموع الكلي',
                                                      style: TextStyle(
                                                        color: Colors.black,
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                      ),
                                                    ),
                                                    Text(
                                                      '${total.toInt()} د.ع',
                                                      style: const TextStyle(
                                                        fontSize: 18,
                                                        color: Colors.black,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Container(
                                                width: double.infinity,
                                                padding: const EdgeInsets.all(
                                                  4,
                                                ),
                                                decoration: BoxDecoration(
                                                  border: Border.all(
                                                    color: Colors.black,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: const [
                                                          Text(
                                                            'متواجدين ٢٤ ساعة',
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              color:
                                                                  Colors.black,
                                                            ),
                                                          ),
                                                          Text(
                                                            'توصيل مجاني داخل المنطقة',
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              color:
                                                                  Colors.black,
                                                            ),
                                                          ),
                                                          Text(
                                                            'امسح الكود تابعنا على تيك توك',
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              color:
                                                                  Colors.black,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    QrImageView(
                                                      data:
                                                          'https://linktr.ee/dukanBeirut',
                                                      version: QrVersions.auto,
                                                      size: 40.0,
                                                      padding: EdgeInsets.zero,
                                                      eyeStyle:
                                                          const QrEyeStyle(
                                                            eyeShape: QrEyeShape
                                                                .square,
                                                            color: Colors.black,
                                                          ),
                                                      dataModuleStyle:
                                                          const QrDataModuleStyle(
                                                            dataModuleShape:
                                                                QrDataModuleShape
                                                                    .square,
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
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              const Center(
                                                child: Text(
                                                  'شكراً لزيارتكم.. ننتظركم دائماً',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.black54,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
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
    GlobalKey receiptKey,
  ) async {
    try {
      final RenderRepaintBoundary? boundary =
          receiptKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Unable to capture receipt image');
      final ui.Image image = await boundary.toImage(pixelRatio: 2.5);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) throw Exception('Unable to convert image to data');
      final Uint8List imgBytes = byteData.buffer.asUint8List();

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
    }
  }
}
