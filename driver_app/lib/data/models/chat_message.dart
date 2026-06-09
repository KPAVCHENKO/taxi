/// Сообщение чата (общий или личный с диспетчером).
class ChatMessage {
  final int id;
  final String room; // group | d<id>
  final String sender; // admin | driver
  final String authorName;
  final String body;
  final String createdAt;

  const ChatMessage({
    required this.id,
    required this.room,
    required this.sender,
    required this.authorName,
    required this.body,
    required this.createdAt,
  });

  bool get isMine => sender == 'driver';

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    return ChatMessage(
      id: (j['id'] is int) ? j['id'] as int : int.tryParse('${j['id']}') ?? 0,
      room: (j['room'] ?? '').toString(),
      sender: (j['sender'] ?? 'admin').toString(),
      authorName: (j['author_name'] ?? 'Диспетчер').toString(),
      body: (j['body'] ?? '').toString(),
      createdAt: (j['created_at'] ?? '').toString(),
    );
  }
}
