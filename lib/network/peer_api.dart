import 'dart:convert';
import 'package:http/http.dart' as http;

class PeerAPI {
  final String ip;
  final int port;

  PeerAPI(this.ip, {this.port = 8080});

  Future<bool> check() async {
    try {
      final r = await http.get(Uri.http('$ip:$port', '/health'))
          .timeout(const Duration(seconds: 3));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getData() async {
    try {
      final r = await http.get(Uri.http('$ip:$port', '/data'))
          .timeout(const Duration(seconds: 5));
      if (r.statusCode == 200) return jsonDecode(r.body);
    } catch (_) {}
    return null;
  }

  Future<bool> sendData(Map<String, dynamic> data) async {
    try {
      final r = await http.post(Uri.http('$ip:$port', '/data'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(data));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
