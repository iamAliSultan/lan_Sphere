import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'new_chat_screen.dart';
import 'dart:typed_data';


class ChatScreen extends StatefulWidget {
  final LanContact contact;

  const ChatScreen({required this.contact});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late RawDatagramSocket socket;
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, String>> messages = [];
  final int udpPort = 4567;
  late String localIp;
  late String myName;
  static const int _tcpPort = 4568; // Default TCP port
  ServerSocket? _tcpServer;
  Socket? _tcpClient;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;

  @override
  void initState() {
    super.initState();
    _getLocalIp();
    _startListening();
    _startTcpServer();
    initNotifications();
    _loadMessages();
  }

  Future<void> _saveMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'chat_${widget.contact.ip.replaceAll('.', '_')}';

    final encoded = messages.map((m) {
      if (m['type'] == 'image') {
        return "${m['sender']}|image|${m['path']}";
      } else {
        return "${m['sender']}|text|${m['message']}";
      }
    }).toList();

    await prefs.setStringList(key, encoded);
  }

  Future<void> _loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'chat_${widget.contact.ip.replaceAll('.', '_')}';
    final encoded = prefs.getStringList(key) ?? [];

    final loaded = encoded.map((e) {
      final parts = e.split('|');
      if (parts.length >= 3 && parts[1] == 'image') {
        return {
          "sender": parts[0],
          "type": "image",
          "path": parts[2],
        };
      } else {
        return {
          "sender": parts[0],
          "type": "text",
          "message": parts.length >= 3 ? parts[2] : "",
        };
      }
    }).toList();

    setState(() {
      messages.addAll(loaded);
    });
  }

  Future<void> initNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('app_icon');
    final InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
    );
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> _showNotification(String message) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
     'lan_chat_messages',  // Channel ID
    'LAN Chat Messages',   // Channel name
channelDescription: 'Notifications for incoming chat messages',
importance: Importance.max,  // Makes notification show as heads-up
priority: Priority.high,
showWhen: true,  // Shows timestamp
enableVibration: true,
playSound: true,
sound: RawResourceAndroidNotificationSound('notification_sound'),
ledColor: Colors.blue,
ledOnMs: 1000,
ledOffMs: 500,
    );

    const NotificationDetails notificationDetails =
      NotificationDetails(android: androidDetails);

  await flutterLocalNotificationsPlugin.show(
    0, 
    'New Message', 
    message, 
    notificationDetails,
    payload: 'chat_message',
  );
  }

  void _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            localIp = addr.address;
            myName = localIp;
            return;
          }
        }
      }
    } catch (e) {
      print("Error getting local IP: $e");
    }
  }

    Future<void> _startTcpServer() async {
    try {
      _tcpServer = await ServerSocket.bind(InternetAddress.anyIPv4, _tcpPort);
      _tcpServer!.listen((Socket client) {
        client.listen(
          (Uint8List data) {
            _handleIncomingTcpData(data);
          },
          onError: (error) {
            print('TCP Client error: $error');
            client.close();
          },
          onDone: () {
            print('TCP Client disconnected');
            client.close();
          },
        );
      });
      print('TCP server listening on port $_tcpPort');
    } catch (e) {
      print('Error starting TCP server: $e');
    }
  }
  // Handle incoming TCP data (primarily for images)
  



  void _startListening() async {
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, udpPort);
      socket.listen((RawSocketEvent event) async {
        if (event == RawSocketEvent.read) {
          Datagram? datagram = socket.receive();
          if (datagram != null) {
            final message = utf8.decode(datagram.data);
            final parts = message.split('|');
            if (parts.length == 2) {
              final senderName = parts[0];
              final msg = parts[1];

              if (senderName != myName) {
                setState(() {
                  messages.add({
                    "sender": senderName,
                    "message": msg,
                    "type": "text"
                  });
                });
                await _saveMessages();
                _showNotification(msg);
              }
            } else if (parts.length > 2 && parts[1] == 'image') {
              // Handle the image bytes
              final imageBytes = datagram.data;
              final file = await _saveImage(imageBytes);

              if (file != null) {
                setState(() {
                  messages.add({
                    "sender": parts[0],
                    "type": "image",
                    "path": file.path,
                  });
                });
                await _saveMessages();
              }
            }
          }
        }
      });
    } catch (e) {
      print("Error starting listener: $e");
    }
  }

  Future<File?> _saveImage(List<int> imageBytes) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/received_image_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(imageBytes);
      return file;
    } catch (e) {
      print("Error saving image: $e");
      return null;
    }
  }
void _sendMessage() async {
  final message = _messageController.text.trim();

  if (message.isEmpty && _selectedImage == null) return;

  // Sending text message (always use UDP for text)
  if (message.isNotEmpty) {
    final encodedMessage = utf8.encode("$myName|$message");
    try {
      final destination = InternetAddress(widget.contact.ip);
      RawDatagramSocket.bind(InternetAddress.anyIPv4, 0).then((sock) {
        sock.send(encodedMessage, destination, udpPort);
        sock.close();
      });

      setState(() {
        messages.add({
          "sender": myName,
          "message": message,
          "type": "text"
        });
      });
    } catch (e) {
      print("Error sending text: $e");
    }
  }

  // Sending image message (use TCP if available, otherwise UDP)
  if (_selectedImage != null) {
    await _sendImage(_selectedImage!);
  }

  setState(() {
    _messageController.clear();
    _selectedImage = null;
  });

  await _saveMessages();
}
Future<void> _handleImageSelection() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;
      setState(() {
        _selectedImage = File(image.path);
      });
    } catch (e) {
      print("Error picking image: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to pick image: ${e.toString()}")),
      );
    }
  }


Future<void> _sendImage(File image) async {
  try {
    final imageBytes = await image.readAsBytes();
    
    // Try TCP first for images (you can adjust the size threshold)
    if (await _ensureTcpConnected()) {
      // Send with simple header: "sender|image|filename|nullbyte"
      final header = '${myName}|image|${image.path.split('/').last}';
      _tcpClient!.add(utf8.encode(header));
      _tcpClient!.add([0]); // Null byte separator
      _tcpClient!.add(imageBytes);
    } else {
      // Fall back to UDP if TCP fails
      final destination = InternetAddress(widget.contact.ip);
      RawDatagramSocket.bind(InternetAddress.anyIPv4, 0).then((sock) {
        sock.send(imageBytes, destination, udpPort);
        sock.close();
      });
    }

    setState(() {
      messages.add({
        "sender": myName,
        "type": "image",
        "path": image.path,
      });
    });
  } catch (e) {
    print("Error sending image: $e");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Failed to send image")),
    );
  }
}

Future<bool> _ensureTcpConnected() async {
  if (_tcpClient != null) return true;
  
  try {
    _tcpClient = await Socket.connect(
      widget.contact.ip,
      _tcpPort,
      timeout: Duration(seconds: 3)
    );
    
    _tcpClient!.listen(
      (Uint8List data) {
        _handleIncomingTcpData(data);
      },
      onError: (error) {
        print('TCP Connection error: $error');
        _tcpClient?.close();
        _tcpClient = null;
      },
      onDone: () {
        print('TCP Connection closed');
        _tcpClient?.close();
        _tcpClient = null;
      },
    );
    return true;
  } catch (e) {
    print('TCP connection failed: $e');
    return false;
  }
}

void _handleIncomingTcpData(Uint8List data) {
  try {
    // Simple header format: "sender|image|filename"
    final headerEnd = data.indexOf(0); // Null byte separator
    if (headerEnd > 0) {
      final header = utf8.decode(data.sublist(0, headerEnd));
      final imageData = data.sublist(headerEnd + 1);
      final parts = header.split('|');
      if (parts.length >= 3 && parts[1] == 'image') {
        _saveAndDisplayImage(parts[0], imageData);
      }
    }
  } catch (e) {
    print('Error processing TCP data: $e');
  }
}

Future<void> _saveAndDisplayImage(String sender, Uint8List imageData) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final filename = 'received_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final file = File('${directory.path}/$filename');
    await file.writeAsBytes(imageData);
    
    setState(() {
      messages.add({
        "sender": sender,
        "type": "image",
        "path": file.path,
      });
    });
    await _saveMessages();
    _showNotification('New image from $sender');
  } catch (e) {
    print('Error saving received image: $e');
  }
}

@override
void dispose() {
  socket.close();
  _tcpServer?.close();
  _tcpClient?.close();
  _messageController.dispose();
  super.dispose();
}
@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: Text("Chat with ${widget.contact.name} (${widget.contact.ip})"),
      actions: [
        IconButton(
          icon: Icon(
            _tcpClient != null ? Icons.check_circle : Icons.wifi,
            color: _tcpClient != null ? Colors.green : Colors.grey,
          ),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(
                _tcpClient != null 
                  ? "TCP connected for large files"
                  : "Using UDP for messages"
              )),
            );
          },
        )
      ],
    ),
    body: Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final msg = messages[index];
              if (msg['type'] == 'image') {
                return ListTile(
                  title: Container(
                    height: 200,
                    width: 200,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Image.file(
                      File(msg['path']!),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.broken_image);
                      },
                    ),
                  ),
                  subtitle: Text(msg['sender']!),
                  trailing: msg['sender'] == myName ? const Icon(Icons.send) : null,
                );
              } else {
                return ListTile(
                  title: Text(msg['message']!),
                  subtitle: Text(msg['sender']!),
                  trailing: msg['sender'] == myName ? const Icon(Icons.send) : null,
                );
              }
            },
          ),
        ),
        if (_selectedImage != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Image.file(_selectedImage!, width: 80, height: 80),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _selectedImage = null;
                    });
                  },
                ),
              ],
            ),
          ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: "Type message...",
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.image, color: Colors.blue),
                        onPressed: _handleImageSelection,  // Fixed this line
                        tooltip: 'Attach Image',
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _sendMessage,
                  child: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}