import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/forms/form_validators.dart';
import '../../../shared/widgets/exchange_ui.dart';

class TransferPayload {
  const TransferPayload(this.asset, this.amount, this.note);

  final String asset;
  final double amount;
  final String note;
}

class TransferDialog extends StatefulWidget {
  const TransferDialog({super.key, required this.recipientName});

  final String recipientName;

  @override
  State<TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<TransferDialog> {
  final formKey = GlobalKey<FormState>();
  String asset = 'USDC';
  final amount = TextEditingController();
  final note = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const AssetAvatar(
            label: 'Send',
            icon: Icons.north_east_rounded,
            size: 42,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text('Send to ${widget.recipientName}')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Choose an asset and enter the amount you want to transfer.',
            style: TextStyle(color: AppTheme.muted),
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'BTC', label: Text('BTC')),
              ButtonSegment(value: 'ETH', label: Text('ETH')),
              ButtonSegment(value: 'USDC', label: Text('USDC')),
            ],
            selected: {asset},
            onSelectionChanged: (value) => setState(() => asset = value.first),
          ),
          const SizedBox(height: 12),
          Form(
            key: formKey,
            child: Column(
              children: [
                FieldContainer(
                  child: TextFormField(
                    controller: amount,
                    keyboardType: TextInputType.number,
                    validator: FormValidators.amount,
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      prefixIcon: const Icon(Icons.payments_outlined),
                      suffixText: asset,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FieldContainer(
                  child: TextFormField(
                    controller: note,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                      prefixIcon: Icon(Icons.notes_rounded),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () {
            if (!formKey.currentState!.validate()) return;
            final parsed = double.tryParse(amount.text);
            Navigator.pop(context, TransferPayload(asset, parsed!, note.text));
          },
          icon: const Icon(Icons.arrow_upward_rounded),
          label: Text('Send $asset'),
        ),
      ],
    );
  }
}
