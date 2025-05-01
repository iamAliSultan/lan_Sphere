import 'package:network_info_plus/network_info_plus.dart';

class NetworkUtils {
  static Future<String?> getLocalSubnet() async {
    final info = NetworkInfo();
    final ip = await info.getWifiIP();
    if (ip == null) return null;
    final parts = ip.split('.');
    parts.removeLast(); // Remove the host part (e.g. 192.168.1.12 => 192.168.1)
    return parts.join('.');
  }

  static Future<bool> isSameLAN(String targetIP) async {
    final subnet = await getLocalSubnet();
    if (subnet == null) return false;

    try {
      final parts = targetIP.split('.');
      final targetSubnet = parts.take(3).join('.');
      return targetSubnet == subnet;
    } catch (_) {
      return false;
    }
  }
}
