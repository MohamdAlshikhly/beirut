import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/data_providers.dart';
import '../models/models.dart';
import '../utils/glass_container.dart';
import '../utils/app_colors.dart';
import '../widgets/skeleton_container.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String query) {
    state = query;
  }
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(() {
  return SearchQueryNotifier();
});

class ProductGrid extends ConsumerStatefulWidget {
  const ProductGrid({super.key});

  @override
  ConsumerState<ProductGrid> createState() => _ProductGridState();
}

class _ProductGridState extends ConsumerState<ProductGrid> {
  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final pinnedIds = ref.watch(pinnedCategoriesProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final searchQuery = ref.watch(searchQueryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                flex: 1,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'ابحث عن منتج بالاسم أو الباركود...',
                    prefixIcon: const Icon(
                      PhosphorIconsRegular.magnifyingGlass,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.black12
                        : Colors.white54,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (val) =>
                      ref.read(searchQueryProvider.notifier).set(val),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: categoriesAsync.when(
                  skipLoadingOnReload: true,
                  skipLoadingOnRefresh: true,
                  data: (categories) {
                    final pinned = categories
                        .where((c) => pinnedIds.contains(c.id))
                        .toList();
                    final isHiddenSelected =
                        selectedCategory != null &&
                        !pinned.any((c) => c.id == selectedCategory);

                    return Row(
                      children: [
                        IconButton(
                          onPressed: () => _showManageCategoriesDialog(
                            context,
                            ref,
                            categories,
                          ),
                          icon: const Icon(
                            Icons.tune,
                            color: AppColors.primary,
                          ),
                          tooltip: 'تخصيص الأقسام',
                        ),
                        _CategoryChip(
                          title: 'الكل',
                          isSelected: selectedCategory == null,
                          onTap: () => ref
                              .read(selectedCategoryProvider.notifier)
                              .set(null),
                        ),
                        const SizedBox(width: 8),
                        ...pinned.map(
                          (cat) => Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: _CategoryChip(
                              title: cat.name,
                              isSelected: selectedCategory == cat.id,
                              onTap: () => ref
                                  .read(selectedCategoryProvider.notifier)
                                  .set(cat.id),
                            ),
                          ),
                        ),
                        if (isHiddenSelected)
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: _CategoryChip(
                              title: categories
                                  .firstWhere((c) => c.id == selectedCategory)
                                  .name,
                              isSelected: true,
                              onTap: () {},
                            ),
                          ),
                      ],
                    );
                  },
                  loading: () => Row(
                    children: List.generate(
                      3,
                      (index) => const Padding(
                        padding: EdgeInsets.only(right: 8.0),
                        child: SkeletonContainer(
                          width: 60,
                          height: 32,
                          borderRadius: BorderRadius.all(Radius.circular(20)),
                        ),
                      ),
                    ),
                  ),
                  error: (err, stack) => const Text('خطأ في تحميل الأقسام'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: productsAsync.when(
            skipLoadingOnReload: true,
            skipLoadingOnRefresh: true,
            data: (products) {
              final filteredProducts = products.where((p) {
                final matchCat = selectedCategory == null
                    ? true
                    : p.categoryId == selectedCategory;
                final matchSearch =
                    p.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
                    (p.barcode != null && p.barcode!.contains(searchQuery));
                return matchCat && matchSearch;
              }).toList();

              if (filteredProducts.isEmpty) {
                return const Center(
                  child: Text(
                    'لم يتم العثور على منتجات.',
                    style: TextStyle(fontSize: 18),
                  ),
                );
              }

              return GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.8,
                ),
                itemCount: filteredProducts.length,
                itemBuilder: (context, index) {
                  final product = filteredProducts[index];
                  return _ProductCard(product: product);
                },
              );
            },
            loading: () => GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.8,
              ),
              itemCount: 12,
              itemBuilder: (context, index) {
                return GlassContainer(
                  borderRadius: BorderRadius.circular(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Expanded(
                        flex: 2,
                        child: SkeletonContainer(
                          width: double.infinity,
                          height: double.infinity,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SkeletonContainer(width: 120, height: 16),
                              const SizedBox(height: 10),
                              const SkeletonContainer(width: 80, height: 18),
                              const SizedBox(height: 20),
                              SkeletonContainer(
                                width: double.infinity,
                                height: 32,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            error: (err, stack) =>
                Center(child: Text('خطأ في تحميل المنتجات: $err')),
          ),
        ),
      ],
    );
  }

  void _showManageCategoriesDialog(
    BuildContext context,
    WidgetRef ref,
    List<Category> categories,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final pinnedIds = ref.watch(pinnedCategoriesProvider);
            return AlertDialog(
              title: const Text('تخصيص الأقسام المفضلة'),
              content: SizedBox(
                width: 400,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final cat = categories[index];
                    final isPinned = pinnedIds.contains(cat.id);
                    return CheckboxListTile(
                      title: Text(cat.name),
                      value: isPinned,
                      onChanged: (_) {
                        ref
                            .read(pinnedCategoriesProvider.notifier)
                            .togglePin(cat.id);
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إغلاق'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary
                : (isDark
                      ? Colors.white10
                      : Colors.black.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? AppColors.primary : Colors.transparent,
            ),
          ),
          child: Text(
            title,
            style: TextStyle(
              color: isSelected
                  ? AppColors.secondary
                  : theme.textTheme.bodyLarge?.color,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends ConsumerWidget {
  final Product product;

  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencyFormatter = NumberFormat('#,##0', 'en_US');

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async {
          final isRecharge =
              product.name.contains('اسياسيل') ||
              product.name.contains('زين') ||
              product.name.contains('كورك') ||
              product.name.contains('رصيد') ||
              product.name.contains('كارت');

          if (isRecharge) {
            final amount = await _showAmountDialog(context);
            if (amount != null && amount > 0) {
              ref
                  .read(cartProvider.notifier)
                  .addProduct(product, priceOverride: amount);
            }
          } else {
            ref.read(cartProvider.notifier).addProduct(product);
          }
        },
        child: GlassContainer(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 2,
                child: product.imageUrl != null
                    ? ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                        child: Image.network(
                          product.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => Container(
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(20),
                              ),
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.primary.withValues(alpha: 0.8),
                                  AppColors.primary.withValues(alpha: 0.5),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                product.name.substring(0, 1).toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 48,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.secondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primary.withValues(alpha: 0.8),
                              AppColors.primary.withValues(alpha: 0.5),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            product.name.substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: AppColors.secondary,
                            ),
                          ),
                        ),
                      ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 1,

                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${currencyFormatter.format(product.price)} د.ع',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: (product.quantity > 5)
                              ? AppColors.primary.withValues(alpha: 0.2)
                              : Colors.red.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            'المخزون: ${product.quantity}',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<double?> _showAmountDialog(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('ادخل مبلغ الكرت لـ ${product.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(
            suffixText: 'د.ع',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (val) {
            Navigator.pop(ctx, double.tryParse(val));
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(controller.text)),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text(
              'إضافة',
              style: TextStyle(color: AppColors.secondary),
            ),
          ),
        ],
      ),
    );
  }
}
