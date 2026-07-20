import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/api_feedback.dart';
import '../../auth/data/auth_repository.dart';
import '../data/order_repository.dart';
import '../utils/order_utils.dart';

final _nfmt = NumberFormat.currency(symbol: '₦', decimalDigits: 2, locale: 'en_NG');

class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({super.key, required this.order});

  final Map<String, dynamic> order;

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  late Map<String, dynamic> _order;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  bool get _isSeller {
    final uid = ref.read(authControllerProvider).user?['id'];
    return _order['seller_id'] == uid;
  }

  String get _status => '${_order['status'] ?? 'placed'}';
  String get _trackingCode => '${_order['tracking_code'] ?? ''}';

  List<Map<String, dynamic>> get _timeline {
    final raw = _order['timeline'] as List? ?? [];
    return raw.cast<Map<String, dynamic>>();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final updated = await ref.read(orderRepositoryProvider).getOrder('${_order['id']}');
      if (mounted) setState(() { _order = updated; _loading = false; });
    } catch (e) {
      if (mounted) { showApiError(context, e); setState(() => _loading = false); }
    }
  }

  Future<void> _confirmDelivery() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Confirm Delivery'),
        content: const Text('Are you sure you received this order?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not yet')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, I got it!')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _loading = true);
    try {
      final updated = await ref.read(orderRepositoryProvider).confirmDelivery('${_order['id']}');
      if (mounted) setState(() { _order = updated; _loading = false; });
      if (mounted) showApiSuccess(context, title: 'Delivery confirmed!', message: 'You can now leave a review for the seller.');
    } catch (e) {
      if (mounted) { showApiError(context, e); setState(() => _loading = false); }
    }
  }

  void _showUpdateStatusSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppTheme.surface,
      builder: (_) => _UpdateStatusSheet(
        currentStatus: _status,
        orderId: '${_order['id']}',
        orderRepo: ref.read(orderRepositoryProvider),
        onUpdated: (updated) { if (mounted) setState(() => _order = updated); },
      ),
    );
  }

  void _showReviewSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppTheme.surface,
      builder: (_) => _ReviewSheet(
        orderId: '${_order['id']}',
        orderRepo: ref.read(orderRepositoryProvider),
        onSubmitted: (updated) { if (mounted) setState(() => _order = updated); },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = _order['product'] as Map<String, dynamic>?;
    final snapshot = _order['product_snapshot'] as Map<String, dynamic>? ?? {};
    final title = '${product?['title'] ?? snapshot['title'] ?? 'Product'}';
    final images = product?['images'] as List? ?? [];
    final firstImage = images.isNotEmpty ? '${images[0]}' : null;
    final seller = _order['seller'] as Map<String, dynamic>?;
    final buyer = _order['buyer'] as Map<String, dynamic>?;
    final isCancelled = _status == 'cancelled';
    final hasReview = _order['review'] != null;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Order Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            Text(
              '#${('${_order['id']}').substring(0, 8).toUpperCase()}',
              style: const TextStyle(fontSize: 11, color: AppTheme.muted, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
          children: [
            // ── Product summary ──────────────────────────────────────────────
            _ProductSummaryCard(
              title: title,
              firstImage: firstImage,
              amount: (_order['amount'] as num?)?.toDouble() ?? 0,
              other: _isSeller ? buyer : seller,
              otherLabel: _isSeller ? 'Buyer' : 'Seller',
            ),

            // ── Status + tracking ────────────────────────────────────────────
            const SizedBox(height: 16),
            _StatusCard(
              status: _status,
              trackingCode: _trackingCode,
              onCopyTracking: () {
                Clipboard.setData(ClipboardData(text: _trackingCode));
                HapticFeedback.lightImpact();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tracking code copied'), duration: Duration(seconds: 2)),
                );
              },
            ),

            // ── Order journey ────────────────────────────────────────────────
            const SizedBox(height: 24),
            const Text('Order Journey', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            _TimelineStepper(
              currentStatus: _status,
              timeline: _timeline,
              isCancelled: isCancelled,
            ),

            // ── Review already submitted ─────────────────────────────────────
            if (hasReview) ...[
              const SizedBox(height: 24),
              _ReviewCard(review: _order['review'] as Map<String, dynamic>),
            ],
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(isCancelled, hasReview),
    );
  }

  Widget? _buildBottomBar(bool isCancelled, bool hasReview) {
    final isConfirmed = _status == 'confirmed';
    if (isCancelled) return null;
    if (isConfirmed && hasReview) return null;

    final actions = <Widget>[];

    if (_isSeller) {
      final nextStatuses = availableNextStatuses(_status);
      if (nextStatuses.isNotEmpty) {
        actions.add(FilledButton.icon(
          onPressed: _showUpdateStatusSheet,
          icon: const Icon(Icons.edit_rounded, size: 18),
          label: const Text('Update Order Status'),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primary,
            minimumSize: const Size(double.infinity, 52),
          ),
        ));
      }
    } else {
      if (_status == 'delivered') {
        actions.add(FilledButton.icon(
          onPressed: _loading ? null : _confirmDelivery,
          icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
          label: const Text('I Received This Order'),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.success,
            minimumSize: const Size(double.infinity, 52),
          ),
        ));
      }
      if (isConfirmed && !hasReview) {
        actions.add(OutlinedButton.icon(
          onPressed: _showReviewSheet,
          icon: const Icon(Icons.star_outline_rounded, size: 18),
          label: const Text('Leave a Review'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
            side: const BorderSide(color: AppTheme.border),
          ),
        ));
      }
    }

    if (actions.isEmpty) return null;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: actions,
        ),
      ),
    );
  }
}

// ── Product summary card ──────────────────────────────────────────────────────

class _ProductSummaryCard extends StatelessWidget {
  const _ProductSummaryCard({
    required this.title,
    required this.firstImage,
    required this.amount,
    required this.other,
    required this.otherLabel,
  });

  final String title;
  final String? firstImage;
  final double amount;
  final Map<String, dynamic>? other;
  final String otherLabel;

  @override
  Widget build(BuildContext context) {
    final otherName = '${other?['display_name'] ?? other?['username'] ?? ''}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: firstImage != null
                ? Image.memory(
                    _decodeImage(firstImage!),
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _placeholder(),
                  )
                : _placeholder(),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  _nfmt.format(amount),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppTheme.primaryBright),
                ),
                if (otherName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '$otherLabel: $otherName',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(color: AppTheme.elevated, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.image_outlined, color: AppTheme.muted, size: 28),
      );

  static Uint8List _decodeImage(String dataUrl) {
    final b64 = dataUrl.contains(',') ? dataUrl.split(',').last : dataUrl;
    return base64Decode(b64);
  }
}

// ── Status + tracking card ────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.status,
    required this.trackingCode,
    required this.onCopyTracking,
  });

  final String status;
  final String trackingCode;
  final VoidCallback onCopyTracking;

  @override
  Widget build(BuildContext context) {
    final color = orderStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(orderStatusIcon(status), color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Current Status', style: TextStyle(color: AppTheme.muted, fontSize: 11, fontWeight: FontWeight.w600)),
                    Text(
                      orderStatusLabel(status),
                      style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (trackingCode.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppTheme.border),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.qr_code_rounded, color: AppTheme.muted, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Tracking Code', style: TextStyle(color: AppTheme.muted, fontSize: 11)),
                      Text(
                        trackingCode,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontFamily: 'monospace', fontSize: 14),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: onCopyTracking,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.elevated,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy_rounded, size: 13, color: AppTheme.muted),
                        SizedBox(width: 4),
                        Text('Copy', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.muted)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Timeline stepper ──────────────────────────────────────────────────────────

class _TimelineStepper extends StatelessWidget {
  const _TimelineStepper({
    required this.currentStatus,
    required this.timeline,
    required this.isCancelled,
  });

  final String currentStatus;
  final List<Map<String, dynamic>> timeline;
  final bool isCancelled;

  Map<String, dynamic>? _eventFor(String status) {
    try {
      return timeline.firstWhere((e) => e['status'] == status);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIdx = allOrderSteps.indexOf(currentStatus);
    final steps = [...allOrderSteps];
    if (isCancelled) steps.add('cancelled');

    return Column(
      children: List.generate(steps.length, (i) {
        final step = steps[i];
        final event = _eventFor(step);
        final isDone = event != null ||
            (!isCancelled && allOrderSteps.indexOf(step) <= currentIdx);
        return _StepRow(
          status: step,
          isDone: isDone,
          isCurrent: step == currentStatus,
          event: event,
          showLine: i < steps.length - 1,
        );
      }),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.status,
    required this.isDone,
    required this.isCurrent,
    required this.event,
    required this.showLine,
  });

  final String status;
  final bool isDone;
  final bool isCurrent;
  final Map<String, dynamic>? event;
  final bool showLine;

  @override
  Widget build(BuildContext context) {
    final color = isDone ? orderStatusColor(status) : AppTheme.muted.withValues(alpha: 0.3);
    final textColor = isDone ? AppTheme.text : AppTheme.muted;
    final note = '${event?['note'] ?? ''}';
    final date = _fmtDate(event?['created_at']);
    final trackingCode = '${event?['tracking_code'] ?? ''}';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Dot + connector ──────────────────────────────────────────────
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDone ? color.withValues(alpha: 0.12) : AppTheme.elevated,
                    border: Border.all(
                      color: isCurrent
                          ? color
                          : isDone
                              ? color.withValues(alpha: 0.4)
                              : AppTheme.border,
                      width: isCurrent ? 2 : 1,
                    ),
                  ),
                  child: Icon(
                    isDone ? Icons.check_rounded : orderStatusIcon(status),
                    color: color,
                    size: 15,
                  ),
                ),
                if (showLine)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: isDone ? color.withValues(alpha: 0.3) : AppTheme.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          // ── Text content ─────────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: showLine ? 20 : 0, top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          orderStatusLabel(status),
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: textColor),
                        ),
                      ),
                      if (date.isNotEmpty)
                        Text(date, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
                    ],
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(note, style: const TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4)),
                  ],
                  if (trackingCode.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.qr_code_rounded, size: 12, color: AppTheme.muted),
                        const SizedBox(width: 4),
                        Text(
                          trackingCode,
                          style: const TextStyle(color: AppTheme.muted, fontSize: 11, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(dynamic raw) {
    if (raw == null) return '';
    try {
      return DateFormat('MMM d, HH:mm').format(DateTime.parse('$raw').toLocal());
    } catch (_) {
      return '';
    }
  }
}

// ── Review card (read-only) ───────────────────────────────────────────────────

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final Map<String, dynamic> review;

  @override
  Widget build(BuildContext context) {
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final comment = '${review['comment'] ?? ''}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your Review', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 10),
          Row(
            children: List.generate(
              5,
              (i) => Icon(
                i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                color: Colors.amber,
                size: 22,
              ),
            ),
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(comment, style: const TextStyle(color: AppTheme.muted, fontSize: 13, height: 1.5)),
          ],
        ],
      ),
    );
  }
}

// ── Update Status Sheet ───────────────────────────────────────────────────────

class _UpdateStatusSheet extends StatefulWidget {
  const _UpdateStatusSheet({
    required this.currentStatus,
    required this.orderId,
    required this.orderRepo,
    required this.onUpdated,
  });

  final String currentStatus;
  final String orderId;
  final OrderRepository orderRepo;
  final void Function(Map<String, dynamic>) onUpdated;

  @override
  State<_UpdateStatusSheet> createState() => _UpdateStatusSheetState();
}

class _UpdateStatusSheetState extends State<_UpdateStatusSheet> {
  String? _selectedStatus;
  final _noteCtrl     = TextEditingController();
  final _trackCtrl    = TextEditingController();
  final _trackUrlCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    _trackCtrl.dispose();
    _trackUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedStatus == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      final updated = await widget.orderRepo.updateStatus(
        orderId:      widget.orderId,
        status:       _selectedStatus!,
        note:         _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        trackingCode: _trackCtrl.text.trim().isEmpty ? null : _trackCtrl.text.trim(),
        trackingUrl:  _trackUrlCtrl.text.trim().isEmpty ? null : _trackUrlCtrl.text.trim(),
      );
      widget.onUpdated(updated);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nextStatuses = availableNextStatuses(widget.currentStatus);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Update Order Status', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'New Status'),
              initialValue: _selectedStatus,
              items: nextStatuses
                  .map((s) => DropdownMenuItem(
                        value: s,
                        child: Row(
                          children: [
                            Icon(orderStatusIcon(s), color: orderStatusColor(s), size: 18),
                            const SizedBox(width: 10),
                            Text(orderStatusLabel(s)),
                          ],
                        ),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedStatus = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'e.g. Your order is packed and ready to ship',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _trackCtrl,
              decoration: const InputDecoration(labelText: 'Tracking Code (optional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _trackUrlCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Tracking URL (optional)'),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _selectedStatus == null || _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Update Status'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Review Sheet ──────────────────────────────────────────────────────────────

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({
    required this.orderId,
    required this.orderRepo,
    required this.onSubmitted,
  });

  final String orderId;
  final OrderRepository orderRepo;
  final void Function(Map<String, dynamic>) onSubmitted;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  int _rating = 0;
  final _commentCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0 || _submitting) return;
    setState(() => _submitting = true);
    try {
      final updated = await widget.orderRepo.submitReview(
        orderId: widget.orderId,
        rating:  _rating,
        comment: _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim(),
      );
      widget.onSubmitted(updated);
      if (mounted) Navigator.pop(context);
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Rate Your Experience', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text(
            'How was your experience with this seller?',
            style: TextStyle(color: AppTheme.muted, fontSize: 13),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              5,
              (i) => GestureDetector(
                onTap: () => setState(() => _rating = i + 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    i < _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: Colors.amber,
                    size: 40,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _commentCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Comment (optional)',
              hintText: 'Share your experience...',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _rating == 0 || _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Submit Review'),
          ),
        ],
      ),
    );
  }
}
