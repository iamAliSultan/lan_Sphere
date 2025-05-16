import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../color.dart';
import 'chat_screen.dart';
import 'login_signup_screen.dart';

class LanContact {
  final String name;
  final String ip;
  final String id;
  final String? profilePic;
  String? lastMessage;

  LanContact({required this.name, required this.ip, required this.id, this.profilePic, this.lastMessage});

  Map<String, dynamic> toMap() => {
        'name': name,
        'ip': ip,
        'id': id,
        'profilePic': profilePic,
        'lastMessage': lastMessage,
      };

  factory LanContact.fromMap(Map<String, dynamic> map) => LanContact(
        name: map['name'],
        ip: map['ip'],
        id: map['id'],
        profilePic: map['profilePic'],
        lastMessage: map['lastMessage'],
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
    // Establish TCP connection and set contact name
    final client = await ChatManager().getTcpClient(contact.ip);
    if (client != null) ChatManager().setContactName(contact.ip, contact.name);
    _loadContacts();
  }

  Future<void> _saveAllContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final contactListJson = contacts.map((contact) => json.encode(contact.toMap())).toList();
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

  Future<String?> _copyImageToAppDir(String? imagePath) async {
    if (imagePath == null) return null;
    final directory = await getApplicationDocumentsDirectory();
    final profilePicsDir = Directory('${directory.path}/profile_pics');
    if (!await profilePicsDir.exists()) {
      await profilePicsDir.create();
    }
    final fileName = 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final newPath = '${profilePicsDir.path}/$fileName';
    await File(imagePath).copy(newPath);
    return newPath;
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

              final contactData = await showDialog<ContactData>(
                context: context,
                builder: (context) => ContactEditorDialog(initialName: ''),
              );

              if (contactData == null || contactData.name.isEmpty) {
                Navigator.pop(context); // Close QRScannerScreen if Cancel is pressed or no name is provided
                return;
              }

              final profilePicPath = await _copyImageToAppDir(contactData.profilePicPath);
              final contact = LanContact(
                name: contactData.name,
                ip: scannedIp,
                id: id,
                profilePic: profilePicPath,
              );
              await _saveContact(contact);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Saved Contact: ${contact.name}")),
              );

              // Navigate directly to ChatScreen after saving the new contact
              Navigator.pop(context); // Close QRScannerScreen
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatScreen(contact: contact),
                ),
              );
            } catch (_) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Invalid QR Code Format")),
              );
              Navigator.pop(context); // Close QRScannerScreen on error
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
                  leading: CircleAvatar(
                    backgroundImage: contact.profilePic != null && File(contact.profilePic!).existsSync()
                        ? FileImage(File(contact.profilePic!))
                        : null,
                    child: contact.profilePic == null || !File(contact.profilePic!).existsSync()
                        ? const Icon(Icons.person, color: Color(0xFF1E2C2F))
                        : null,
                  ),
                  onTap: () async {
                    final updatedContact = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatScreen(contact: contact),
                      ),
                    );
                    if (updatedContact != null) {
                      setState(() {
                        contacts[index] = updatedContact;
                      });
                      await _saveAllContacts();
                    }
                  },
                  trailing: PopupMenuButton<String>(
                    color: Colors.black.withOpacity(0.6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.white.withOpacity(0.2)),
                    ),
                    onSelected: (value) async {
                      if (value == 'edit') {
                        final contactData = await showDialog<ContactData>(
                          context: context,
                          builder: (context) => ContactEditorDialog(
                            initialName: contact.name,
                            initialProfilePic: contact.profilePic,
                          ),
                        );
                        if (contactData != null && contactData.name.isNotEmpty) {
                          final profilePicPath = await _copyImageToAppDir(contactData.profilePicPath);
                          setState(() {
                            contacts[index] = LanContact(
                              name: contactData.name,
                              ip: contact.ip,
                              id: contact.id,
                              profilePic: profilePicPath,
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
                      const PopupMenuItem(value: 'edit', child: Text("Edit", style: TextStyle(color: Colors.white))),
                      const PopupMenuItem(value: 'delete', child: Text("Delete", style: TextStyle(color: Colors.white))),
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

class ContactData {
  final String name;
  final String? profilePicPath;

  ContactData({required this.name, this.profilePicPath});
}

class ContactEditorDialog extends StatefulWidget {
  final String initialName;
  final String? initialProfilePic;

  const ContactEditorDialog({
    required this.initialName,
    this.initialProfilePic,
  });

  @override
  _ContactEditorDialogState createState() => _ContactEditorDialogState();
}

class _ContactEditorDialogState extends State<ContactEditorDialog> {
  final TextEditingController _nameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.initialName;
    if (widget.initialProfilePic != null) {
      _selectedImage = File(widget.initialProfilePic!);
    }
  }

  Future<void> _pickImage() async {
    try {
      print('Attempting to pick image...');
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 50,
      );
      print('Image picked: ${image?.path}');

      if (image != null) {
        final file = File(image.path);
        if (await file.exists()) {
          print('File exists at path: ${image.path}');
          setState(() {
            _selectedImage = file;
          });
        } else {
          print('File does not exist at path: ${image.path}');
        }
      } else {
        print('No image selected');
      }
    } catch (e, stackTrace) {
      print('Error picking image: $e');
      print('Stack trace: $stackTrace');
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImage = null;
    });
    print('Image removed');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColor.appbar, AppColor.headertext, AppColor.button],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8.0),
              child: const Text(
                'Edit Contact',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: CircleAvatar(
                              radius: 30,
                              backgroundImage: _selectedImage != null
                                  ? FileImage(_selectedImage!)
                                  : null,
                              child: _selectedImage == null
                                  ? const Icon(Icons.person, size: 30, color: Colors.white)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.camera_alt, color: AppColor.button, size: 24),
                            onPressed: _pickImage,
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red, size: 24),
                            onPressed: _removeImage,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: 200,
                        child: TextField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: 'Name',
                            labelStyle: const TextStyle(color: Colors.white),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Colors.white),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Colors.white),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Colors.white),
                            ),
                          ),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context); // Simply close the dialog on Cancel
                    },
                    child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                  ),
                  TextButton(
                    onPressed: () {
                      final name = _nameController.text.trim();
                      if (name.isNotEmpty) {
                        Navigator.pop(
                          context,
                          ContactData(
                            name: name,
                            profilePicPath: _selectedImage?.path,
                          ),
                        );
                      }
                    },
                    child: const Text('Save', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ],
        ),
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
              final picker = ImagePicker();
              final image = await picker.pickImage(source: ImageSource.gallery);
              if (image != null) {
                final result = await controller.analyzeImage(image.path);
                if (result?.barcodes.isNotEmpty == true) {
                  final rawValue = result!.barcodes.first.rawValue;
                  if (rawValue != null) {
                    onScan(rawValue);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("No QR code found in the image")),
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("No QR code detected in the image")),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: Center(
        child: Container(
          width: 300,
          height: 300,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color.fromARGB(255, 3, 70, 47), width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: MobileScanner(
              fit: BoxFit.cover,
              controller: controller,
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