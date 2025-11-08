import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:multicast_dns/multicast_dns.dart';

/// A simple local HTTP server used by CopyPasta for sync and peer connection.
class LocalServer {
  HttpServer? _server;
  int port = 8080;
  String? ip;
  bool get isRunning => _server != null;

  final GlobalKey<NavigatorState> navigatorKey;

  LocalServer(this.navigatorKey);

  /// Start the server and listen for peer requests.
  Future<void> start() async {
    if (_server != null) return;

    final interfaces = await NetworkInterface.list(
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );
    ip = interfaces.expand((i) => i.addresses).firstWhere((a) => !a.isLoopback).address;

    final router = shelf.Router();


    router.get('/health', (_) => Response.ok('ok'));

    router.get('/data', (_) async {
      final prefs = await SharedPreferences.getInstance();
      final notes = prefs.getStringList('notes') ?? [];
      final links = prefs.getStringList('links') ?? [];
      return Response.ok(jsonEncode({'notes': notes, 'links': links}),
          headers: {'Content-Type': 'application/json'});
    });

    router.post('/data', (Request req) async {
      final prefs = await SharedPreferences.getInstance();
      final body = await req.readAsString();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      await prefs.setStringList('notes', List<String>.from(decoded['notes'] ?? []));
      await prefs.setStringList('links', List<String>.from(decoded['links'] ?? []));
      return Response.ok('saved');
    });

    // Connection handshake endpoints
    router.post('/connect', (Request req) async {
      final body = await req.readAsString();
      final data = jsonDecode(body);
      final requesterIp = data['ip'] ?? 'Unknown';
      final requesterName = data['name'] ?? 'Unknown device';
      _showIncomingRequest(requesterName, requesterIp);
      return Response.ok(
          jsonEncode({'status': 'pending', 'message': 'Request sent to user'}),
          headers: {'Content-Type': 'application/json'});
    });

    router.post('/accept', (Request req) async {
      final prefs = await SharedPreferences.getInstance();
      final body = await req.readAsString();
      final data = jsonDecode(body);
      final peerIp = data['ip'];
      final peerName = data['name'];
      await prefs.setString('connectedPeer', peerIp);
      await prefs.setString('connectedPeerName', peerName);
      return Response.ok(jsonEncode({'status': 'connected'}),
          headers: {'Content-Type': 'application/json'});
    });

    final handler = const Pipeline().addMiddleware(logRequests()).addHandler(router);
    _server = await io.serve(handler, InternetAddress.anyIPv4, port);
    print('✅ CopyPasta server running at $ip:$port');

    _startMdnsAdvertise();
  }

  void _showIncomingRequest(String requesterName, String requesterIp) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Incoming Connection'),
        content: Text('$requesterName ($requesterIp) wants to connect.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Reject')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('connectedPeer', requesterIp);
              await prefs.setString('connectedPeerName', requesterName);
              print('✅ Connected to $requesterIp');
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  /// Minimal mDNS advertisement socket (for discovery)
  Future<void> _startMdnsAdvertise() async {
    try {
      final mdns = MDnsClient();
      await mdns.start();
      print('🌐 mDNS socket active for CopyPasta discovery');
    } catch (e) {
      print('⚠️ mDNS failed: $e');
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    print('🛑 Server stopped');
  }
}
