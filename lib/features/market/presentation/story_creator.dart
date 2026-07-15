import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/api_feedback.dart';
import '../data/story_repository.dart';

class StoryCreatorSheet extends ConsumerStatefulWidget {
  const StoryCreatorSheet({super.key});

  @override
  ConsumerState<StoryCreatorSheet> createState() => _StoryCreatorSheetState();
}

class _StoryCreatorSheetState extends ConsumerState<StoryCreatorSheet> {
  final _textCtrl = TextEditingController();
  String? _imageDataUrl;
  bool _posting = false;
  final _picker = ImagePicker();

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 80,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return;
    final mimeType = file.mimeType ?? 'image/jpeg';
    setState(() {
      _imageDataUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';
    });
  }

  Future<void> _post() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty && _imageDataUrl == null) {
      showApiError(context, 'Add an image or text to post a story.');
      return;
    }
    setState(() => _posting = true);
    try {
      await ref.read(storyRepositoryProvider).createStory(
            text: text.isEmpty ? null : text,
            imageDataUrl: _imageDataUrl,
          );
      if (mounted) Navigator.pop(context, 'created');
    } catch (e) {
      if (mounted) {
        showApiError(context, e);
        setState(() => _posting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasContent = _textCtrl.text.trim().isNotEmpty || _imageDataUrl != null;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text('New Story',
                    style: TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 18)),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // ── Image preview / picker ──────────────────────────────────
          GestureDetector(
            onTap: _pickImage,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 20),
              height: _imageDataUrl != null ? 200 : 80,
              decoration: BoxDecoration(
                color: AppTheme.elevated,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: _imageDataUrl != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(
                          base64Decode(_imageDataUrl!.substring(
                              _imageDataUrl!.indexOf(',') + 1)),
                          fit: BoxFit.cover,
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: () => setState(() => _imageDataUrl = null),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close,
                                  color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: _pickImage,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text('Change',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ),
                      ],
                    )
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined,
                            color: AppTheme.muted, size: 28),
                        SizedBox(height: 4),
                        Text('Tap to add photo',
                            style: TextStyle(
                                color: AppTheme.muted, fontSize: 12)),
                      ],
                    ),
            ),
          ),

          const SizedBox(height: 12),

          // ── Caption input ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _textCtrl,
              maxLines: 3,
              maxLength: 300,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Add a caption… (optional)',
                hintStyle: const TextStyle(color: AppTheme.muted),
                filled: true,
                fillColor: AppTheme.elevated,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                counterStyle: const TextStyle(color: AppTheme.muted),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Post button ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: FilledButton.icon(
              onPressed: (_posting || !hasContent) ? null : _post,
              icon: _posting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded),
              label: const Text('Post Story'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}
