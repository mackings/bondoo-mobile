import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/api_feedback.dart';
import '../data/product_repository.dart';

class ProductCreateSheet extends ConsumerStatefulWidget {
  const ProductCreateSheet({super.key});

  @override
  ConsumerState<ProductCreateSheet> createState() => _ProductCreateSheetState();
}

const _listingCategories = ['Electronics', 'Fashion', 'Food & Drinks', 'Services', 'Others'];

class _ProductCreateSheetState extends ConsumerState<ProductCreateSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _picker = ImagePicker();
  final List<String> _images = [];
  String _category = _listingCategories.first;
  bool _submitting = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_images.length >= 3) return;
    final img = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 80,
    );
    if (img == null) return;
    final bytes = await img.readAsBytes();
    if (bytes.isEmpty) return;
    final mime = _mimeType(img.name);
    final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
    if (dataUrl.length > 1_400_000) {
      if (mounted) showApiError(context, 'Image too large. Pick a smaller one.');
      return;
    }
    setState(() => _images.add(dataUrl));
  }

  String _mimeType(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _submitting) return;
    if (_images.isEmpty) {
      showApiError(context, 'Add at least one product image.');
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(productRepositoryProvider).createProduct(
            title: _titleCtrl.text.trim(),
            description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
            price: double.parse(_priceCtrl.text.trim().replaceAll(',', '')),
            images: _images,
            category: _category,
          );
      if (mounted) Navigator.pop(context, 'created');
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('List a Product', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),

              // Image pickers
              Row(
                children: [
                  for (int i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: GestureDetector(
                          onTap: i < _images.length
                              ? () => setState(() => _images.removeAt(i))
                              : _pickImage,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppTheme.elevated,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.border),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: i < _images.length
                                ? Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.memory(
                                        base64Decode(_images[i].split(',').last),
                                        fit: BoxFit.cover,
                                      ),
                                      Positioned(
                                        top: 4,
                                        right: 4,
                                        child: Container(
                                          decoration: const BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.close, color: Colors.white, size: 16),
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_photo_alternate_outlined,
                                        color: _images.length < 3 ? AppTheme.primary : AppTheme.muted,
                                        size: 28,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        i == 0 ? 'Cover' : 'Photo ${i + 1}',
                                        style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'Title *'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a title' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(labelText: 'Description (optional)'),
                minLines: 2,
                maxLines: 4,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _priceCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [_thousandsFormatter],
                decoration: const InputDecoration(labelText: 'Price (₦) *', prefixText: '₦ '),
                validator: (v) {
                  final d = double.tryParse(v?.trim().replaceAll(',', '') ?? '');
                  if (d == null || d <= 0) return 'Enter a valid price';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Category
              const Text('Category', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.muted)),
              const SizedBox(height: 8),
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _listingCategories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final cat = _listingCategories[i];
                    final selected = _category == cat;
                    return GestureDetector(
                      onTap: () => setState(() => _category = cat),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: selected ? AppTheme.primary : AppTheme.elevated,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: selected ? AppTheme.primary : AppTheme.border),
                        ),
                        child: Text(
                          cat,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: selected ? Colors.white : AppTheme.muted,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.storefront_rounded),
                label: const Text('List Product'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final _thousandsFormatter = TextInputFormatter.withFunction((oldValue, newValue) {
  final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.isEmpty) return newValue.copyWith(text: '');
  final buf = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  final formatted = buf.toString();
  return TextEditingValue(
    text: formatted,
    selection: TextSelection.collapsed(offset: formatted.length),
  );
});
