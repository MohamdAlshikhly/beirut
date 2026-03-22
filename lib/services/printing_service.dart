import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_pos_printer_platform/flutter_pos_printer_platform.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import '../providers/data_providers.dart';
import 'package:enough_convert/enough_convert.dart';

final printingServiceProvider = Provider((ref) => PrintingService(ref));

class PrintingService {
  final Ref ref;
  PrintingService(this.ref);

  Future<List<PrinterDevice>> getAvailablePrinters() async {
    final printerManager = PrinterManager.instance;
    final devices = <PrinterDevice>[];
    final logNotifier = ref.read(printingLogsProvider.notifier);

    Future.microtask(() {
      logNotifier.clear();
      logNotifier.add('بدء البحث عن طابعات USB...');
    });

    try {
      // Listen for a short duration to collect USB devices
      final stream = printerManager.discovery(type: PrinterType.usb);
      await for (final device in stream.timeout(const Duration(seconds: 4))) {
        Future.microtask(() {
          logNotifier.add(
            'تم العثور على جهاز: ${device.name} (V:${device.vendorId}, P:${device.productId})',
          );
        });
        devices.add(device);
      }

      Future.microtask(() {
        if (devices.isEmpty) {
          logNotifier.add('انتهى البحث: لم يتم اكتشاف أي طابعة USB.');
          logNotifier.add(
            'نصيحة: تأكد من إزالة الطابعة من إعدادات الـ Mac (Printers & Scanners) لكي يتمكن البرنامج من الوصول إليها مباشرة.',
          );
        } else {
          logNotifier.add('انتهى البحث: تم اكتشاف ${devices.length} طابعة.');
        }
      });
    } catch (e) {
      // Timeout reached or other error, we return what we found
      Future.microtask(() {
        logNotifier.add('خروج من البحث: $e');
      });
    }

    return devices;
  }

  Future<void> printReceipt(
    List<CartItem> cartItems,
    double total, {
    int? saleId,
    PrinterDevice? selectedDevice,
    String? networkIp,
  }) async {
    // 1. Generate Content
    final bytes = await _generateTsplBytes(cartItems, total, saleId: saleId);

    // 2. Connect and Send
    final printerManager = PrinterManager.instance;

    if (networkIp != null && networkIp.isNotEmpty) {
      await printerManager.connect(
        type: PrinterType.network,
        model: TcpPrinterInput(ipAddress: networkIp),
      );
      await printerManager.send(type: PrinterType.network, bytes: bytes);
      await printerManager.disconnect(type: PrinterType.network);
      return;
    }

    PrinterDevice? device = selectedDevice;
    if (device == null) {
      final devices = await getAvailablePrinters();
      if (devices.isEmpty) {
        throw Exception('لم يتم العثور على طابعة مرتبطة عبر USB');
      }
      device = devices.first;
    }

    await printerManager.connect(
      type: PrinterType.usb,
      model: UsbPrinterInput(
        name: device.name,
        productId: device.productId,
        vendorId: device.vendorId,
      ),
    );

    await printerManager.send(type: PrinterType.usb, bytes: bytes);
    await printerManager.disconnect(type: PrinterType.usb);
  }

  Future<Uint8List> _generateTsplBytes(
    List<CartItem> items,
    double total, {
    int? saleId,
  }) async {
    final currencyFormatter = NumberFormat('#,##0', 'en_US');
    final dateFormatter = DateFormat('yyyy-MM-dd HH:mm');

    StringBuffer tspl = StringBuffer();

    // Calculate adaptive height: Header(200) + Items(40 each) + Footer(200)
    int height = 500 + (items.length * 40);

    tspl.writeln('SIZE 80 mm, ${height / 8} mm');
    tspl.writeln('GAP 0,0');
    tspl.writeln('DIRECTION 1');
    tspl.writeln('CLS');

    int y = 30;

    // Shop Name
    tspl.writeln('TEXT 400, $y, "FONT001", 0, 2, 2, "دكان بيروت"');
    y += 60;

    if (saleId != null) {
      tspl.writeln('TEXT 40, $y, "FONT001", 0, 1, 1, "Invoice: #$saleId"');
      y += 40;
    }
    tspl.writeln(
      'TEXT 40, $y, "FONT001", 0, 1, 1, "Date: ${dateFormatter.format(DateTime.now())}"',
    );
    y += 50;

    tspl.writeln('BAR 40, $y, 500, 2');
    y += 20;

    // Items Header
    tspl.writeln('TEXT 40, $y, "FONT001", 0, 1, 1, "Item"');
    tspl.writeln('TEXT 320, $y, "FONT001", 0, 1, 1, "Qty"');
    tspl.writeln('TEXT 450, $y, "FONT001", 0, 1, 1, "Price"');
    y += 40;
    tspl.writeln('BAR 40, $y, 500, 1');
    y += 20;

    for (var item in items) {
      // Shorten name if too long
      String name = item.product.name;
      if (name.length > 20) name = name.substring(0, 17) + '...';

      tspl.writeln('TEXT 40, $y, "FONT001", 0, 1, 1, "$name"');
      tspl.writeln('TEXT 320, $y, "FONT001", 0, 1, 1, "${item.quantity}"');
      tspl.writeln(
        'TEXT 450, $y, "FONT001", 0, 1, 1, "${currencyFormatter.format(item.product.price)}"',
      );
      y += 40;
    }

    y += 20;
    tspl.writeln('BAR 40, $y, 500, 2');
    y += 30;

    tspl.writeln(
      'TEXT 40, $y, "FONT001", 0, 2, 2, "TOTAL: ${currencyFormatter.format(total)} IQD"',
    );
    y += 80;

    tspl.writeln(
      'TEXT 400, $y, "FONT001", 0, 1, 1, "دكان بيروت.. طعم الأصالة"',
    );
    y += 40;
    tspl.writeln(
      'TEXT 400, $y, "FONT001", 0, 1, 1, "شكراً لزيارتكم.. ننتظركم دائماً"',
    );

    tspl.writeln('PRINT 1, 1');

    try {
      const codec = Windows1256Codec();
      return Uint8List.fromList(codec.encode(tspl.toString()));
    } catch (e) {
      debugPrint('Encoding error, falling back to UTF-8: $e');
      return Uint8List.fromList(utf8.encode(tspl.toString()));
    }
  }
}
