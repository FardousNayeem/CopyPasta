import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:multicast_dns/multicast_dns.dart';

class LocalServer {
  HttpServer? _server;
  int port = 8080;
  String? ip;
  bool get isRunning => _server != null;
  MDnsClient? _mdns;

  /// Start the HTTP server and broadcast its presence on the LAN.
  Future<void> start() async {
    if (_server != null) return;

    final interfaces = await NetworkInterface.list(
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );

    ip = interfaces
        .expand((i) => i.addresses)
        .firstWhere((a) => !a.isLoopback)
        .address;

    final router = Router();

    // Health check
    router.get('/health', (Request _) => Response.ok('ok'));

    // Get stored data
    router.get('/data', (Request _) async {
      final prefs = await SharedPreferences.getInstance();
      final notes = prefs.getStringList('notes') ?? [];
      final links = prefs.getStringList('links') ?? [];
      final jsonData = jsonEncode({'notes': notes, 'links': links});
      return Response.ok(jsonData, headers: {'Content-Type': 'application/json'});
    });

    // Receive and save incoming data
    router.post('/data', (Request req) async {
      final body = await req.readAsString();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();

      if (decoded['notes'] != null) {
        await prefs.setStringList('notes', List<String>.from(decoded['notes']));
      }
      if (decoded['links'] != null) {
        await prefs.setStringList('links', List<String>.from(decoded['links']));
      }

      return Response.ok('saved');
    });

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(router);

    _server = await io.serve(handler, InternetAddress.anyIPv4, port);
    print('✅ CopyPasta server running on $ip:$port');

    // Start advertising for mDNS discovery
    _advertiseService();
  }

  /// Broadcast a service record for mDNS discovery
  Future<void> _advertiseService() async {
    try {
      _mdns = MDnsClient();
      await _mdns!.start();

      // Note: multicast_dns cannot broadcast directly, but this ensures the socket is live for discovery.
      // If you switch to `bonsoir` later, you can truly broadcast from here.
      print('🌐 (mDNS discovery socket started for CopyPasta)');
    } catch (e) {
      print('⚠️ Failed to start mDNS socket: $e');
    }
  }

  /// Stop the HTTP server and mDNS socket
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _mdns?.stop();
    _mdns = null;
    print('🛑 CopyPasta server stopped');
  }
}
