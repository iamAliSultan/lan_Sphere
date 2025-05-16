import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

@pragma('vm:entry-point')
class ChatManager {
  static final ChatManager _instance = ChatManager._internal();
  factory ChatManager() => _instance;
  ChatManager._internal();

  static const int _tcpPort = 4568;
  ServerSocket? _tcpServer;
  final Map<String, Socket> _tcpClients = {};
  final Map<Socket, List<int>> _receiveBuffers = {};
  final Map<Socket, int> _expectedSizes = {};
  String? localIp;
  String? myName;
  String? _currentCallIp;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  final ImagePicker picker = ImagePicker();
  final Map<String, VideoPlayerController> _videoControllers = {};
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isInitialized = false;
  final Map<String, String> _contactNames = {};
  // Background service
  final _backgroundService = FlutterBackgroundService();
  // Add a public getter for backgroundService
  FlutterBackgroundService get backgroundService => _backgroundService;

  // Call-related
  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  MediaStream? remoteStream;
  RTCVideoRenderer localRenderer = RTCVideoRenderer();
  RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  bool _inCall = false;
  bool _isVideoCall = false;
  bool get isVideoCall => _isVideoCall;
  String? callStatus;

  // Callbacks
  Function(Map<String, dynamic>, String)? _onNewMessage;
  Function(String, String, {String? sdpJson, bool? isVideo, Map<String, dynamic>? candidateMap})? _onCallEvent;

  void setOnNewMessageCallback(Function(Map<String, dynamic>, String) callback) {
    _onNewMessage = callback;
  }

  void setOnCallEventCallback(Function(String, String, {String? sdpJson, bool? isVideo, Map<String, dynamic>? candidateMap}) callback) {
    _onCallEvent = callback;
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    await initNotifications();
    await _getLocalIp();
    await _setupBackgroundService();
    await _startTcpServer();
    await _initWebRTC();
  }

  Future<void> _initWebRTC() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
  }

  Future<void> initNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );
    const channel = AndroidNotificationChannel(
      'lan_chat_messages',
      'LAN Chat Messages',
      description: 'Notifications for incoming chat messages',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      ledColor: Colors.blue,
    );
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    print('Notification channel initialized'); // Debug log
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload != null ? jsonDecode(response.payload!) : {};
    final senderIp = payload['senderIp'];
    if (senderIp == null) return;

    if (response.actionId == 'reply_action' && response.input != null) {
      sendMessageFromNotification(senderIp, response.input!);
    } else if (response.actionId == 'accept_call' && payload['isCall'] == true) {
      final sdpJson = payload['sdpJson'];
      final isVideoCall = payload['isVideoCall'] == true;
      if (sdpJson != null && _onCallEvent != null) {
        _onCallEvent!('call_offer', senderIp, sdpJson: sdpJson, isVideo: isVideoCall);
      }
    } else if (response.actionId == 'reject_call' && payload['isCall'] == true) {
      if (_onCallEvent != null) _onCallEvent!('call_end', senderIp);
    } else if (response.actionId == 'play_voice_note' && payload['type'] == 'voice') {
      final path = payload['path'];
      if (path != null && File(path).existsSync()) {
        _audioPlayer.play(DeviceFileSource(path));
      }
    }
  }

  Future<void> _getLocalIp() async {
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
  }

  Future<void> _setupBackgroundService() async {
    const notificationChannel = AndroidNotificationChannel(
      'lan_chat_background',
      'LAN Chat Service',
      description: 'Keeps LAN connections active',
      importance: Importance.low,
    );
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(notificationChannel);

    await _backgroundService.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStartBackgroundService,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: notificationChannel.id,
        initialNotificationTitle: 'LAN Chat Running',
        initialNotificationContent: 'Maintaining connections',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: _onStartBackgroundService,
        onBackground: _onIosBackground,
      ),
    );
    if (!(await _backgroundService.isRunning())) {
      await _backgroundService.startService();
    }
  }

  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async => true;

  @pragma('vm:entry-point')
  static void _onStartBackgroundService(ServiceInstance service) async {
    if (service is AndroidServiceInstance) {
      service.on('setAsForeground').listen((event) => service.setAsForegroundService());
      service.on('setAsBackground').listen((event) => service.setAsBackgroundService());
      service.on('stopService').listen((event) => service.stopSelf());
    }
    final chatManager = ChatManager();
    if (!chatManager._isInitialized) {
      await chatManager.initialize();
    }
    while (true) {
      if (chatManager._tcpServer == null) {
        await chatManager._startTcpServer();
      }
      await Future.delayed(const Duration(seconds: 30));
    }
  }

  Future<void> _startTcpServer() async {
    if (_tcpServer != null) return;
    try {
      _tcpServer = await ServerSocket.bind(InternetAddress.anyIPv4, _tcpPort, shared: true);
      _tcpServer!.listen((client) {
        _receiveBuffers[client] = [];
        _expectedSizes[client] = 0;
        client.listen(
          (data) => _handleIncomingTcpData(client, data),
          onError: (error) {
            _cleanupClient(client, error);
          },
          onDone: () {
            _cleanupClient(client);
          },
        );
      });
    } catch (e) {
      print('Failed to start TCP server: $e');
      _tcpServer = null;
    }
  }

  Future<Socket?> getTcpClient(String ip) async {
    if (_tcpClients.containsKey(ip) && _tcpClients[ip]!.remoteAddress.address == ip) {
      return _tcpClients[ip];
    }
    try {
      final client = await Socket.connect(ip, _tcpPort, timeout: const Duration(seconds: 10));
      _tcpClients[ip] = client;
      client.listen(
        (data) => _handleIncomingTcpData(client, data),
        onError: (error) => _cleanupClient(client, error),
        onDone: () => _cleanupClient(client),
      );
      return client;
    } catch (e) {
      print('Failed to connect to $ip: $e');
      _tcpClients.remove(ip);
      return null;
    }
  }

  void _cleanupClient(Socket client, [dynamic error]) {
    final ip = client.remoteAddress.address;
    print('Client disconnected from $ip${error != null ? ': $error' : ''}');
    _receiveBuffers.remove(client);
    _expectedSizes.remove(client);
    _tcpClients.remove(ip);
    client.close();
  }

  void _handleIncomingTcpData(Socket client, Uint8List data) {
    _receiveBuffers[client]!.addAll(data);
    while (_receiveBuffers[client]!.contains(0)) {
      final headerEnd = _receiveBuffers[client]!.indexOf(0);
      final header = utf8.decode(_receiveBuffers[client]!.sublist(0, headerEnd));
      final parts = header.split('|');
      if (parts.length >= 2) {
        final sender = parts[0];
        final type = parts[1];
        final timestamp = DateTime.now().toIso8601String();

        if (type == 'call_offer' && parts.length >= 4 && sender != myName) {
          final sdpJson = parts[2];
          final isVideo = parts[3] == 'true';
          print('Received call offer: isVideo=$isVideo, sender=$sender'); // Debug log
          if (!isVideo) { // Only trigger notification for voice calls
            final contactName = getContactName(client.remoteAddress.address);
            print('Triggering voice call notification for $contactName'); // Debug log
            showNotification(
              contactName: contactName,
              isCall: true,
              isVideoCall: false,
              senderIp: client.remoteAddress.address,
              sdpJson: sdpJson,
            );
          }
          if (_onCallEvent != null) {
            _onCallEvent!('call_offer', client.remoteAddress.address, sdpJson: sdpJson, isVideo: isVideo);
          }
          _receiveBuffers[client] = _receiveBuffers[client]!.sublist(headerEnd + 1);
        } else if (type == 'call_answer' && parts.length >= 3 && sender != myName) {
          final sdpMap = jsonDecode(parts[2]);
          peerConnection?.setRemoteDescription(RTCSessionDescription(sdpMap['sdp'], sdpMap['type']));
          if (_onCallEvent != null) {
            _onCallEvent!('call_answer', client.remoteAddress.address);
          }
          _receiveBuffers[client] = _receiveBuffers[client]!.sublist(headerEnd + 1);
        } else if (type == 'ice_candidate' && parts.length >= 3 && sender != myName) {
          final candidateMap = jsonDecode(parts[2]);
          peerConnection?.addCandidate(RTCIceCandidate(candidateMap['candidate'], candidateMap['sdpMid'], candidateMap['sdpMLineIndex']));
          if (_onCallEvent != null) {
            _onCallEvent!('ice_candidate', client.remoteAddress.address, candidateMap: candidateMap);
          }
          _receiveBuffers[client] = _receiveBuffers[client]!.sublist(headerEnd + 1);
        } else if (type == 'call_end' && sender != myName) {
          endCall();
          if (_onCallEvent != null) {
            _onCallEvent!('call_end', client.remoteAddress.address);
          }
          _receiveBuffers[client] = _receiveBuffers[client]!.sublist(headerEnd + 1);
        } else if (parts.length >= 5 && sender != myName) {
          final extension = parts[3];
          final size = int.parse(parts[4]);
          final payloadStart = headerEnd + 1;
          final currentBuffer = _receiveBuffers[client]!;
          if (currentBuffer.length - payloadStart >= size) {
            final payload = currentBuffer.sublist(payloadStart, payloadStart + size);
            _receiveBuffers[client] = currentBuffer.sublist(payloadStart + size);
            if (type == 'text') {
              final message = utf8.decode(payload);
              final msg = {"sender": sender, "message": message, "type": "text", "timestamp": timestamp};
              print('Received text message from $sender: $message'); // Debug log
              _queueMessage(msg, client.remoteAddress.address); // Queue only if incoming
            } else {
              _saveAndDisplayMedia(sender, Uint8List.fromList(payload), extension, type, timestamp, client.remoteAddress.address);
            }
          } else {
            _expectedSizes[client] = size;
            break;
          }
        } else {
          _receiveBuffers[client] = [];
          break;
        }
      } else {
        _receiveBuffers[client] = [];
        break;
      }
    }
  }

  // Updated method to queue messages only for incoming messages
  Future<void> _queueMessage(Map<String, dynamic> message, String senderIp) async {
    // Only queue and notify if the message is from someone else (incoming)
    if (message['sender'] != myName) {
      final prefs = await SharedPreferences.getInstance();
      final key = 'queued_messages_${senderIp.replaceAll('.', '_')}';
      final encoded = prefs.getStringList(key) ?? [];
      final entry = message['type'] == 'image' || message['type'] == 'video' || message['type'] == 'file' || message['type'] == 'voice'
          ? "${message['sender']}|${message['type']}|${message['path']}|${message['timestamp']}"
          : "${message['sender']}|text|${message['message']}|${message['timestamp']}";
      encoded.add(entry);
      await prefs.setStringList(key, encoded);
      print('Queuing message from ${message['sender']} of type ${message['type']}'); // Debug log
      showNotification(
        contactName: message['sender'], // Use sender as contact name for simplicity; update with getContactName if needed
        message: message['message'] ?? 'New ${message['type']}',
        senderIp: senderIp,
        type: message['type'],
      );
    }
    // Always notify the UI if callback is set (for both incoming and outgoing)
    if (_onNewMessage != null) {
      _onNewMessage!(message, senderIp);
    }
  }

  // Load queued messages when ChatScreen initializes
  Future<List<Map<String, dynamic>>> loadQueuedMessages(String contactIp) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'queued_messages_${contactIp.replaceAll('.', '_')}';
    final encoded = prefs.getStringList(key) ?? [];
    final messages = encoded.map((e) {
      final parts = e.split('|');
      if (parts.length >= 4 && (parts[1] == 'image' || parts[1] == 'video' || parts[1] == 'file' || parts[1] == 'voice')) {
        return {"sender": parts[0], "type": parts[1], "path": parts[2], "timestamp": parts[3]};
      }
      return {"sender": parts[0], "type": "text", "message": parts[2], "timestamp": parts[3]};
    }).toList();
    // Clear the queue after loading
    await prefs.remove(key);
    return messages;
  }

  Future<void> saveMessages(String contactIp, Map<String, dynamic> message) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'chat_${contactIp.replaceAll('.', '_')}';
    final encoded = prefs.getStringList(key) ?? [];
    final entry = message['type'] == 'image' || message['type'] == 'video' || message['type'] == 'file' || message['type'] == 'voice'
        ? "${message['sender']}|${message['type']}|${message['path']}|${message['timestamp']}"
        : "${message['sender']}|text|${message['message']}|${message['timestamp']}";
    encoded.add(entry);
    await prefs.setStringList(key, encoded);
  }

  Future<void> loadMessages(String contactIp) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'chat_${contactIp.replaceAll('.', '_')}';
    final encoded = prefs.getStringList(key) ?? [];
    final loaded = encoded.map((e) {
      final parts = e.split('|');
      if (parts.length >= 4 && (parts[1] == 'image' || parts[1] == 'video' || parts[1] == 'file' || parts[1] == 'voice')) {
        return {"sender": parts[0], "type": parts[1], "path": parts[2], "timestamp": parts[3]};
      }
      return {"sender": parts[0], "type": "text", "message": parts[2], "timestamp": parts[3]};
    }).toList();
    for (var msg in loaded.where((m) => m['type'] == 'video' && m['path'] != null)) {
      final file = File(msg['path'] ?? '');
      if (await file.exists()) {
        final controller = VideoPlayerController.file(file);
        _videoControllers[msg['path']!] = controller;
        await controller.initialize();
        controller.setLooping(false);
      }
    }
  }

  Future<void> _saveAndDisplayMedia(String sender, Uint8List data, String extension, String type, String timestamp, String contactIp) async {
    final directory = await getApplicationDocumentsDirectory();
    final filename = 'received_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final file = File('${directory.path}/$filename');
    await file.writeAsBytes(data);
    if (await file.exists()) {
      final msg = {"sender": sender, "type": type, "path": file.path, "timestamp": timestamp};
      print('Received media of type $type from $sender'); // Debug log
      _queueMessage(msg, contactIp); // Queue only if incoming
    }
  }

  Future<void> sendMessageFromNotification(String senderIp, String message) async {
    if (message.trim().isEmpty) return;
    final timestamp = DateTime.now().toIso8601String();
    final client = await getTcpClient(senderIp);
    if (client != null) {
      final messageBytes = utf8.encode(message);
      final header = '$myName|text|message|txt|${messageBytes.length}';
      client.add(utf8.encode(header));
      client.add([0]);
      client.add(messageBytes);
      await client.flush();
      final msg = {"sender": myName, "message": message, "type": "text", "timestamp": timestamp};
      _queueMessage(msg, senderIp); // No notification for sender
    }
  }

  Future<void> showNotification({
    required String contactName,
    String? message,
    String? type,
    bool isCall = false,
    bool isVideoCall = false,
    required String senderIp,
    String? path,
    String? sdpJson,
  }) async {
    List<AndroidNotificationAction> actions = [];
    String title;
    String body;

    if (isCall && !isVideoCall) {
      title = 'Incoming Voice Call';
      body = 'From $contactName';
      actions = [
        AndroidNotificationAction(
          'accept_call',
          'Accept',
          showsUserInterface: false,
        ),
        AndroidNotificationAction(
          'reject_call',
          'Reject',
          showsUserInterface: false,
        ),
      ];
    } else if (type != null) {
      title = '$contactName';
      body = message ?? 'New $type';
      if (type == 'voice') {
        actions = [
          AndroidNotificationAction(
            'play_voice_note',
            'Play Voice Note',
            showsUserInterface: false,
          ),
        ];
      } else {
        actions = [
          AndroidNotificationAction(
            'reply_action',
            'Reply',
            allowGeneratedReplies: true,
            showsUserInterface: false,
          ),
        ];
      }
    } else {
      return; // Skip if no valid notification type
    }

    final androidDetails = AndroidNotificationDetails(
      'lan_chat_messages',
      'LAN Chat Messages',
      channelDescription: 'Notifications for incoming chat messages',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      color: Colors.blue,
      ledColor: Colors.blue,
      ledOnMs: 1000,
      ledOffMs: 500,
      actions: actions,
    );

    print('Showing notification: title=$title, body=$body'); // Debug log
    await flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      NotificationDetails(android: androidDetails),
      payload: jsonEncode({
        'senderIp': senderIp,
        'isCall': isCall,
        'isVideoCall': isVideoCall,
        'type': type,
        'path': path,
        'sdpJson': sdpJson,
      }),
    );
  }

  Future<void> sendMessage(String receiverIp, String message, {String type = 'text'}) async {
    final timestamp = DateTime.now().toIso8601String();
    final client = await getTcpClient(receiverIp);
    if (client == null) return;

    if (type == 'text' && message.isNotEmpty) {
      final messageBytes = utf8.encode(message);
      final header = '$myName|text|message|txt|${messageBytes.length}';
      client.add(utf8.encode(header));
      client.add([0]);
      client.add(messageBytes);
      await client.flush();
      final msg = {"sender": myName, "message": message, "type": "text", "timestamp": timestamp};
      _queueMessage(msg, receiverIp); // No notification for sender
    }
  }

  Future<void> sendImage(String receiverIp, File image) async {
    final timestamp = DateTime.now().toIso8601String();
    final imageBytes = await image.readAsBytes();
    final extension = image.path.split('.').last.toLowerCase();
    const chunkSize = 64 * 1024;
    final client = await getTcpClient(receiverIp);
    if (client != null) {
      final header = '$myName|image|${image.path.split('/').last}|$extension|${imageBytes.length}';
      client.add(utf8.encode(header));
      client.add([0]);
      for (int i = 0; i < imageBytes.length; i += chunkSize) {
        final end = (i + chunkSize < imageBytes.length) ? i + chunkSize : imageBytes.length;
        client.add(imageBytes.sublist(i, end));
        await Future.delayed(const Duration(milliseconds: 20));
      }
      await client.flush();
      final msg = {"sender": myName, "type": "image", "path": image.path, "timestamp": timestamp};
      _queueMessage(msg, receiverIp);
    }
  }

  Future<void> sendVideo(String receiverIp, File video) async {
    final timestamp = DateTime.now().toIso8601String();
    final videoBytes = await video.readAsBytes();
    final extension = video.path.split('.').last.toLowerCase();
    const chunkSize = 64 * 1024;
    final client = await getTcpClient(receiverIp);
    if (client != null) {
      final header = '$myName|video|${video.path.split('/').last}|$extension|${videoBytes.length}';
      client.add(utf8.encode(header));
      client.add([0]);
      for (int i = 0; i < videoBytes.length; i += chunkSize) {
        final end = (i + chunkSize < videoBytes.length) ? i + chunkSize : videoBytes.length;
        client.add(videoBytes.sublist(i, end));
        await Future.delayed(const Duration(milliseconds: 20));
      }
      await client.flush();
      final msg = {"sender": myName, "type": "video", "path": video.path, "timestamp": timestamp};
      _queueMessage(msg, receiverIp);
      final controller = VideoPlayerController.file(video);
      _videoControllers[video.path] = controller;
      await controller.initialize();
      controller.setLooping(false);
    }
  }

  Future<void> sendFile(String receiverIp, File file) async {
    final timestamp = DateTime.now().toIso8601String();
    final fileBytes = await file.readAsBytes();
    final extension = file.path.split('.').last.toLowerCase();
    const chunkSize = 64 * 1024;
    final client = await getTcpClient(receiverIp);
    if (client != null) {
      final header = '$myName|file|${file.path.split('/').last}|$extension|${fileBytes.length}';
      client.add(utf8.encode(header));
      client.add([0]);
      for (int i = 0; i < fileBytes.length; i += chunkSize) {
        final end = (i + chunkSize < fileBytes.length) ? i + chunkSize : fileBytes.length;
        client.add(fileBytes.sublist(i, end));
        await Future.delayed(const Duration(milliseconds: 20));
      }
      await client.flush();
      final msg = {"sender": myName, "type": "file", "path": file.path, "timestamp": timestamp};
      _queueMessage(msg, receiverIp);
    }
  }

  Future<void> sendVoiceNote(String receiverIp, File voiceNote) async {
    final timestamp = DateTime.now().toIso8601String();
    final voiceBytes = await voiceNote.readAsBytes();
    final extension = voiceNote.path.split('.').last.toLowerCase();
    const chunkSize = 64 * 1024;
    final client = await getTcpClient(receiverIp);
    if (client != null) {
      final header = '$myName|voice|${voiceNote.path.split('/').last}|$extension|${voiceBytes.length}';
      client.add(utf8.encode(header));
      client.add([0]);
      for (int i = 0; i < voiceBytes.length; i += chunkSize) {
        final end = (i + chunkSize < voiceBytes.length) ? i + chunkSize : voiceBytes.length;
        client.add(voiceBytes.sublist(i, end));
        await Future.delayed(const Duration(milliseconds: 20));
      }
      await client.flush();
      final msg = {"sender": myName, "type": "voice", "path": voiceNote.path, "timestamp": timestamp};
      _queueMessage(msg, receiverIp);
    }
  }

  Future<void> startCall(String receiverIp, bool isVideo) async {
    _currentCallIp = receiverIp;
    if (_inCall) return;
    _isVideoCall = isVideo;
    _inCall = true;
    callStatus = 'Ringing';
    await _createPeerConnection();
    final mediaConstraints = {
      'audio': {'echoCancellation': true, 'noiseSuppression': true},
      'video': isVideo ? {'facingMode': 'user'} : false
    };
    localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    localStream!.getTracks().forEach((track) {
      track.enabled = true;
      peerConnection!.addTrack(track, localStream!);
    });
    localRenderer.srcObject = localStream;
    final offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);
    final client = await getTcpClient(receiverIp);
    if (client != null) {
      final message = '$myName|call_offer|${jsonEncode(offer.toMap())}|$_isVideoCall';
      client.add(utf8.encode(message));
      client.add([0]);
      await client.flush();
    } else {
      endCall();
    }
  }

  Future<void> answerCall(String receiverIp, String sdpJson, bool isVideo) async {
    _currentCallIp = receiverIp;
    if (_inCall) return;
    _isVideoCall = isVideo;
    _inCall = true;
    callStatus = 'Connecting';
    await _createPeerConnection();
    final mediaConstraints = {
      'audio': {'echoCancellation': true, 'noiseSuppression': true},
      'video': isVideo ? {'facingMode': 'user'} : false
    };
    localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    localStream!.getTracks().forEach((track) {
      track.enabled = true;
      peerConnection!.addTrack(track, localStream!);
    });
    localRenderer.srcObject = localStream;
    final sdpMap = jsonDecode(sdpJson);
    await peerConnection!.setRemoteDescription(RTCSessionDescription(sdpMap['sdp'], sdpMap['type']));
    final answer = await peerConnection!.createAnswer();
    await peerConnection!.setLocalDescription(answer);
    final client = await getTcpClient(receiverIp);
    if (client != null) {
      final message = '$myName|call_answer|${jsonEncode(answer.toMap())}';
      client.add(utf8.encode(message));
      client.add([0]);
      await client.flush();
    }
    callStatus = 'Connected';
  }

  Future<void> endCall() async {
    if (!_inCall || _currentCallIp == null) return;
    final client = _tcpClients[_currentCallIp];
    if (client != null) {
      final message = '$myName|call_end|';
      client.add(utf8.encode(message));
      client.add([0]);
      await client.flush();
    }
    if (_onCallEvent != null) {
      _onCallEvent!('call_end', _currentCallIp!);
    }
    localStream?.getTracks().forEach((track) => track.stop());
    localStream?.dispose();
    remoteStream?.dispose();
    await peerConnection?.close();
    peerConnection = null;
    localStream = null;
    remoteStream = null;
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    _inCall = false;
    _isVideoCall = false;
    callStatus = null;
    _currentCallIp = null;
  }

  Future<void> _createPeerConnection() async {
    peerConnection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan'
    });
    peerConnection!.onIceCandidate = (candidate) {
      _tcpClients.values.forEach((client) {
        final message = '$myName|ice_candidate|${jsonEncode(candidate.toMap())}';
        client.add(utf8.encode(message));
        client.add([0]);
        client.flush();
      });
    };
    peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteStream = event.streams[0];
        remoteRenderer.srcObject = remoteStream;
      }
    };
    peerConnection!.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected || state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        endCall();
      }
    };
  }

  void setContactName(String ip, String name) => _contactNames[ip] = name;
  String getContactName(String ip) => _contactNames[ip] ?? ip.split('.').last;

  void close() {
    _tcpServer?.close();
    _tcpClients.values.forEach((client) => client.close());
    _tcpServer = null;
    _tcpClients.clear();
    _receiveBuffers.clear();
    _expectedSizes.clear();
    _videoControllers.values.forEach((controller) => controller.dispose());
    _videoControllers.clear();
    _audioPlayer.dispose();
    localRenderer.dispose();
    remoteRenderer.dispose();
    _backgroundService.invoke('stopService');
    _isInitialized = false;
    callStatus = null;
    _inCall = false;
    _isVideoCall = false;
    localStream?.dispose();
    remoteStream?.dispose();
    peerConnection?.close();
    _currentCallIp = null;
  }
}