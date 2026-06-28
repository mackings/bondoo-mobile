class FormValidators {
  static String? requiredText(String? value, {String label = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$label is required';
    return null;
  }

  static String? email(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Email is required';
    final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text);
    if (!valid) return 'Enter a valid email address';
    return null;
  }

  static String? password(String? value) {
    final text = value ?? '';
    if (text.isEmpty) return 'Password is required';
    if (text.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  static String? username(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Username is required';
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(text)) {
      return 'Use lowercase letters, numbers, or underscores';
    }
    return null;
  }

  static String? amount(String? value) {
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null) return 'Enter a valid amount';
    if (parsed <= 0) return 'Amount must be greater than zero';
    return null;
  }

  static String? walletAddress(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Wallet address is required';
    if (text.length < 10) return 'Wallet address is too short';
    return null;
  }

  static String? otp(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'OTP code is required';
    if (!RegExp(r'^\d{4}$').hasMatch(text)) return 'Enter a 4 digit OTP code';
    return null;
  }
}
