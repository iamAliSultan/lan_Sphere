import 'dart:io';
import 'dart:convert';

class SocketHandler {
  static const int chatPort = 4567;

  static Future<RawDatagramSocket> createListener(void Function(String, String) onMessageReceived) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, chatPort);
    
    socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = socket.receive();
        if (datagram != null) {
          final message = utf8.decode(datagram.data);
          final parts = message.split('|');
          if (parts.length == 2) {
            onMessageReceived(parts[0], parts[1]);
          }
        }
      }
    });
    
    return socket;
  }

  static Future<void> sendMessage(String ip, String senderName, String message) async {
    try {
      final destination = InternetAddress(ip);
      final encodedMessage = utf8.encode("$senderName|$message");
      
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.send(encodedMessage, destination, chatPort);
      socket.close();
    } catch (e) {
      print("Error sending message: $e");
    }
  }
}