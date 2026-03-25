import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/data_providers.dart';
import '../utils/app_colors.dart';
import '../services/local_database.dart';
import '../services/sync_service.dart';
import 'package:uuid/uuid.dart';

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
    if (_nameController.text.trim().isEmpty || _priceController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال اسم المنتج وسعره')),
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
        'name': _nameController.text.trim(),
        'barcode': _barcodeController.text.trim().isEmpty
            ? null
            : _barcodeController.text.trim(),
        'price': double.parse(_priceController.text),
        'cost_price': _costPriceController.text.isNotEmpty
            ? double.parse(_costPriceController.text)
            : null,
        'quantity': _qtyController.text.isNotEmpty
            ? double.parse(_qtyController.text)
            : 0.0,
        'category_id': _selectedCategoryId,
        'image_url': imageUrl,
        'base_unit_id': _selectedBaseUnitId,
        'base_unit_conversion':
            double.tryParse(_conversionController.text) ?? 1.0,
      };

      // 1. Try Online First
      try {
        final onlineRes = await supabase
            .from('products')
            .insert(productData)
            .select()
            .single();

        // 2. Mirror to Local as Synced
        await db.insert('products', {
          ...productData,
          'id': onlineRes['id'],
          'is_synced': 1,
        });

        ref.invalidate(productsProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تمت إضافة المنتج أونلاين بنجاح!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
        return; // Success, exit
      } catch (onlineError) {
        debugPrint('Online product save failed: $onlineError');
      }

      // 3. Fallback to Local (Offline)
      await db.insert('products', {...productData, 'is_synced': 0});

      ref
          .read(syncServiceProvider)
          .syncUp(); // Background sync when back online
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
                          data: (categories) => DropdownButtonFormField<int>(
                            value: _selectedCategoryId,
                            decoration: const InputDecoration(
                              labelText: 'القسم',
                              filled: true,
                            ),
                            items: categories
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c.id,
                                    child: Text(c.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedCategoryId = v),
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
                          return DropdownButtonFormField<int>(
                            value: _selectedBaseUnitId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'المنتج الأساسي (الوحدة الأصغر)',
                              filled: true,
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('لا يوجد (منتج أساسي مفرد)'),
                              ),
                              ...products.map(
                                (p) => DropdownMenuItem(
                                  value: p.id,
                                  child: Text(p.name),
                                ),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => _selectedBaseUnitId = v),
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
