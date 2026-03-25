import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_pos_printer_platform/flutter_pos_printer_platform.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../providers/data_providers.dart';
import 'package:image/image.dart' as img;

enum PrinterProtocol { tspl, escPos }

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
        } else {
          logNotifier.add('انتهى البحث: تم اكتشاف ${devices.length} طابعة.');
        }
      });
    } catch (e) {
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
    PrinterProtocol protocol = PrinterProtocol.escPos,
  }) async {
    // This method is now legacy, but kept for compatibility.
    // It could potentially render a hidden widget to use printReceiptImage.
    final List<int> bytes = [];
    const esc = 0x1B;
    const gs = 0x1D;

    bytes.addAll([esc, 0x40]); // Init
    bytes.addAll(utf8.encode('Dukan Beirut\nReceipt\n\n'));
    if (saleId != null) bytes.addAll(utf8.encode('ID: #$saleId\n'));
    bytes.addAll(utf8.encode('Total: ${total.toInt()} IQD\n'));
    bytes.addAll([esc, 0x64, 3]); // Feed
    bytes.addAll([gs, 0x56, 66, 0]); // Cut

    await _sendBytesToPrinter(
      Uint8List.fromList(bytes),
      selectedDevice,
      networkIp,
    );
  }

  Future<void> printReceiptImage(
    Uint8List imgBytes, {
    PrinterDevice? selectedDevice,
    String? networkIp,
    PrinterProtocol protocol = PrinterProtocol.escPos,
  }) async {
    final img.Image? originalImage = img.decodeImage(imgBytes);
    if (originalImage == null) return;

    final processedImage = img.grayscale(originalImage);

    List<int> bytes = [];
    if (protocol == PrinterProtocol.escPos) {
      bytes = _generateEscPosImageBytes(processedImage);
    } else {
      bytes = _generateTsplImageBytes(processedImage);
    }

    await _sendBytesToPrinter(
      Uint8List.fromList(bytes),
      selectedDevice,
      networkIp,
    );
  }

  Future<void> _sendBytesToPrinter(
    Uint8List bytes,
    PrinterDevice? selectedDevice,
    String? networkIp,
  ) async {
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
      if (devices.isEmpty) return;
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

  List<int> _generateEscPosImageBytes(img.Image image) {
    List<int> bytes = [];
    const esc = 0x1B;
    const gs = 0x1D;

    bytes.addAll([esc, 0x40]); // Init
    bytes.addAll([esc, 0x61, 1]); // Center

    int width = image.width;
    int height = image.height;
    int widthBytes = (width + 7) ~/ 8;

    bytes.addAll([gs, 0x76, 0x30, 0]);
    bytes.add(widthBytes % 256);
    bytes.add(widthBytes ~/ 256);
    bytes.add(height % 256);
    bytes.add(height ~/ 256);

    for (int y = 0; y < height; y++) {
      for (int xByte = 0; xByte < widthBytes; xByte++) {
        int byte = 0;
        for (int bit = 0; bit < 8; bit++) {
          int x = xByte * 8 + bit;
          if (x < width) {
            final pixel = image.getPixel(x, y);
            final luminance =
                (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b);
            if (luminance < 128) byte |= (0x80 >> bit);
          }
        }
        bytes.add(byte);
      }
    }

    bytes.addAll([esc, 0x64, 3, gs, 0x56, 66, 0]);
    return bytes;
  }

  List<int> _generateTsplImageBytes(img.Image image) {
    List<int> bytes = [];
    int width = image.width;
    int height = image.height;
    int widthBytes = (width + 7) ~/ 8;

    bytes.addAll(utf8.encode('CLS\r\nBITMAP 0,0,$widthBytes,$height,0,'));

    for (int y = 0; y < height; y++) {
      for (int xByte = 0; xByte < widthBytes; xByte++) {
        int byte = 0;
        for (int bit = 0; bit < 8; bit++) {
          int x = xByte * 8 + bit;
          if (x < width) {
            final pixel = image.getPixel(x, y);
            final luminance =
                (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b);
            if (luminance < 128) byte |= (0x80 >> bit);
          }
        }
        bytes.add(byte);
      }
    }
    bytes.addAll(utf8.encode('\r\nPRINT 1,1\r\n'));
    return bytes;
  }
}
