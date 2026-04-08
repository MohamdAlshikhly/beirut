import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../models/models.dart';
import '../providers/data_providers.dart';
import '../services/sync_service.dart';
import '../utils/glass_container.dart';

class SessionsMonitoringScreen extends ConsumerStatefulWidget {
  const SessionsMonitoringScreen({super.key});

  @override
  ConsumerState<SessionsMonitoringScreen> createState() =>
      _SessionsMonitoringScreenState();
}

class _SessionsMonitoringScreenState
    extends ConsumerState<SessionsMonitoringScreen> {
  bool _isLoading = true;
  List<SessionLog> _sessions = [];
  StreamSubscription? _realtimeSubscription;
  final Set<int> _endingSessionIds = {};

  @override
  void initState() {
    super.initState();
    _fetchSessions();
    _initRealtimeListener();
  }

  void _initRealtimeListener() {
    _realtimeSubscription = ref
        .read(supabaseProvider)
        .from('sessions')
        .stream(primaryKey: ['id'])
        .listen((_) => _fetchSessions());
  }

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
    super.dispose();
  }

  Future<void> _fetchSessions() async {
    setState(() => _isLoading = true);
    try {
      final supabase = ref.read(supabaseProvider);
      final response = await supabase
          .from('sessions')
          .select('*, users(name)')
          .order('started_at', ascending: false)
          .limit(100);

      if (mounted) {
        setState(() {
          _sessions = (response as List)
              .map((e) => SessionLog.fromJson(e))
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Error fetching sessions: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _endSession(int sessionId) async {
    if (_endingSessionIds.contains(sessionId)) return;
    setState(() => _endingSessionIds.add(sessionId));
    try {
      final supabase = ref.read(supabaseProvider);
      await supabase
          .from('sessions')
          .update({
            'is_active': false,
            'ended_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', sessionId);
      await _fetchSessions();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل إنهاء الجلسة، تحقق من الاتصال')),
        );
      }
    } finally {
      if (mounted) setState(() => _endingSessionIds.remove(sessionId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'مراقبة جلسات الكاشير',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(PhosphorIconsBold.arrowsClockwise),
            onPressed: () async {
              await ref.read(syncServiceProvider).syncDown();
              _fetchSessions();
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                : [const Color(0xFFF1F5F9), const Color(0xFFE2E8F0)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _sessions.isEmpty
            ? const Center(
                child: Text(
                  'لا توجد جلسات مسجلة بعد',
                  style: TextStyle(fontSize: 18),
                ),
              )
            : RefreshIndicator(
                onRefresh: _fetchSessions,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _sessions.length,
                  itemBuilder: (context, index) {
                    final session = _sessions[index];
                    final DateFormat formatter = DateFormat(
                      'yyyy-MM-dd hh:mm a',
                    );
                    final startFormatted = formatter.format(session.startedAt);
                    final endFormatted = session.endedAt != null
                        ? formatter.format(session.endedAt!)
                        : 'لم تنتهِ';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: GlassContainer(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: session.isActive
                                    ? Colors.green.withValues(alpha: 0.1)
                                    : Colors.grey.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                session.isActive
                                    ? PhosphorIconsFill.desktop
                                    : PhosphorIconsFill.stopCircle,
                                color: session.isActive
                                    ? Colors.green
                                    : Colors.grey,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    session.userName ?? 'مستخدم محذوف',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(
                                        PhosphorIconsRegular.clock,
                                        size: 14,
                                        color: Colors.grey,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        startFormatted,
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (session.endedAt != null)
                                    Row(
                                      children: [
                                        const Icon(
                                          PhosphorIconsRegular.clockAfternoon,
                                          size: 14,
                                          color: Colors.grey,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          endFormatted,
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                            if (session.isActive)
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: _endingSessionIds.contains(session.id)
                                    ? null
                                    : () => _endSession(session.id),
                                child: _endingSessionIds.contains(session.id)
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('إنهاء'),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'منتهية',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
