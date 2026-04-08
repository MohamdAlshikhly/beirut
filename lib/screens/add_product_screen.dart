import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/data_providers.dart';
import '../utils/app_colors.dart';
import '../services/local_database.dart';
import 'package:uuid/uuid.dart';
import '../widgets/searchable_dropdown.dart';
import '../models/models.dart';

class AddProductScreen extends ConsumerStatefulWidget {
  final String? initialBarcode;
  const AddProductScreen({super.key, this.initialBarcode});

  @override
  ConsumerState<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends ConsumerState<AddProductScreen> {
  final _nameController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _priceController = TextEditingController();
  final _costPriceController = TextEditingController();
  final _qtyController = TextEditingController();
  int? _selectedCategoryId;
  int? _selectedBaseUnitId;
  final _conversionController = TextEditingController(text: '1.0');
  bool _isLoading = false;
  bool _isCard = false;
  XFile? _pickedImage;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    if (widget.initialBarcode != null) {
      _barcodeController.text = widget.initialBarcode!;
    }
  }

  Future<void> _pickImage() async {
    final image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _pickedImage = image);
    }
  }

  Future<String?> _uploadImage() async {
    if (_pickedImage == null) return null;
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
      return null;
    }
  }

  void _save() async {
    final name = _nameController.text.trim();
    final price = double.tryParse(_priceController.text);
    final costPrice = _costPriceController.text.isNotEmpty
        ? double.tryParse(_costPriceController.text)
        : null;
    final qty = _qtyController.text.isNotEmpty
        ? double.tryParse(_qtyController.text)
        : 0.0;

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال اسم المنتج')),
      );
      return;
    }
    if (price == null || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال سعر صحيح')),
      );
      return;
    }
    if (costPrice == null && _costPriceController.text.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('سعر التكلفة غير صحيح')),
      );
      return;
    }
    if (qty == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الكمية غير صحيحة')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      String? imageUrl;
      imageUrl = await _uploadImage();

      final supabase = ref.read(supabaseProvider);
      final db = await LocalDatabase.instance.database;

      final productData = {
        'name': name,
        'barcode': _barcodeController.text.trim().isEmpty
            ? null
            : _barcodeController.text.trim(),
        'price': price,
        'cost_price': costPrice,
        'quantity': qty,
        'category_id': _selectedCategoryId,
        'image_url': imageUrl,
        'base_unit_id': _selectedBaseUnitId,
        'base_unit_conversion':
            double.tryParse(_conversionController.text) ?? 1.0,
        'is_card': _isCard ? 1 : 0,
      };

      // 1. Try Online First
      try {
        final initialQty = _qtyController.text.isNotEmpty
            ? double.parse(_qtyController.text)
            : 0.0;

        // Insert at 0 quantity first, then move stock via linkage
        final dataAtZero = Map<String, dynamic>.from(productData);
        dataAtZero['quantity'] = 0.0;

        final onlineRes = await supabase
            .from('products')
            .insert(dataAtZero)
            .select()
            .single();

        final newId = onlineRes['id'];

        // Mirror locally at 0
        await db.insert('products', {
          ...dataAtZero,
          'id': newId,
          'is_synced': 1,
        });

        // 2. Update Stock via Linkage (this handles base units automatically)
        if (initialQty != 0) {
          await ref
              .read(checkoutProvider)
              .updateStockWithLinkage(
                productId: newId,
                change: initialQty,
                reason: 'الرصيد الابتدائي (مرتبط)',
                isOnline: true,
              );
        }

        ref.invalidate(productsProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تمت إضافة المنتج بنجاح وتحديث الوحدات المرتبطة!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
        return;
      } catch (onlineError) {
        debugPrint('Online product save failed: $onlineError');
        // FALLBACK TO LOCAL (Simple insert, linkage will sync later or user handles manually)
        await db.insert('products', {...productData, 'is_synced': 0});
        ref.invalidate(productsProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم حفظ المنتج أوفلاين (سيتم الرفـع لاحقاً)'),
              backgroundColor: Colors.orange,
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: Colors.red),
        );
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل المنتج الجديد'),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.secondary,
      ),
      body: Container(
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                : [const Color(0xFFF1F5F9), const Color(0xFFE2E8F0)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? Colors.black45 : Colors.white.withAlpha(220),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white24 : Colors.black12,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'بيانات المنتج الجديد:',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
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
                                    'صورة المنتج',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _barcodeController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'الباركود',
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'اسم المنتج المُراد إضافته',
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    value: _isCard,
                    onChanged: (v) => setState(() => _isCard = v),
                    title: const Text('كرت تعبئة'),
                    subtitle: const Text(
                      'يتيح إضافة كروت بقيم مختلفة من إدارة الكروت',
                      style: TextStyle(fontSize: 12),
                    ),
                    secondary: const Icon(Icons.credit_card, color: AppColors.primary),
                    activeThumbColor: AppColors.primary,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _priceController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'السعر',
                            filled: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _costPriceController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'سعر التكلفة',
                            filled: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _qtyController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: 'الكمية الابتدائية في المخزن',
                            filled: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: categoriesAsync.when(
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
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (e, st) =>
                              const Text('Error loading categories'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text(
                    'ربط الوحدات (اختياري):',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'مثال: إذا كان هذا المنتج عبارة عن صندوق، اختر "العلبة" كوحدة أساسية وضع معامل التحويل 24.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  ref
                      .watch(productsProvider)
                      .when(
                        data: (products) {
                          // Filter out potential circular references (though simple one-level is fine)
                          return SearchableDropdown<Product>(
                            items: products,
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
                            searchMatcher: (p, q) =>
                                p.name.toLowerCase().contains(q.toLowerCase()),
                          );
                        },
                        loading: () => const LinearProgressIndicator(),
                        error: (e, st) => const Text('Error loading products'),
                      ),
                  if (_selectedBaseUnitId != null) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _conversionController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'كم قطعة من الوحدة الأصغر يحتوي هذا المنتج؟',
                        hintText: 'مثلاً: كارتون فيه 24 علبة تضع 24',
                        filled: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 48),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.secondary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isLoading ? null : _save,
                    child: _isLoading
                        ? const CircularProgressIndicator(
                            color: AppColors.secondary,
                          )
                        : const Text(
                            'حفظ المنتج في قـاعدة البيانات',
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
        ),
      ),
    );
  }
}
