import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

final contactsRepositoryProvider = Provider<ContactsRepository>((ref) =>
    ContactsRepository(ref.watch(apiClientProvider)));

class BondooContact {
  final String name;
  final String phone;
  final Map<String, dynamic>? user; // non-null = on Bondoo

  const BondooContact({required this.name, required this.phone, this.user});
  bool get isOnApp => user != null;
}

class ContactsRepository {
  ContactsRepository(this._api);
  final ApiClient _api;

  Future<List<BondooContact>> syncContacts() async {
    // 1. Request permission
    final granted = await FlutterContacts.requestPermission(readonly: true);
    if (!granted) return [];

    // 2. Read all contacts with phones
    final contacts = await FlutterContacts.getContacts(withProperties: true);

    // 3. Collect all phone numbers with their contact names
    final phoneToName = <String, String>{};
    for (final c in contacts) {
      final name = c.displayName.isNotEmpty ? c.displayName : 'Unknown';
      for (final p in c.phones) {
        final normalized = _normalize(p.number);
        if (normalized.length >= 7) phoneToName[normalized] = name;
      }
    }

    if (phoneToName.isEmpty) return [];

    // 4. Send to backend — batch up to 500
    final phones = phoneToName.keys.take(500).toList();
    final matched = await _api.post('/contacts/sync', {'phones': phones}) as List;

    // 5. Build result: matched contacts show the user, others for invite
    final matchedPhones = <String>{};
    final result = <BondooContact>[];

    for (final m in matched) {
      final phone = '${(m as Map)['phone']}';
      final user = m['user'] as Map<String, dynamic>;
      final name = phoneToName[phone] ?? user['display_name'] ?? phone;
      matchedPhones.add(phone);
      result.add(BondooContact(name: '$name', phone: phone, user: user));
    }

    // Add all unmatched contacts for invite
    for (final entry in phoneToName.entries) {
      if (matchedPhones.contains(entry.key)) continue;
      result.add(BondooContact(name: entry.value, phone: entry.key));
    }

    return result;
  }

  String _normalize(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[\s\-\(\)\.]+'), '');
    if (cleaned.startsWith('+')) return cleaned;
    final digits = cleaned.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.startsWith('234')) return '+$digits';
    if (digits.startsWith('0') && digits.length == 11) return '+234${digits.substring(1)}';
    return '+$digits';
  }
}
