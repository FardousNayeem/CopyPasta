import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalServer {
  HttpServer? _server;
  int port = 8080;
  String? ip;

  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;

    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );

    ip = interfaces
        .expand((i) => i.addresses)
        .firstWhere((a) => !a.isLoopback)
        .address;

    final router = Router();

    router.get('/health', (Request _) => Response.ok('ok'));

    router.get('/data', (Request _) async {
      final prefs = await SharedPreferences.getInstance();
      final notes = prefs.getStringList('notes') ?? [];
      final links = prefs.getStringList('links') ?? [];
      return Response.ok(jsonEncode({'notes': notes, 'links': links}),
          headers: {'Content-Type': 'application/json'});
    });

    router.post('/data', (Request req) async {
      final body = await req.readAsString();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();

      if (decoded['notes'] != null) {
        await prefs.setStringList(
            'notes', List<String>.from(decoded['notes']));
      }
      if (decoded['links'] != null) {
        await prefs.setStringList(
            'links', List<String>.from(decoded['links']));
      }

      return Response.ok('saved');
    });

    final handler =
        const Pipeline().addMiddleware(logRequests()).addHandler(router);

    _server = await io.serve(handler, InternetAddress.anyIPv4, port);
    print('Server running on $ip:$port');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
