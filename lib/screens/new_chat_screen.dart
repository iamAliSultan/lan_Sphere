import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../color.dart';
import 'package:image_picker/image_picker.dart';
import './chat_screen.dart';

class LanContact {
  final String name;
  final String ip;
  final String id;

  LanContact({required this.name, required this.ip, required this.id});

  Map<String, dynamic> toMap() => {'name': name, 'ip': ip, 'id': id};

  factory LanContact.fromMap(Map<String, dynamic> map) => LanContact(
        name: map['name'],
        ip: map['ip'],
        id: map['id'],
      );
}

class NewChatScreen extends StatefulWidget {
  @override
  _NewChatScreenState createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  String? deviceQRCode;
  List<LanContact> contacts = [];

  @override
  void initState() {
    super.initState();
    _generateDeviceQRCode();
    _loadContacts();
  }

  Future<void> _generateDeviceQRCode() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString('device_qr_code');
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString('device_qr_code', id);
    }
    final ip = await NetworkInfo().getWifiIP() ?? "0.0.0.0";
    setState(() {
      deviceQRCode = jsonEncode({'id': id, 'ip': ip});
    });
  }

  Future<void> _loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final contactListJson = prefs.getStringList('contacts') ?? [];
    setState(() {
      contacts = contactListJson
          .map((contactJson) => LanContact.fromMap(json.decode(contactJson)))
          .toList();
    });
  }

  Future<void> _saveContact(LanContact contact) async {
    final prefs = await SharedPreferences.getInstance();
    final contactListJson = prefs.getStringList('contacts') ?? [];
    contactListJson.add(json.encode(contact.toMap()));
    await prefs.setStringList('contacts', contactListJson);
    _loadContacts();
  }

  Future<void> _saveAllContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final contactListJson =
        contacts.map((contact) => json.encode(contact.toMap())).toList();
    await prefs.setStringList('contacts', contactListJson);
  }

  bool _isSameSubnet(String ip1, String ip2) {
    final parts1 = ip1.split('.');
    final parts2 = ip2.split('.');
    return parts1.length == 4 &&
        parts2.length == 4 &&
        parts1[0] == parts2[0] &&
        parts1[1] == parts2[1] &&
        parts1[2] == parts2[2];
  }

  void _scanQRCode() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QRScannerScreen(
          onScan: (rawResult) async {
            try {
              final data = jsonDecode(rawResult);
              if (data['id'] == null || data['ip'] == null) throw 'Invalid QR code';

              final id = data['id'];
              final scannedIp = data['ip'];
              final myIp = await NetworkInfo().getWifiIP() ?? "";

              if (!_isSameSubnet(myIp, scannedIp)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Device is not on the same LAN!")),
                );
                Navigator.pop(context);
                return;
              }

              if (contacts.any((c) => c.id == id)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Device already saved!")),
                );
                Navigator.pop(context);
                return;
              }

              final name = await showDialog<String>(
                context: context,
                builder: (context) {
                  String deviceName = "";
                  return AlertDialog(
                    title: const Text("Enter Device Name"),
                    content: TextField(
                      onChanged: (value) => deviceName = value,
                      decoration: const InputDecoration(hintText: "Device Name"),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, null),
                        child: const Text("Cancel"),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, deviceName),
                        child: const Text("Save"),
                      ),
                    ],
                  );
                },
              );

              if (name == null || name.isEmpty) {
                Navigator.pop(context);
                return;
              }

              final contact = LanContact(name: name, ip: scannedIp, id: id);
              await _saveContact(contact);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Saved Contact: ${contact.name}")),
              );
              Navigator.pop(context);
            } catch (_) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Invalid QR Code Format")),
              );
              Navigator.pop(context);
            }
          },
        ),
      ),
    );
  }

  void _showQRCodeScreen() {
    if (deviceQRCode == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QRDisplayScreen(deviceQRCode: deviceQRCode!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.background,
      appBar: AppBar(
        backgroundColor: AppColor.appbar,
        title: const Text("New Chat", style: TextStyle(color: Colors.white)),
        iconTheme: IconThemeData(color: AppColor.text),
      ),
      body: Column(
        children: [
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFF629584),
              child: Icon(Icons.person_add, color: Colors.white),
            ),
            title: Text("New Contact", style: TextStyle(color: AppColor.text)),
            trailing: Icon(Icons.qr_code_scanner, color: AppColor.text),
            onTap: _scanQRCode,
          ),
          const Divider(),
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFF4A5DFF),
              child: Icon(Icons.qr_code, color: Colors.white),
            ),
            title: Text("Generate QR Code", style: TextStyle(color: AppColor.text)),
            trailing: Icon(Icons.arrow_forward, color: AppColor.text),
            onTap: _showQRCodeScreen,
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: contacts.length,
              itemBuilder: (context, index) {
                final contact = contacts[index];
                return ListTile(
                  title: Text(contact.name, style: TextStyle(color: AppColor.text)),
                  subtitle: Text("IP: ${contact.ip}", style: TextStyle(color: Colors.grey)),
                  leading: const Icon(Icons.person, color: Color(0xFF1E2C2F)),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatScreen(contact: contact),
                      ),
                    );
                  },
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'edit') {
                        final newName = await showDialog<String>(
                          context: context,
                          builder: (context) {
                            String name = contact.name;
                            return AlertDialog(
                              title: const Text("Edit Contact Name"),
                              content: TextField(
                                controller: TextEditingController(text: name),
                                onChanged: (value) => name = value,
                                decoration: const InputDecoration(hintText: "Contact Name"),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, null),
                                  child: const Text("Cancel"),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, name),
                                  child: const Text("Save"),
                                ),
                              ],
                            );
                          },
                        );
                        if (newName != null && newName.isNotEmpty) {
                          setState(() {
                            contacts[index] = LanContact(
                              name: newName,
                              ip: contact.ip,
                              id: contact.id,
                            );
                          });
                          await _saveAllContacts();
                        }
                      } else if (value == 'delete') {
                        setState(() {
                          contacts.removeAt(index);
                        });
                        await _saveAllContacts();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text("Edit")),
                      const PopupMenuItem(value: 'delete', child: Text("Delete")),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class QRScannerScreen extends StatelessWidget {
  final Function(String) onScan;
  final MobileScannerController controller = MobileScannerController();

  QRScannerScreen({required this.onScan});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.background,
      appBar: AppBar(
        backgroundColor: AppColor.appbar,
        title: const Text("Scan QR Code", style: TextStyle(color: Colors.white)),
        iconTheme: IconThemeData(color: AppColor.text),
        actions: [
          IconButton(
            icon: const Icon(Icons.switch_camera),
            onPressed: () => controller.switchCamera(),
          ),
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.image),
            onPressed: () async {
              final image = await ImagePicker().pickImage(source: ImageSource.gallery);
              if (image != null) {
                final result = await controller.analyzeImage(image.path);
                if (result?.raw != null) {
                  onScan(result!.raw! as String);
                }
              }
            },
          )
        ],
      ),
      body: Center(
        child: Container(
          width: 300,
          height: 300,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color.fromARGB(255, 3, 70, 47), width: 2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: MobileScanner(
              fit: BoxFit.cover,
              onDetect: (capture) {
                for (final barcode in capture.barcodes) {
                  if (barcode.rawValue != null) {
                    onScan(barcode.rawValue!);
                    break;
                  }
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}

class QRDisplayScreen extends StatelessWidget {
  final String deviceQRCode;

  const QRDisplayScreen({required this.deviceQRCode});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.background,
      appBar: AppBar(
        backgroundColor: AppColor.appbar,
        title: const Text("Your QR Code", style: TextStyle(color: Colors.white)),
        iconTheme: IconThemeData(color: AppColor.text),
      ),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColor.appbar,
            borderRadius: BorderRadius.circular(12),
          ),
          child: QrImageView(
            data: deviceQRCode,
            version: QrVersions.auto,
            size: 250,
            backgroundColor: Colors.white,
          ),
        ),
      ),
    );
  }
}
