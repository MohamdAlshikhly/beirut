import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../providers/data_providers.dart';
import '../utils/glass_container.dart';

class CashDrawerHistoryScreen extends ConsumerWidget {
  const CashDrawerHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(cashDrawerLogsProvider);
    final currencyFormatter = NumberFormat('#,##0', 'en_US');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('حركات جرارة الأموال'),
        centerTitle: true,
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
        child: logsAsync.when(
          data: (logs) {
            if (logs.isEmpty) {
              return const Center(child: Text('لا توجد حركات مسجلة حالياً'));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[index];
                final isPositive = log.type == 'deposit' || (log.type == 'open' && log.amount > 0);
                final isNegative = log.type == 'withdraw' || (log.type == 'open' && log.amount < 0);
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GlassContainer(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: (isPositive ? Colors.green : (isNegative ? Colors.red : Colors.blue)).withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isPositive ? PhosphorIconsFill.trendUp : (isNegative ? PhosphorIconsFill.trendDown : PhosphorIconsFill.archive),
                            color: isPositive ? Colors.green : (isNegative ? Colors.red : Colors.blue),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                log.reason,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Text(
                                DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(log.createdAt)),
                                style: const TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        if (log.amount != 0)
                          Text(
                            '${isPositive ? '+' : ''}${currencyFormatter.format(log.amount)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isPositive ? Colors.green : Colors.red,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('حدث خطأ: $e')),
        ),
      ),
    );
  }
}

final cashDrawerLogsProvider = StreamProvider<List<CashLog>>((ref) {
  final supabase = ref.watch(supabaseProvider);
  return supabase
      .from('cash_drawer_logs')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .map((data) => data.map((e) => CashLog.fromJson(e)).toList());
});

class CashLog {
  final String id;
  final String type;
  final double amount;
  final String reason;
  final String createdAt;

  CashLog({
    required this.id,
    required this.type,
    required this.amount,
    required this.reason,
    required this.createdAt,
  });

  factory CashLog.fromJson(Map<String, dynamic> json) {
    return CashLog(
      id: json['id'].toString(),
      type: json['type'] as String,
      amount: (json['amount'] as num).toDouble(),
      reason: json['reason'] as String? ?? 'بدون سبب',
      createdAt: json['created_at'] as String,
    );
  }
}
