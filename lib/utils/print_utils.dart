import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_pos_printer_platform/flutter_pos_printer_platform.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
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

    // Key used to re-trigger FutureBuilder
    int scanCount = 0;

    showDialog(
      context: context,
      builder: (ctx) {
        PrinterDevice? selectedDevice;

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
                        scanCount++; // Re-trigger FutureBuilder
                        selectedDevice = null;
                      });
                    },
                    tooltip: 'تحديث البحث',
                  ),
                ],
              ),
              content: SizedBox(
                width: 700, // Wider for Two-Pane
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
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFCFCFC),
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
                                          // Shop Name design
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Image.asset(
                                                'assets/images/logo.png',
                                                color: Colors.black,
                                                width: 50,
                                                height: 50,
                                              ),
                                              const SizedBox(width: 12),
                                              const Text(
                                                'دكان بيروت',
                                                style: TextStyle(
                                                  color: Colors.black,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 55,
                                                  fontFamily: 'Alvatan',
                                                  letterSpacing: 0.8,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 25),
                                          Divider(color: Colors.black),
                                          const SizedBox(height: 15),
                                          // Sale Info
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                'التاريخ: ${DateTime.now().toString().substring(0, 16)}',
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.black54,
                                                ),
                                              ),
                                              if (saleId != null)
                                                Text(
                                                  '#$saleId',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.black,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 15),
                                          Divider(color: Colors.black),
                                          const SizedBox(height: 15),
                                          // Items
                                          const Row(
                                            children: [
                                              Expanded(
                                                flex: 3,
                                                child: Text(
                                                  'الصنف',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.black,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: Text(
                                                  'الكمية',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.black,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: Text(
                                                  'السعر',
                                                  textAlign: TextAlign.right,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.black,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          ...itemsToPrint.map(
                                            (item) => Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 4,
                                                  ),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    flex: 3,
                                                    child: Text(
                                                      item.product.name,
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        color: Colors.black,
                                                      ),
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: Text(
                                                      'x${item.quantity.toInt()}',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: const TextStyle(
                                                        color: Colors.black,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: Text(
                                                      '${(item.product.price * item.quantity).toInt()}',
                                                      textAlign:
                                                          TextAlign.right,
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        color: Colors.black,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 20),
                                          Divider(
                                            color: Colors.black,
                                            thickness: 2,
                                          ),
                                          const SizedBox(height: 15),
                                          // Total
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              const Text(
                                                'المجموع الكلي',
                                                style: TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 14,
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
                                          const SizedBox(height: 20),
                                          // Footer
                                          const Center(
                                            child: Column(
                                              children: [
                                                SizedBox(height: 6),
                                                Text(
                                                  'شكراً لزيارتكم.. ننتظركم دائماً',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.black54,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
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
                              const SizedBox(height: 12),
                              if (isScanning)
                                const Expanded(
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircularProgressIndicator(),
                                        SizedBox(height: 16),
                                        Text(
                                          'جاري البحث...',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
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
                                          onTap: () {
                                            setState(() {
                                              selectedDevice = device;
                                            });
                                          },
                                        ),
                                      );
                                    },
                                  ),
                                )
                              else
                                const Expanded(
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          PhosphorIconsRegular.empty,
                                          size: 40,
                                          color: Colors.grey,
                                        ),
                                        SizedBox(height: 12),
                                        Text(
                                          'لم يتم العثور على طابعات USB\nتأكد من إزالة الطابعة من إعدادات الماك',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
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
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
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
  ) async {
    try {
      await ref
          .read(printingServiceProvider)
          .printReceipt(
            items,
            total,
            selectedDevice: device,
            saleId: saleId,
            networkIp: networkIp,
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
