import 'dart:io';
import 'dart:convert';

class LanContact {
  final String name;
  final String ip;

  LanContact({required this.name, required this.ip});
}

class NetworkDiscovery {
  static const int discoveryPort = 4568;
  
  static Future<List<LanContact>> discoverDevices(String myDeviceName) async {
    final List<LanContact> devices = [];
    final interfaces = await NetworkInterface.list();
    
    for (var interface in interfaces) {
      for (var address in interface.addresses) {
        if (!address.isLoopback && address.type == InternetAddressType.IPv4) {
          try {
            final socket = await RawDatagramSocket.bind(address, 0);
            final broadcast = _getBroadcastAddress(address);
            
            // Send discovery packet
            socket.broadcastEnabled = true;
            socket.send(utf8.encode("DISCOVER|$myDeviceName"), broadcast, discoveryPort);
            
            // Listen for responses
            socket.listen((event) {
              if (event == RawSocketEvent.read) {
                final datagram = socket.receive();
                if (datagram != null) {
                  final response = utf8.decode(datagram.data);
                  if (response.startsWith("RESPONSE|")) {
                    final parts = response.split('|');
                    if (parts.length == 3) {
                      final name = parts[1];
                      final ip = parts[2];
                      if (!devices.any((d) => d.ip == ip)) {
                        devices.add(LanContact(name: name, ip: ip));
                      }
                    }
                  }
                }
              }
            });
            
            await Future.delayed(Duration(seconds: 2));
            socket.close();
          } catch (e) {
            print("Discovery error: $e");
          }
        }
      }
    }
    
    return devices;
  }
  
  static InternetAddress _getBroadcastAddress(InternetAddress address) {
    final parts = address.address.split('.');
    return InternetAddress("${parts[0]}.${parts[1]}.${parts[2]}.255");
  }

  static Future<void> startDiscoveryResponder(String deviceName) async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort);
      
      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) {
            final message = utf8.decode(datagram.data);
            if (message.startsWith("DISCOVER|")) {
              // Get our IP address
              final localIp = datagram.address.address;
              // Send response back to sender
              socket.send(
                utf8.encode("RESPONSE|$deviceName|$localIp"),
                datagram.address,
                datagram.port
              );
            }
          }
        }
      });
    } catch (e) {
      print("Responder error: $e");
    }
  }
}