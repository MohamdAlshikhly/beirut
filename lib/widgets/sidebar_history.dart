import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../providers/data_providers.dart';
import '../utils/app_colors.dart';
import '../services/local_database.dart';
import '../services/sync_service.dart';
import '../widgets/skeleton_container.dart';

class SidebarHistory extends ConsumerStatefulWidget {
  const SidebarHistory({super.key});

  @override
  ConsumerState<SidebarHistory> createState() => _SidebarHistoryState();
}

class _SidebarHistoryState extends ConsumerState<SidebarHistory> {
  List<Map<String, dynamic>> _sales = [];
  List<Map<String, dynamic>> _filteredSales = [];
  bool _isLoading = true;
  final _currencyFormatter = NumberFormat('#,##0', 'en_US');

  @override
  void initState() {
    super.initState();
    _fetchSales();
  }

  Future<void> _fetchSales() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final user = ref.read(authProvider);
      final db = await LocalDatabase.instance.database;

      String query = '''
        SELECT sales.*, users.name as user_name
        FROM sales
        LEFT JOIN users ON sales.user_id = users.id
      ''';

      List<dynamic> args = [];
      if (user != null && user.role != 'admin') {
        query += ' WHERE sales.user_id = ?';
        args.add(user.id);
      }

      query += ' ORDER BY created_at DESC LIMIT 50';

      final res = await db.rawQuery(query, args);

      if (mounted) {
        setState(() {
          _sales = res.map((row) {
            final map = Map<String, dynamic>.from(row);
            map['users'] = {'name': row['user_name']};
            return map;
          }).toList();
          _filteredSales = _sales;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching sidebar sales: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filter(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredSales = _sales;
      } else {
        _filteredSales = _sales
            .where((s) => s['id'].toString().contains(query))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(PhosphorIconsRegular.caretRight),
                onPressed: () => ref
                    .read(sidebarViewProvider.notifier)
                    .set(SidebarView.cart),
              ),
              const Text(
                'سجل الفواتير',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(PhosphorIconsBold.arrowsClockwise, size: 20),
                onPressed: () async {
                  await ref.read(syncServiceProvider).syncDown();
                  _fetchSales();
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'بحث برقم الفاتورة...',
              prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass),
              filled: true,
              fillColor: isDark ? Colors.white10 : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
            onChanged: _filter,
            keyboardType: TextInputType.number,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _isLoading
              ? ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: 5,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => const SkeletonContainer(
                    height: 80,
                    width: double.infinity,
                  ),
                )
              : _filteredSales.isEmpty
              ? const Center(child: Text('لا توجد فواتير'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filteredSales.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final sale = _filteredSales[index];
                    final saleId = sale['id'];
                    final total = (sale['total_price'] as num).toDouble();
                    final date = DateTime.parse(sale['created_at']).toLocal();
                    final formattedDate = DateFormat(
                      'MM-dd HH:mm',
                    ).format(date);
                    final pyType = sale['payment_type'] == 'cash'
                        ? 'نقدي'
                        : 'بطاقة';

                    return InkWell(
                      onTap: () {
                        ref
                            .read(selectedHistorySaleProvider.notifier)
                            .set(sale);
                        ref
                            .read(sidebarViewProvider.notifier)
                            .set(SidebarView.details);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'فاتورة #$saleId',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  formattedDate,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${_currencyFormatter.format(total)} د.ع',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                                Text(
                                  pyType,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.blueGrey,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              PhosphorIconsRegular.caretLeft,
                              size: 16,
                              color: Colors.grey,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
