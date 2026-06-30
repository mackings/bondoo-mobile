import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class ThousandsInputFormatter extends TextInputFormatter {
  ThousandsInputFormatter({this.decimal = false});
  final bool decimal;
  final _whole = NumberFormat('#,##0');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = newValue.text.replaceAll(',', '');
    if (raw.isEmpty) return newValue;
    final valid = decimal ? RegExp(r'^\d*\.?\d*$').hasMatch(raw) : RegExp(r'^\d*$').hasMatch(raw);
    if (!valid || raw == '.') return oldValue;
    final parts = raw.split('.');
    final whole = parts.first.isEmpty ? '0' : parts.first;
    final n = int.tryParse(whole);
    if (n == null) return oldValue;
    var formatted = _whole.format(n);
    if (decimal && raw.contains('.')) {
      formatted = '$formatted.${parts.length > 1 ? parts[1] : ''}';
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
