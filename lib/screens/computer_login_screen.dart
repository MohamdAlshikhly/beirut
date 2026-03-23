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
  StreamSubscription? _realtimeSubscription;

  @override
  void initState() {
    super.initState();
    _setupRealtimeListener();
  }

  void _setupRealtimeListener() {
    final client = ref.read(supabaseProvider);
    _realtimeSubscription = client
        .from('sessions')
        .stream(primaryKey: ['id'])
        .eq('session_code', _sessionId)
        .listen(
          (data) async {
            if (data.isEmpty || _isLoggingIn || !mounted) return;

            setState(() => _isLoggingIn = true);

            try {
              final sessionRow = data.first;
              final userId = sessionRow['user_id'];

              final userRes = await client
                  .from('users')
                  .select()
                  .eq('id', userId)
                  .single();

              final user = AppUser.fromJson(userRes);

              if (mounted) {
                ref.read(authProvider.notifier).login(user);

                // Clean up: delete the session record after successful login to keep DB clean
                client
                    .from('sessions')
                    .delete()
                    .eq('session_code', _sessionId)
                    .then((_) => debugPrint('Session cleaned up'))
                    .catchError((e) => debugPrint('Session cleanup error: $e'));
              }
            } catch (e) {
              debugPrint('Login Session Error: $e');
              if (mounted) {
                setState(() => _isLoggingIn = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('فشل تسجيل الدخول، يرجى المحاولة مرة أخرى'),
                  ),
                );
              }
            }
          },
          onError: (error) {
            debugPrint('Realtime Stream Error: $error');
          },
        );
  }

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
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
