// lan_contact.dart
class LanContact {
  final String name;
  final String ip;

  LanContact({required this.name, required this.ip});

  // Convert the contact to a map for saving/loading messages
  Map<String, String> toMap() {
    return {
      'name': name,
      'ip': ip,
    };
  }

  // Create a LanContact from a map
  factory LanContact.fromMap(Map<String, String> map) {
    return LanContact(
      name: map['name'] ?? '',
      ip: map['ip'] ?? '',
    );
  }
}
