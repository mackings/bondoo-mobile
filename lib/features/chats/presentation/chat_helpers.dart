import 'package:intl/intl.dart';

class ConversationMeta {
  const ConversationMeta(this.title, this.otherId, this.avatarUrl);

  final String title;
  final String? otherId;
  final String? avatarUrl;
}

ConversationMeta conversationMeta(
  Map<String, dynamic> conversation, {
  String? currentUserId,
}) {
  final me = currentUserId;
  final members = (conversation['conversation_members'] as List? ?? [])
      .cast<Map>();
  final other = members.cast<Map?>().firstWhere(
    (member) => member?['user_id'] != me,
    orElse: () => members.isEmpty ? null : members.first,
  );
  final profile = other?['profiles'] as Map?;
  final title = conversation['is_group'] == true
      ? '${conversation['name'] ?? 'Group'}'
      : '${profile?['display_name'] ?? 'Chat'}';
  return ConversationMeta(
    title,
    other?['user_id'] as String?,
    profile?['avatar_url'] as String?,
  );
}

String initials(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed == 'null') return 'B';
  return trimmed.substring(0, 1).toUpperCase();
}

String shortDate(dynamic value) {
  if (value == null) return '';
  final date = DateTime.tryParse('$value')?.toLocal();
  if (date == null) return '';
  return DateFormat.MMMd().format(date);
}

String messageTime(dynamic value) {
  if (value == null) return '';
  final date = DateTime.tryParse('$value')?.toLocal();
  if (date == null) return '';
  return DateFormat('HH:mm').format(date);
}

String conversationPreview(Map? message, {String? currentUserId}) {
  if (message == null) return 'Start the conversation';

  final mine = '${message['sender_id']}' == currentUserId;
  final prefix = mine ? 'You: ' : '';
  final kind = '${message['kind'] ?? 'text'}';

  switch (kind) {
    case 'image':
      return '${prefix}Photo';
    case 'voice':
      return '${prefix}Voice note';
    case 'offer':
      final offer = message['offer'] as Map?;
      final side = '${offer?['side'] ?? 'trade'}';
      final coin = '${offer?['coin'] ?? 'offer'}';
      return '${prefix}Offer: $side $coin';
    case 'transfer':
      final asset = '${message['transfer_asset'] ?? ''}'.trim();
      final amount = '${message['transfer_amount'] ?? ''}'.trim();
      final action = mine ? 'Sent' : 'Received';
      return '$prefix$action $amount $asset'.trim();
    default:
      final body = '${message['body'] ?? ''}'.trim();
      return body.isEmpty ? '${prefix}Message' : '$prefix$body';
  }
}
