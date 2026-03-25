import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../providers/data_providers.dart';
import '../screens/camera_scanner_screen.dart';
import '../utils/app_colors.dart';

class QrScannerApprovalScreen extends ConsumerStatefulWidget {
  const QrScannerApprovalScreen({super.key});

  @override
  ConsumerState<QrScannerApprovalScreen> createState() =>
      _QrScannerApprovalScreenState();
}

class _QrScannerApprovalScreenState
    extends ConsumerState<QrScannerApprovalScreen> {
  bool _isSending = false;

  Future<void> _scanAndApprove() async {
    final sessionId = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const CameraScannerScreen(title: 'مسح رمز جلسة الكومبيوتر'),
      ),
    );

    if (sessionId == null || sessionId.isEmpty || !mounted) return;

    final currentUser = ref.read(authProvider);
    if (currentUser == null) return;

    setState(() => _isSending = true);

    try {
      final client = ref.read(supabaseProvider);

      await client.from('sessions').insert({
        'user_id': currentUser.id,
        'session_code': sessionId,
        'started_at': DateTime.now().toIso8601String(),
        'is_active': true,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تفعيل الجلسة للكومبيوتر بنجاح! ✔️'),
            backgroundColor: Colors.green,
          ),
        );
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      debugPrint('Error inserting session: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حدث خطأ أثناء الاتصال بالكومبيوتر')),
        );
      }
    }

    if (mounted) setState(() => _isSending = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isSending) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final currentUser = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('تفعيل جلسة الكاشير'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  PhosphorIconsBold.desktop,
                  size: 80,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'مرحباً ${currentUser?.name ?? ''}، قم بمسح الـ QR الظاهر على شاشة الكومبيوتر لبدء جلستك.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 48),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.secondary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(PhosphorIconsBold.scan),
                label: const Text(
                  'مسح باركود شاشة الكومبيوتر',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                onPressed: _scanAndApprove,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
