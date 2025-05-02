class Message {
  final int? id;
  final String contactIp;
  final String sender;
  final String type; // 'text' or 'image'
  final String? content; // For text messages
  final String? path; // For image paths
  final DateTime timestamp;

  Message({
    this.id,
    required this.contactIp,
    required this.sender,
    required this.type,
    this.content,
    this.path,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'contact_ip': contactIp,
      'sender': sender,
      'type': type,
      'content': content,
      'path': path,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'],
      contactIp: map['contact_ip'],
      sender: map['sender'],
      type: map['type'],
      content: map['content'],
      path: map['path'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
    );
  }
}