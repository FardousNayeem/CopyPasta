import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart' as srouter;
import 'package:uuid/uuid.dart';

class ConnectPage extends StatefulWidget {
  const ConnectPage({Key? key}) : super(key: key);

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final _uuid = const Uuid();
  late String _deviceId;
  late String _deviceName;

  final _discoveredDevices = <DiscoveredDevice>[];

  bool isConnected = false;
  String? connectedDevice;

  static const int _port = 43210; // HTTP port
  static const int _udpPort = 5353; // UDP discovery port
  static const Duration _broadcastInterval = Duration(seconds: 3);

  io.HttpServer? _server;
  io.RawDatagramSocket? _udpSocket;
  Timer? _broadcastTimer;

  @override
  void initState() {
    super.initState();
    _initializeNetwork();
  }

  @override
  void dispose() {
    _server?.close(force: true);
    _udpSocket?.close();
    _broadcastTimer?.cancel();
    super.dispose();
  }

  /// Initialize device identity, HTTP server, and discovery system
  Future<void> _initializeNetwork() async {
    _deviceId = _uuid.v4();
    _deviceName = "CopyPasta-${io.Platform.localHostname}";
    await _startHttpServer();
    await _startUdpBroadcast();
  }

  // -------------------------------------------------------------
  // 🛰️ HTTP SERVER using shelf + shelf_router
  // -------------------------------------------------------------
  Future<void> _startHttpServer() async {
    final router = srouter.Router();

    // POST /connect  →  incoming connection request
    router.post('/connect', (Request request) async {
      final body = jsonDecode(await request.readAsString());
      final fromName = body['fromName'];

      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Connection Request'),
          content: Text('$fromName wants to connect. Accept?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Decline'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Accept'),
            ),
          ],
        ),
      );

      if (accepted == true) {
        setState(() {
          isConnected = true;
          connectedDevice = fromName;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connected to $fromName')),
        );
        Navigator.pop(context, true);
        return Response.ok(jsonEncode({'status': 'accepted'}));
      } else {
        return Response.ok(jsonEncode({'status': 'rejected'}));
      }
    });

    // optional /ping route
    router.get('/ping', (Request req) async {
      return Response.ok(jsonEncode({'pong': _deviceName}));
    });

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, io.InternetAddress.anyIPv4, _port);
    debugPrint('📡 HTTP server running on port $_port');
  }

  // -------------------------------------------------------------
  // 📡 UDP DISCOVERY (broadcast)
  // -------------------------------------------------------------
  Future<void> _startUdpBroadcast() async {
    _udpSocket = await io.RawDatagramSocket.bind(
      io.InternetAddress.anyIPv4,
      _udpPort,
    );
    _udpSocket!.broadcastEnabled = true;

    // Listen for UDP messages from other devices
    _udpSocket!.listen((event) {
      if (event == io.RawSocketEvent.read) {
        final datagram = _udpSocket!.receive();
        if (datagram != null) {
          final msg = utf8.decode(datagram.data);
          if (msg.startsWith("CopyPasta|")) {
            final parts = msg.split('|');
            if (parts.length >= 4) {
              final name = parts[1];
              final address = parts[2];
              final port = int.tryParse(parts[3]) ?? _port;

              if (name != _deviceName &&
                  !_discoveredDevices.any((d) => d.address == address)) {
                setState(() {
                  _discoveredDevices.add(
                    DiscoveredDevice(name: name, address: address, port: port),
                  );
                });
              }
            }
          }
        }
      }
    });

    // Periodically broadcast our device info
    _broadcastTimer = Timer.periodic(_broadcastInterval, (_) {
      _broadcastPresence();
    });
  }

  /// Broadcast this device's availability on UDP
  void _broadcastPresence() {
    final localIp = _getLocalIp();
    final message = "CopyPasta|$_deviceName|$localIp|$_port";
    _udpSocket?.send(
      utf8.encode(message),
      io.InternetAddress("255.255.255.255"),
      _udpPort,
    );
  }

  /// Get local IPv4 address (non-loopback)
  String _getLocalIp() {
    try {
      for (var interface in io.NetworkInterface.listSync()) {
        for (var addr in interface.addresses) {
          if (addr.type == io.InternetAddressType.IPv4 &&
              !addr.isLoopback &&
              !addr.address.startsWith('169')) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting local IP: $e');
    }
    return '0.0.0.0';
  }

  // -------------------------------------------------------------
  // 🔗 CONNECTION REQUEST (HTTP)
  // -------------------------------------------------------------
  Future<void> _connectToDevice(DiscoveredDevice device) async {
    try {
      final uri = Uri.parse('http://${device.address}:${device.port}/connect');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'fromName': _deviceName}),
      );

      final data = jsonDecode(response.body);
      if (data['status'] == 'accepted') {
        setState(() {
          isConnected = true;
          connectedDevice = device.name;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connected to ${device.name}')),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${device.name} rejected connection')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect: $e')),
      );
    }
  }

  // -------------------------------------------------------------
  // 🖼️ UI
  // -------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.primaryContainer,
        title: Text(
          'Connect Devices',
          style: TextStyle(
            color: theme.onPrimaryContainer,
            fontWeight: FontWeight.w600,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (isConnected && connectedDevice != null)
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: theme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Connected: $connectedDevice',
                      style: TextStyle(
                        color: theme.onPrimaryContainer,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          isConnected = false;
                          connectedDevice = null;
                        });
                      },
                      child: const Text(
                        'Disconnect',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _discoveredDevices.isEmpty
                  ? const Center(child: Text('Searching for devices...'))
                  : ListView.builder(
                      itemCount: _discoveredDevices.length,
                      itemBuilder: (context, index) {
                        final device = _discoveredDevices[index];
                        return Card(
                          color: theme.surfaceVariant,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          child: ListTile(
                            title: Text(
                              device.name,
                              style: TextStyle(
                                color: theme.onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(device.address),
                            trailing: ElevatedButton.icon(
                              icon: const Icon(Icons.link),
                              label: const Text('Connect'),
                              onPressed: () => _connectToDevice(device),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// 📦 Discovered Device model
// -------------------------------------------------------------
class DiscoveredDevice {
  final String name;
  final String address;
  final int port;

  DiscoveredDevice({
    required this.name,
    required this.address,
    required this.port,
  });
}
