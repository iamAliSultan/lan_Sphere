import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
class BackgroundService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  static ServerSocket? _tcpServer;
  static const int _tcpPort = 4568;
  static String? _localIp;
  static String? _myName;
  static final Map<Socket, List<int>> _receiveBuffers = {};
  static final Map<Socket, int> _expectedSizes = {};

  @pragma('vm:entry-point')
  static Future<void> initializeService() async {
    if (Platform.isAndroid) {
      final status = await Permission.notification.request();
      if (!status.isGranted) {
        debugPrint('Notification permission denied');
      }
      // Request ignore battery optimizations
      final batteryStatus = await Permission.ignoreBatteryOptimizations.request();
      if (!batteryStatus.isGranted) {
        debugPrint('Battery optimization permission denied');
      }
    }

    await _initNotifications();

    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'lan_chat_service',
        initialNotificationTitle: 'LANsphere Running',
        initialNotificationContent: 'Your chat service is active',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.connectedDevice],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    try {
      debugPrint('Starting BackgroundService in foreground mode');
      await service.startService();
    } catch (e) {
      debugPrint('Failed to start foreground service: $e');
      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onStart,
          autoStart: true,
          isForegroundMode: false,
        ),
        iosConfiguration: IosConfiguration(
          autoStart: true,
          onForeground: onStart,
          onBackground: onIosBackground,
        ),
      );
      debugPrint('Starting BackgroundService in non-foreground mode');
      await service.startService();
    }
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();

    if (service is AndroidServiceInstance) {
      try {
        // Delay to ensure channel is created
        await Future.delayed(const Duration(milliseconds: 500));
        await service.setAsForegroundService();
        service.setForegroundNotificationInfo(
          title: 'LANsphere Running',
          content: 'Your chat service is active',
        );
      } catch (e) {
        debugPrint('Failed to set foreground notification: $e');
      }
    }

    await _getLocalIp();
    await _startTcpServer();

    service.on('stopService').listen((event) {
      _tcpServer?.close();
      service.stopSelf();
    });
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    return true;
  }

  @pragma('vm:entry-point')
  static Future<void> _initNotifications() async {
    const androidSettings = AndroidInitializationSettings('ic_launcher'); // Use existing ic_launcher
    try {
      await _notificationsPlugin.initialize(
        const InitializationSettings(android: androidSettings),
        onDidReceiveNotificationResponse: (details) async {
          if (details.payload != null) {
            final parts = details.payload!.split('|');
            if (parts.length >= 2) {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('pending_notification', details.payload!);
              debugPrint('Notification payload stored: ${details.payload}');
            }
          }
        },
      );
    } catch (e) {
      debugPrint('Failed to initialize notifications: $e');
    }

    const channel = AndroidNotificationChannel(
      'lan_chat_service',
      'LANsphere Service',
      description: 'Notifications for LANsphere background service and messages',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      ledColor: Colors.blue,
    );
    try {
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
      debugPrint('Notification channel created: lan_chat_service');
    } catch (e) {
      debugPrint('Failed to create notification channel: $e');
    }
  }

  @pragma('vm:entry-point')
  static Future<void> _showNotification(String title, String message, String senderIp, String senderName) async {
    const androidDetails = AndroidNotificationDetails(
      'lan_chat_service',
      'LANsphere Service',
      channelDescription: 'Notifications for incoming chat messages and calls',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      ledColor: Colors.blue,
      ledOnMs: 1000,
      ledOffMs: 500,
    );
    try {
      await _notificationsPlugin.show(
        senderIp.hashCode,
        title,
        message,
        const NotificationDetails(android: androidDetails),
        payload: '$senderIp|$senderName',
      );
      debugPrint('Notification shown: $title');
    } catch (e) {
      debugPrint('Failed to show notification: $e');
    }
  }

  @pragma('vm:entry-point')
  static Future<void> _getLocalIp() async {
    try {
      final info = NetworkInfo();
      _localIp = await info.getWifiIP();
      if (_localIp != null && _localIp!.isNotEmpty) {
        _myName = _localIp;
        debugPrint('Local IP from WiFi: $_localIp');
      } else {
        final interfaces = await NetworkInterface.list(includeLinkLocal: true);
        for (var interface in interfaces) {
          for (var addr in interface.addresses) {
            if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
              _localIp = addr.address;
              _myName = _localIp;
              debugPrint('Local IP from interface: $_localIp');
              return;
            }
          }
        }
        debugPrint('No valid IPv4 address found');
      }
    } catch (e) {
      debugPrint('Failed to get local IP: $e');
    }
  }

  @pragma('vm:entry-point')
  static Future<void> _startTcpServer() async {
    try {
      _tcpServer = await ServerSocket.bind(InternetAddress.anyIPv4, _tcpPort);
      debugPrint('TCP server started on port $_tcpPort');
      _tcpServer!.listen((client) {
        _receiveBuffers[client] = [];
        _expectedSizes[client] = 0;
        client.listen(
          (data) => _handleIncomingTcpData(client, data),
          onError: (error) {
            _receiveBuffers.remove(client);
            _expectedSizes.remove(client);
            client.close();
            debugPrint('Client error: $error');
          },
          onDone: () {
            _receiveBuffers.remove(client);
            _expectedSizes.remove(client);
            client.close();
            debugPrint('Client disconnected');
          },
        );
      });
    } catch (e) {
      debugPrint('TCP Server Error: $e');
    }
  }

  @pragma('vm:entry-point')
  static void _handleIncomingTcpData(Socket client, List<int> data) async {
    _receiveBuffers[client]!.addAll(data);
    while (_receiveBuffers[client]!.contains(0)) {
      final headerEnd = _receiveBuffers[client]!.indexOf(0);
      final header = utf8.decode(_receiveBuffers[client]!.sublist(0, headerEnd));
      final parts = header.split('|');
      if (parts.length >= 2) {
        final sender = parts[0];
        final type = parts[1];
        final timestamp = DateTime.now().toIso8601String();

        if (type == 'call_offer' && parts.length >= 4 && sender != _myName) {
          final isVideo = parts[3] == 'true';
          await _showNotification('Incoming ${isVideo ? "Video" : "Voice"} Call', 'From $sender', sender, sender);
          _receiveBuffers[client] = _receiveBuffers[client]!.sublist(headerEnd + 1);
        } else if (parts.length >= 5) {
          final filename = parts[2];
          final extension = parts[3];
          final size = int.parse(parts[4]);
          final payloadStart = headerEnd + 1;
          final currentBuffer = _receiveBuffers[client]!;
          if (currentBuffer.length - payloadStart >= size) {
            final payload = currentBuffer.sublist(payloadStart, payloadStart + size);
            _receiveBuffers[client] = currentBuffer.sublist(payloadStart + size);
            if (type == 'text' && sender != _myName) {
              final message = utf8.decode(payload);
              await _saveMessage(sender, message, 'text', timestamp);
              await _showNotification('New Message from $sender', message, sender, sender);
            } else if (sender != _myName) {
              await _saveMedia(sender, payload, extension, type, filename, timestamp);
              await _showNotification('New $type from $sender', 'Received a $type file', sender, sender);
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

  @pragma('vm:entry-point')
  static Future<void> _saveMessage(String sender, String message, String type, String timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'chat_${sender.replaceAll('.', '_')}';
    final messages = prefs.getStringList(key) ?? [];
    messages.add('$sender|$type|$message|$timestamp');
    await prefs.setStringList(key, messages);
    debugPrint('Message saved for $sender');
  }

  @pragma('vm:entry-point')
  static Future<void> _saveMedia(String sender, List<int> data, String extension, String type, String filename, String timestamp) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$filename');
    await file.writeAsBytes(data);
    if (await file.exists()) {
      final prefs = await SharedPreferences.getInstance();
      final key = 'chat_${sender.replaceAll('.', '_')}';
      final messages = prefs.getStringList(key) ?? [];
      messages.add('$sender|$type|${file.path}|$timestamp');
      await prefs.setStringList(key, messages);
      debugPrint('Media saved: ${file.path}');
    }
  }
}