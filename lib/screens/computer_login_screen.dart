import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../providers/data_providers.dart';
import '../models/models.dart';
import '../utils/app_colors.dart';
import '../utils/glass_container.dart';

class ComputerLoginScreen extends ConsumerStatefulWidget {
  const ComputerLoginScreen({super.key});

  @override
  ConsumerState<ComputerLoginScreen> createState() =>
      _ComputerLoginScreenState();
}

class _ComputerLoginScreenState extends ConsumerState<ComputerLoginScreen> {
  final String _sessionId = const Uuid().v4();
  bool _isLoggingIn = false;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  void _startPolling() {
    // Poll the database every 2 seconds to see if the mobile scanner
    // assigned a user to this session_code. Highly robust fallback.
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_isLoggingIn || !mounted) return;

      final client = ref.read(supabaseProvider);
      try {
        final res = await client
            .from('sessions')
            .select()
            .eq('session_code', _sessionId)
            .limit(1);

        if (res.isNotEmpty) {
          if (mounted) setState(() => _isLoggingIn = true);

          final sessionRow = res.first;
          final userId = sessionRow['user_id'];

          final userRes = await client
              .from('users')
              .select()
              .eq('id', userId)
              .single();

          final user = AppUser.fromJson(userRes);

          timer.cancel(); // Stop polling when succeeded

          if (mounted) {
            ref.read(authProvider.notifier).login(user);
          }
        }
      } catch (e) {
        debugPrint('Polling Check Error: $e');
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: SizedBox(
          width: 500,
          child: GlassContainer(
            padding: const EdgeInsets.all(48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  PhosphorIconsBold.scan,
                  size: 64,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 24),
                const Text(
                  'تسجيل دخول الكاشير',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'يُرجى استخدام تطبيق الهاتف ومسح هذا الباركود لفتح الجلسة بأسمك بأمان.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 48),
                _isLoggingIn
                    ? const Column(
                        children: [
                          CircularProgressIndicator(color: AppColors.primary),
                          SizedBox(height: 16),
                          Text(
                            'جاري تسجيل الدخول...',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      )
                    : Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: QrImageView(
                          data: _sessionId,
                          version: QrVersions.auto,
                          size: 250.0,
                          backgroundColor: Colors.white,
                        ),
                      ),
                const SizedBox(height: 24),
                if (!_isLoggingIn)
                  const Text(
                    'بانتظار قراءة الـ QR من تطبيق الهاتف...',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
