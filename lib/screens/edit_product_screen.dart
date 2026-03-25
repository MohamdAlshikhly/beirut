import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../models/models.dart';
import '../providers/data_providers.dart';
import '../utils/app_colors.dart';
import '../utils/glass_container.dart';
import 'package:uuid/uuid.dart';
import '../widgets/searchable_dropdown.dart';

class EditProductScreen extends ConsumerStatefulWidget {
  final Product product;
  const EditProductScreen({super.key, required this.product});

  @override
  ConsumerState<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends ConsumerState<EditProductScreen> {
  late TextEditingController _nameController;
  late TextEditingController _barcodeController;
  late TextEditingController _priceController;
  late TextEditingController _costPriceController;
  late TextEditingController _qtyController;
  int? _selectedCategoryId;
  int? _selectedBaseUnitId;
  late TextEditingController _conversionController;
  bool _isLoading = false;
  XFile? _pickedImage;
  String? _currentImageUrl;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product.name);
    _barcodeController = TextEditingController(text: widget.product.barcode);
    _priceController = TextEditingController(
      text: widget.product.price.toString(),
    );
    _costPriceController = TextEditingController(
      text: widget.product.costPrice?.toString() ?? '',
    );
    _qtyController = TextEditingController(
      text: widget.product.quantity.toString(),
    );
    _selectedCategoryId = widget.product.categoryId;
    _selectedBaseUnitId = widget.product.baseUnitId;
    _conversionController = TextEditingController(
      text: widget.product.baseUnitConversion.toString(),
    );
    _currentImageUrl = widget.product.imageUrl;
  }

  Future<void> _pickImage() async {
    final image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _pickedImage = image);
    }
  }

  Future<String?> _uploadImage() async {
    if (_pickedImage == null) return _currentImageUrl;
    try {
      final supabase = ref.read(supabaseProvider);
      final fileExtension = _pickedImage!.path.split('.').last;
      final fileName = '${const Uuid().v4()}.$fileExtension';
      final fileBytes = await _pickedImage!.readAsBytes();

      await supabase.storage.from('products').uploadBinary(fileName, fileBytes);

      final imageUrl = supabase.storage.from('products').getPublicUrl(fileName);
      return imageUrl;
    } catch (e) {
      debugPrint('Upload error: $e');
      return _currentImageUrl;
    }
  }

  void _save() async {
    if (_nameController.text.trim().isEmpty || _priceController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إكمال البيانات الأساسية')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final imageUrl = await _uploadImage();
      final supabase = ref.read(supabaseProvider);
      final newQty = double.parse(_qtyController.text);
      final oldQty = widget.product.quantity;
      final diff = newQty - oldQty;

      await supabase
          .from('products')
          .update({
            'name': _nameController.text.trim(),
            'barcode': _barcodeController.text.trim().isEmpty
                ? null
                : _barcodeController.text.trim(),
            'price': double.parse(_priceController.text),
            'cost_price': _costPriceController.text.isNotEmpty
                ? double.parse(_costPriceController.text)
                : null,
            // Note: We don't update quantity here directly to let linkage handle it if diff != 0
            // but we update other linkage fields
            'category_id': _selectedCategoryId,
            'image_url': imageUrl,
            'base_unit_id': _selectedBaseUnitId,
            'base_unit_conversion':
                double.tryParse(_conversionController.text) ?? 1.0,
          })
          .eq('id', widget.product.id);

      if (diff != 0) {
        await ref
            .read(checkoutProvider)
            .updateStockWithLinkage(
              productId: widget.product.id,
              change: diff,
              reason: 'تعديل مخزون يدوي (مرتبط)',
              isOnline: true,
            );
      }

      ref.invalidate(productsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تحديث المنتج بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المنتج'),
        content: const Text(
          'هل أنت متأكد من حذف هذا المنتج؟ لا يمكن التراجع عن هذه العملية.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        final supabase = ref.read(supabaseProvider);
        await supabase.from('products').delete().eq('id', widget.product.id);
        ref.invalidate(productsProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم حذف المنتج'),
              backgroundColor: Colors.orange,
            ),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('فشل الحذف: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('تعديل المنتج'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(PhosphorIconsRegular.trash, color: Colors.red),
            onPressed: _isLoading ? null : _delete,
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassContainer(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Center(
                      child: GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white10
                                : Colors.black.withAlpha(20),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.primary,
                              width: 2,
                            ),
                          ),
                          child: _pickedImage != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.file(
                                    File(_pickedImage!.path),
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : _currentImageUrl != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.network(
                                    _currentImageUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (c, e, s) =>
                                        const Icon(Icons.broken_image),
                                  ),
                                )
                              : const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_a_photo,
                                      size: 40,
                                      color: AppColors.primary,
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'تغيير الصورة',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                    if (_currentImageUrl != null || _pickedImage != null)
                      TextButton(
                        onPressed: () => setState(() {
                          _pickedImage = null;
                          _currentImageUrl = null;
                        }),
                        child: const Text(
                          'إزالة الصورة',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'اسم المنتج',
                        prefixIcon: const Icon(PhosphorIconsRegular.package),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _barcodeController,
                      decoration: InputDecoration(
                        labelText: 'الباركود',
                        prefixIcon: const Icon(PhosphorIconsRegular.barcode),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _priceController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'سعر البيع',
                              prefixIcon: const Icon(
                                PhosphorIconsRegular.money,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _costPriceController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'سعر التكلفة',
                              prefixIcon: const Icon(
                                PhosphorIconsRegular.coins,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _qtyController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'الكمية المتوفرة حالياً',
                        prefixIcon: const Icon(PhosphorIconsRegular.stack),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    categoriesAsync.when(
                      data: (categories) => SearchableDropdown<Category>(
                        items: categories,
                        value: _selectedCategoryId != null
                            ? categories.firstWhere(
                                (c) => c.id == _selectedCategoryId,
                              )
                            : null,
                        label: 'القسم',
                        hint: 'اختر القسم',
                        itemTitle: (c) => c.name,
                        onChanged: (v) =>
                            setState(() => _selectedCategoryId = v?.id),
                        searchMatcher: (c, q) =>
                            c.name.toLowerCase().contains(q.toLowerCase()),
                      ),
                      loading: () => const LinearProgressIndicator(),
                      error: (e, st) => const Text('خطأ في تحميل الأقسام'),
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    const Text(
                      'ربط الوحدات (اختياري):',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ref
                        .watch(productsProvider)
                        .when(
                          data: (products) {
                            return SearchableDropdown<Product>(
                              items: products
                                  .where((p) => p.id != widget.product.id)
                                  .toList(),
                              value: _selectedBaseUnitId != null
                                  ? products.firstWhere(
                                      (p) => p.id == _selectedBaseUnitId,
                                    )
                                  : null,
                              label: 'المنتج الأساسي (الوحدة الأصغر)',
                              hint: 'لا يوجد (منتج أساسي مفرد)',
                              itemTitle: (p) => p.name,
                              onChanged: (v) =>
                                  setState(() => _selectedBaseUnitId = v?.id),
                              searchMatcher: (p, q) => p.name
                                  .toLowerCase()
                                  .contains(q.toLowerCase()),
                            );
                          },
                          loading: () => const LinearProgressIndicator(),
                          error: (e, st) => const Text('خطأ في تحميل المنتجات'),
                        ),
                    if (_selectedBaseUnitId != null) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _conversionController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'معامل التحويل',
                          hintText: 'مثلاً: كارتون فيه 24 علبة تضع 24',
                          prefixIcon: const Icon(PhosphorIconsRegular.equals),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.secondary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 5,
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(
                        color: AppColors.secondary,
                      )
                    : const Text(
                        'حفظ التعديلات',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
