import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';
import 'new_chat_screen.dart';

class ChatScreen extends StatefulWidget {
  final LanContact contact;

  const ChatScreen({required this.contact});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, String>> messages = [];
  late String localIp;
  late String myName;
  static const int _tcpPort = 4568;
  ServerSocket? _tcpServer;
  Socket? _tcpClient;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;
  final Map<Socket, List<int>> _receiveBuffers = {};
  final Map<Socket, int> _expectedSizes = {};

  @override
  void initState() {
    super.initState();
    _getLocalIp();
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
        InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> _showNotification(String message) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'lan_chat_messages',
      'LAN Chat Messages',
      channelDescription: 'Notifications for incoming chat messages',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
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
        _receiveBuffers[client] = [];
        _expectedSizes[client] = 0;
        client.listen(
          (Uint8List data) {
            _handleIncomingTcpData(client, data);
          },
          onError: (error) {
            print('TCP Client error: $error');
            _receiveBuffers.remove(client);
            _expectedSizes.remove(client);
            client.close();
          },
          onDone: () {
            print('TCP Client disconnected');
            _receiveBuffers.remove(client);
            _expectedSizes.remove(client);
            client.close();
          },
        );
      });
      print('TCP server listening on port $_tcpPort');
    } catch (e) {
      print('Error starting TCP server: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to start TCP server: $e")),
      );
    }
  }

  void _sendMessage() async {
    final message = _messageController.text.trim();

    if (message.isEmpty && _selectedImage == null) return;

    if (message.isNotEmpty) {
      try {
        if (await _ensureTcpConnected()) {
          final messageBytes = utf8.encode(message);
          final header = '$myName|text|message|txt|${messageBytes.length}';
          _tcpClient!.add(utf8.encode(header));
          _tcpClient!.add([0]);
          _tcpClient!.add(messageBytes);
          _tcpClient!.flush();
          print('Sent text message: $message (${messageBytes.length} bytes)');

          setState(() {
            messages.add({
              "sender": myName,
              "message": message,
              "type": "text"
            });
          });
          await _saveMessages();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Message sent successfully")),
          );
        } else {
          throw Exception("TCP connection could not be established");
        }
      } catch (e) {
        print("Error sending text: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to send message: $e")),
        );
      }
    }

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Sending image...")),
      );
      final imageBytes = await image.readAsBytes();
      final extension = image.path.split('.').last.toLowerCase();
      const chunkSize = 64 * 1024; // 64KB chunks

      if (await _ensureTcpConnected()) {
        final header =
            '${myName}|image|${image.path.split('/').last}|$extension|${imageBytes.length}';
        _tcpClient!.add(utf8.encode(header));
        _tcpClient!.add([0]);

        for (int i = 0; i < imageBytes.length; i += chunkSize) {
          final end = (i + chunkSize < imageBytes.length)
              ? i + chunkSize
              : imageBytes.length;
          _tcpClient!.add(imageBytes.sublist(i, end));
          await Future.delayed(Duration(milliseconds: 20));
        }
        _tcpClient!.flush();
        print('Sent image: ${image.path} (${imageBytes.length} bytes)');

        setState(() {
          messages.add({
            "sender": myName,
            "type": "image",
            "path": image.path,
          });
        });
        await _saveMessages();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Image sent successfully")),
        );
      } else {
        throw Exception("TCP connection could not be established");
      }
    } catch (e) {
      print("Error sending image: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to send image: $e")),
      );
    }
  }

  Future<bool> _ensureTcpConnected() async {
    if (_tcpClient != null) return true;

    for (int i = 0; i < 3; i++) {
      try {
        print(
            'Attempting TCP connection to ${widget.contact.ip}:$_tcpPort (Attempt ${i + 1})');
        _tcpClient = await Socket.connect(
          widget.contact.ip,
          _tcpPort,
          timeout: Duration(seconds: 10),
        );

        _tcpClient!.listen(
          (Uint8List data) {
            _handleIncomingTcpData(_tcpClient!, data);
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
        print('TCP connection established');
        return true;
      } catch (e) {
        print('TCP connection attempt ${i + 1} failed: $e');
        if (i == 2) return false;
        await Future.delayed(Duration(seconds: 1));
      }
    }
    return false;
  }

  void _handleIncomingTcpData(Socket client, Uint8List data) {
    try {
      _receiveBuffers[client]!.addAll(data);

      while (_receiveBuffers[client]!.contains(0)) {
        final headerEnd = _receiveBuffers[client]!.indexOf(0);
        final header = utf8.decode(_receiveBuffers[client]!.sublist(0, headerEnd));
        final parts = header.split('|');

        if (parts.length >= 5) {
          final sender = parts[0];
          final type = parts[1];
          final filename = parts[2];
          final extension = parts[3];
          final size = int.parse(parts[4]);

          final payloadStart = headerEnd + 1;
          final currentBuffer = _receiveBuffers[client]!;

          if (currentBuffer.length - payloadStart >= size) {
            final payload = currentBuffer.sublist(payloadStart, payloadStart + size);
            _receiveBuffers[client] = currentBuffer.sublist(payloadStart + size);

            if (type == 'text' && sender != myName) {
              final message = utf8.decode(payload);
              print('Received text message: $message (${payload.length} bytes, header: $header)');
              setState(() {
                messages.add({
                  "sender": sender,
                  "message": message,
                  "type": "text"
                });
              });
              _showNotification(message);
              _saveMessages();
            } else if (type == 'image' && sender != myName) {
              print('Received image: $filename (${payload.length} bytes, header: $header)');
              _saveAndDisplayImage(sender, Uint8List.fromList(payload), extension);
            }
          } else {
            _expectedSizes[client] = size;
            break; // Wait for more data
          }
        } else {
          print('Invalid header received: $header');
          _receiveBuffers[client] = [];
          break; // Invalid header
        }
      }
    } catch (e) {
      print('Error processing TCP data: $e');
      _receiveBuffers[client] = [];
    }
  }

  Future<void> _saveAndDisplayImage(
      String sender, Uint8List imageData, String extension) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final filename =
          'received_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final file = File('${directory.path}/$filename');
      await file.writeAsBytes(imageData);

      print('Saved image: ${file.path} (${imageData.length} bytes)');

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
    _tcpServer?.close();
    _tcpClient?.close();
    _messageController.dispose();
    _receiveBuffers.clear();
    _expectedSizes.clear();
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
              _tcpClient != null ? Icons.check_circle : Icons.wifi_off,
              color: _tcpClient != null ? Colors.green : Colors.red,
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(_tcpClient != null
                        ? "TCP connected for messages and images"
                        : "TCP not connected")),
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
                    trailing:
                        msg['sender'] == myName ? const Icon(Icons.send) : null,
                  );
                } else {
                  return ListTile(
                    title: Text(msg['message']!),
                    subtitle: Text(msg['sender']!),
                    trailing:
                        msg['sender'] == myName ? const Icon(Icons.send) : null,
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
                        onPressed: _handleImageSelection,
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