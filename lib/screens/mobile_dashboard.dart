import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../providers/data_providers.dart';
import '../providers/theme_provider.dart';
import '../utils/app_colors.dart';
import '../utils/glass_container.dart';
import '../widgets/admin_dialogs.dart';
import '../screens/sales_history_screen.dart';
import '../screens/camera_scanner_screen.dart';
import '../screens/add_product_screen.dart';
import '../screens/edit_product_screen.dart';
import '../screens/qr_scanner_approval_screen.dart';
import '../models/models.dart';
import '../screens/sessions_monitoring_screen.dart';
import '../screens/retire_money_screen.dart';
import '../screens/add_user_screen.dart';
import '../widgets/add_stock_dialog.dart';
import '../screens/cards_management_screen.dart';
import '../widgets/skeleton_container.dart';
import '../services/sync_service.dart';
import '../widgets/searchable_dropdown.dart';
import '../screens/cash_drawer_history_screen.dart';

class MobileDashboard extends ConsumerStatefulWidget {
  const MobileDashboard({super.key});

  @override
  ConsumerState<MobileDashboard> createState() => _MobileDashboardState();
}

class _MobileDashboardState extends ConsumerState<MobileDashboard> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      const _MainDashboardTab(),
      const _InventoryTab(),
      const _UserSettingsTab(),
    ];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: AppBar(
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        backgroundColor: (isDark ? const Color(0xFF0F172A) : Colors.white)
            .withValues(alpha: 0.7),
        elevation: 0,
        title: Text(
          'دكان بيروت',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
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
        child: SafeArea(child: pages[_currentIndex]),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            selectedItemColor: AppColors.primary,
            unselectedItemColor: Colors.grey,
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            elevation: 0,
            onTap: (index) => setState(() => _currentIndex = index),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(PhosphorIconsRegular.chartBar),
                activeIcon: Icon(PhosphorIconsFill.chartBar),
                label: 'الرئيسية',
              ),
              BottomNavigationBarItem(
                icon: Icon(PhosphorIconsRegular.package),
                activeIcon: Icon(PhosphorIconsFill.package),
                label: 'المخزن',
              ),
              BottomNavigationBarItem(
                icon: Icon(PhosphorIconsRegular.userGear),
                activeIcon: Icon(PhosphorIconsFill.userGear),
                label: 'الإعدادات',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MainDashboardTab extends ConsumerWidget {
  const _MainDashboardTab();

  Widget _buildStatCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color, {
    bool isLoading = false,
  }) {
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const Spacer(),
              Icon(
                PhosphorIconsRegular.trendUp,
                color: Colors.green.withValues(alpha: 0.6),
                size: 16,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          isLoading
              ? const SkeletonContainer(width: 80, height: 24)
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(balanceProvider);
    final todaySalesAsync = ref.watch(todaySalesProvider);
    final todaySalesCountAsync = ref.watch(todaySalesCountProvider);
    final productsAsync = ref.watch(productsProvider);
    final currencyFormatter = NumberFormat('#,##0', 'en_US');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(syncServiceProvider).syncDown();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'نظرة عامة',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: balanceAsync.when(
                  data: (val) => _buildStatCard(
                    context,
                    'درج النقدية',
                    '${currencyFormatter.format(val)} د.ع',
                    PhosphorIconsFill.cashRegister,
                    Colors.green,
                  ),
                  loading: () => _buildStatCard(
                    context,
                    'درج النقدية',
                    '',
                    PhosphorIconsFill.cashRegister,
                    Colors.green,
                    isLoading: true,
                  ),
                  error: (e, st) => _buildStatCard(
                    context,
                    'درج النقدية',
                    'خطأ',
                    PhosphorIconsFill.cashRegister,
                    Colors.red,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: todaySalesAsync.when(
                  data: (val) => _buildStatCard(
                    context,
                    'مبيعات اليوم',
                    '${currencyFormatter.format(val)} د.ع',
                    PhosphorIconsFill.chartLineUp,
                    Colors.blue,
                  ),
                  loading: () => _buildStatCard(
                    context,
                    'مبيعات اليوم',
                    '',
                    PhosphorIconsFill.chartLineUp,
                    Colors.blue,
                    isLoading: true,
                  ),
                  error: (e, st) => _buildStatCard(
                    context,
                    'مبيعات اليوم',
                    'خطأ',
                    PhosphorIconsFill.chartLineUp,
                    Colors.red,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: productsAsync.when(
                  data: (list) => _buildStatCard(
                    context,
                    'المنتجات المسجلة',
                    '${list.length}',
                    PhosphorIconsFill.package,
                    Colors.orange,
                  ),
                  loading: () => _buildStatCard(
                    context,
                    'المنتجات المسجلة',
                    '',
                    PhosphorIconsFill.package,
                    Colors.orange,
                    isLoading: true,
                  ),
                  error: (e, st) => _buildStatCard(
                    context,
                    'المنتجات المسجلة',
                    'خطأ',
                    PhosphorIconsFill.package,
                    Colors.red,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: todaySalesCountAsync.when(
                  data: (val) => _buildStatCard(
                    context,
                    'عدد فواتير اليوم',
                    '$val',
                    PhosphorIconsFill.bellRinging,
                    Colors.purple,
                  ),
                  loading: () => _buildStatCard(
                    context,
                    'عدد فواتير اليوم',
                    '',
                    PhosphorIconsFill.bellRinging,
                    Colors.purple,
                    isLoading: true,
                  ),
                  error: (e, st) => _buildStatCard(
                    context,
                    'عدد فواتير اليوم',
                    'خطأ',
                    PhosphorIconsFill.bellRinging,
                    Colors.red,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Text(
            'الفواتير',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SalesHistoryScreen()),
              );
            },
            borderRadius: BorderRadius.circular(20),
            child: GlassContainer(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      PhosphorIconsFill.receipt,
                      color: AppColors.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'البحث وتعديل الفواتير',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'إرجاع مواد أو تعديل مبيعات سابقة',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    PhosphorIconsRegular.caretLeft,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => AlertDialog(
                  title: const Text('فتح الدرج عن بعد'),
                  content: const Text(
                    'هل أنت متأكد من رغبتك في فتح درج النقود في الكومبيوتر؟',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('إلغاء'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('فتح'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await ref.read(cashDrawerProvider).logAndOpen(
                  type: 'open',
                  reason: 'remote_open',
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم إرسال أمر الفتح بنجاح!')),
                  );
                }
              }
            },
            borderRadius: BorderRadius.circular(20),
            child: GlassContainer(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      PhosphorIconsFill.archive,
                      color: Colors.orange,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'فتح درج النقود (عن بعد)',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'إرسال أمر فتح للكومبيوتر المتصل',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    PhosphorIconsRegular.caretLeft,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryTab extends ConsumerStatefulWidget {
  const _InventoryTab();
  @override
  ConsumerState<_InventoryTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends ConsumerState<_InventoryTab> {
  String _searchQuery = '';

  Future<void> _startAddProductFlow() async {
    final barcode = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const CameraScannerScreen(title: 'مسح باركود المنتج الجديد'),
      ),
    );
    // Proceed even if barcode is null (user cancelled scan)
    if (mounted) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AddProductScreen(initialBarcode: barcode),
        ),
      );
    }
  }

  Future<void> _startAddStockFlow() async {
    final barcode = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const CameraScannerScreen(title: 'مسح باركود منتج للتزويد'),
      ),
    );

    if (barcode != null && mounted) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      final productList = ref.read(productsProvider).value ?? [];
      try {
        final product = productList.firstWhere(
          (p) => p.barcode == barcode || p.id.toString() == barcode,
        );
        showDialog(
          context: context,
          builder: (_) => AddStockQuantityDialog(product: product),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'المنتج الممسوح غير موجود في المستودع! قم بإضافته كمنتج جديد أولاً.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _editCategory(Category category) async {
    final nameController = TextEditingController(text: category.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل اسم القسم'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'اسم القسم الجديد'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != category.name) {
      try {
        final supabase = ref.read(supabaseProvider);
        await supabase
            .from('categories')
            .update({'name': newName})
            .eq('id', category.id);
        ref.invalidate(categoriesProvider);
      } catch (e) {
        debugPrint('Error editing category: $e');
      }
    }
  }

  void _deleteCategory(Category category) async {
    final categories = ref.read(categoriesProvider).value ?? [];
    final otherCategories = categories
        .where((c) => c.id != category.id)
        .toList();

    int? targetCategoryId;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('حذف القسم'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'يجب تحويل كافة منتجات هذا القسم إلى قسم آخر قبل الحذف.',
              ),
              const SizedBox(height: 16),
              SearchableDropdown<Category>(
                items: otherCategories,
                value: targetCategoryId != null
                    ? otherCategories.firstWhere(
                        (c) => c.id == targetCategoryId,
                      )
                    : null,
                label: 'اختر القسم البديل',
                hint: 'اختر قسم',
                itemTitle: (c) => c.name,
                onChanged: (v) =>
                    setDialogState(() => targetCategoryId = v?.id),
                searchMatcher: (c, q) =>
                    c.name.toLowerCase().contains(q.toLowerCase()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: targetCategoryId == null
                  ? null
                  : () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('حذف وتحويل المنتجات'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true && targetCategoryId != null) {
      try {
        final supabase = ref.read(supabaseProvider);
        // 1. Move products
        await supabase
            .from('products')
            .update({'category_id': targetCategoryId})
            .eq('category_id', category.id);
        // 2. Delete category
        await supabase.from('categories').delete().eq('id', category.id);

        ref.invalidate(productsProvider);
        ref.invalidate(categoriesProvider);
      } catch (e) {
        debugPrint('Error deleting category: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.secondary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(PhosphorIconsBold.plusCircle),
                  label: const Text(
                    'إضافة منتج',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: _startAddProductFlow,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(PhosphorIconsBold.folderPlus),
                  label: const Text(
                    'إضافة قسم',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const AddCategoryDialog(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(PhosphorIconsBold.camera),
            label: const Text(
              'تزويد المخزن عبر مسح الباركود',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            onPressed: _startAddStockFlow,
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.credit_card),
            label: const Text(
              'إدارة كروت التعبئة',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CardsManagementScreen(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            decoration: InputDecoration(
              hintText: 'ابحث عن منتج (الاسم، الباركود)...',
              prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass),
              suffixIcon: IconButton(
                icon: const Icon(
                  PhosphorIconsRegular.camera,
                  color: AppColors.primary,
                ),
                onPressed: () async {
                  final barcode = await Navigator.push<String?>(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const CameraScannerScreen(title: 'مسح باركود للبحث'),
                    ),
                  );
                  if (barcode != null) {
                    setState(() => _searchQuery = barcode);
                  }
                },
              ),
              filled: true,
              fillColor: isDark
                  ? Colors.white10
                  : Colors.black.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: productsAsync.when(
              data: (products) {
                final categories = ref.watch(categoriesProvider).value ?? [];
                final filteredProducts = products.where((p) {
                  final q = _searchQuery.toLowerCase();
                  return p.name.toLowerCase().contains(q) ||
                      (p.barcode?.contains(q) ?? false);
                }).toList();

                if (filteredProducts.isEmpty) {
                  return const Center(child: Text('لم يتم العثور على منتجات'));
                }

                // Group products by category
                final grouped = <int?, List<Product>>{};
                for (var p in filteredProducts) {
                  grouped.putIfAbsent(p.categoryId, () => []).add(p);
                }

                final sortedCategoryIds = grouped.keys.toList()
                  ..sort((a, b) {
                    if (a == null) return 1;
                    if (b == null) return -1;
                    final catA = categories.firstWhere(
                      (c) => c.id == a,
                      orElse: () => Category(id: -1, name: ''),
                    );
                    final catB = categories.firstWhere(
                      (c) => c.id == b,
                      orElse: () => Category(id: -1, name: ''),
                    );
                    return catA.name.compareTo(catB.name);
                  });

                return RefreshIndicator(
                  onRefresh: () async {
                    await ref.read(syncServiceProvider).syncDown();
                  },
                  child: ListView.builder(
                    itemCount: sortedCategoryIds.length,
                    itemBuilder: (context, catIndex) {
                      final catId = sortedCategoryIds[catIndex];
                      final catProducts = grouped[catId]!;
                      final category = categories.firstWhere(
                        (c) => c.id == catId,
                        orElse: () => Category(id: -1, name: 'بدون قسم'),
                      );

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    category.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                if (category.id != -1) ...[
                                  const Spacer(),
                                  IconButton(
                                    icon: const Icon(
                                      PhosphorIconsRegular.pencilSimple,
                                      size: 18,
                                    ),
                                    onPressed: () => _editCategory(category),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      PhosphorIconsRegular.trash,
                                      size: 18,
                                      color: Colors.red,
                                    ),
                                    onPressed: () => _deleteCategory(category),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          ...catProducts.map(
                            (product) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: GlassContainer(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: product.quantity > 5
                                            ? Colors.green.withValues(
                                                alpha: 0.1,
                                              )
                                            : Colors.red.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: product.imageUrl != null
                                          ? ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              child: Image.network(
                                                product.imageUrl!,
                                                fit: BoxFit.cover,
                                                errorBuilder: (c, e, s) => Icon(
                                                  PhosphorIconsRegular.package,
                                                  color: product.quantity > 5
                                                      ? Colors.green
                                                      : Colors.red,
                                                  size: 20,
                                                ),
                                              ),
                                            )
                                          : Icon(
                                              PhosphorIconsRegular.package,
                                              color: product.quantity > 5
                                                  ? Colors.green
                                                  : Colors.red,
                                              size: 20,
                                            ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            product.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                          ),
                                          Text(
                                            '${NumberFormat('#,##0').format(product.price)} د.ع',
                                            style: TextStyle(
                                              color: Colors.green.shade700,
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          'الكمية: ${product.quantity}',
                                          style: TextStyle(
                                            color: product.quantity > 5
                                                ? Colors.green
                                                : Colors.red,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        InkWell(
                                          onTap: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => EditProductScreen(
                                                product: product,
                                              ),
                                            ),
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.primary,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Text(
                                              'تعديل',
                                              style: TextStyle(
                                                color: AppColors.secondary,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('حدث خطأ: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserSettingsTab extends ConsumerWidget {
  const _UserSettingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(authProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (user != null)
          GlassContainer(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primary,
                  radius: 30,
                  child: Text(
                    user.name[0],
                    style: const TextStyle(
                      color: AppColors.secondary,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      user.role == 'admin' ? 'مدير النظام' : 'كاشير مبيعات',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        const Text(
          'الصلاحيات والإدارة',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 12),
        GlassContainer(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(
                  PhosphorIconsRegular.money,
                  color: Colors.red,
                ),
                title: const Text(
                  'سحب وصرف أموال',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: const Icon(PhosphorIconsRegular.caretLeft),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RetireMoneyScreen()),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  PhosphorIconsRegular.userPlus,
                  color: Colors.blue,
                ),
                title: const Text(
                  'إضافة مستخدم أو كاشير',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: const Icon(PhosphorIconsRegular.caretLeft),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddUserScreen()),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  PhosphorIconsRegular.qrCode,
                  color: Colors.green,
                ),
                title: const Text(
                  'تفعيل جلسة كمبيوتر',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: const Icon(PhosphorIconsRegular.caretLeft),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const QrScannerApprovalScreen(),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  PhosphorIconsRegular.desktop,
                  color: Colors.orange,
                ),
                title: const Text(
                  'مراقبة جلسات الكاشير',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: const Icon(PhosphorIconsRegular.caretLeft),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SessionsMonitoringScreen(),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  PhosphorIconsRegular.archive,
                  color: Colors.teal,
                ),
                title: const Text(
                  'سجل حركات جرارة الأموال',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: const Icon(PhosphorIconsRegular.caretLeft),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CashDrawerHistoryScreen(),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'إعدادات التطبيق',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 12),
        GlassContainer(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                  isDark ? PhosphorIconsFill.sun : PhosphorIconsFill.moon,
                  color: Colors.orange,
                ),
                title: const Text(
                  'الوضع الليلي / النهاري',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: Switch(
                  value: isDark,
                  activeColor: AppColors.primary,
                  onChanged: (val) =>
                      ref.read(themeModeProvider.notifier).toggle(),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  PhosphorIconsRegular.database,
                  color: Colors.purple,
                ),
                title: const Text(
                  'نسخ احتياطي للبيانات',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: const Icon(PhosphorIconsRegular.caretLeft),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'يتم حفظ البيانات تلقائياً سحابياً في Supabase ✨',
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 48),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
            foregroundColor: Colors.redAccent,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Colors.redAccent, width: 2),
            ),
          ),
          icon: const Icon(PhosphorIconsBold.signOut),
          label: const Text(
            'تسجيل خروج',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          onPressed: () {
            ref.read(authProvider.notifier).logout();
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
