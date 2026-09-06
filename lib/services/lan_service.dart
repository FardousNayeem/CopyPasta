import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart' as srouter;
import 'package:uuid/uuid.dart';

import 'package:copypasta/models/attachment.dart';
import 'package:copypasta/models/pasta_item.dart';
import 'package:copypasta/services/attachment_store.dart';
import 'package:copypasta/services/background_service.dart';
import 'package:copypasta/services/item_store.dart';
import 'package:copypasta/services/web_ui.dart';

/// A peer seen on the network.
class Peer {
  final String id;
  final String name;
  final String address;
  final int port;
  final DateTime lastSeen;

  const Peer({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    required this.lastSeen,
  });

  String get baseUrl => 'http://$address:$port';

  Peer touch() => Peer(
        id: id,
        name: name,
        address: address,
        port: port,
        lastSeen: DateTime.now(),
      );
}

enum ServerStatus { stopped, starting, running, failed }

/// Owns everything that touches the network: the HTTP server other devices
/// talk to, UDP presence announcements, the subnet scan that finds peers when
/// broadcast is filtered, and the sync client.
///
/// It is a process-lifetime singleton rather than widget state. The old
/// implementation started the server inside a page's `initState` and tore it
/// down in `dispose`, so the server only existed while that page was open,
/// which is why nothing could ever connect to it.
class LanService extends ChangeNotifier {
  LanService._();
  static final LanService instance = LanService._();

  static const int httpPort = 43210;

  /// Presence is announced on a port of our own. The previous code used 5353,
  /// the mDNS port, where it fought the operating system's own responder.
  static const int discoveryPort = 43211;

  static const Duration _announceInterval = Duration(seconds: 3);
  static const Duration _peerTtl = Duration(seconds: 12);
  static const String _protocolMagic = 'copypasta/1';

  static const _prefsDeviceId = 'lan_device_id';
  static const _prefsDeviceName = 'lan_device_name';
  static const _prefsPin = 'lan_pin';

  final _store = ItemStore.instance;
  final _files = AttachmentStore.instance;
  // Lazy: constructing an HttpClient eagerly runs at singleton-creation
  // time, which under flutter_test happens outside a test zone.
  late final http.Client _client = http.Client();

  late String deviceId;
  late String deviceName;
  late String pin;

  io.HttpServer? _server;
  io.RawDatagramSocket? _socket;
  Timer? _announceTimer;
  Timer? _reapTimer;

  ServerStatus status = ServerStatus.stopped;
  String? lastError;

  /// Set while a subnet sweep is in flight, so the UI can say so.
  bool isScanning = false;

  final Map<String, Peer> _peers = {};
  List<Peer> get peers {
    final list = _peers.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  final List<String> _addresses = [];

  /// Every URL this device can be reached on, for display and for the QR-less
  /// "type this in your browser" flow.
  List<String> get reachableUrls =>
      _addresses.map((a) => 'http://$a:$httpPort').toList(growable: false);

  /// Failed PIN attempts per remote address, so a six-digit PIN cannot simply
  /// be enumerated by a script on the same network.
  final Map<String, _AuthAttempts> _authAttempts = {};
  static const int _maxAuthFailures = 10;
  static const Duration _authLockout = Duration(minutes: 5);

  // ---------------------------------------------------------------- identity

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    deviceId = prefs.getString(_prefsDeviceId) ?? const Uuid().v4();
    await prefs.setString(_prefsDeviceId, deviceId);

    deviceName = prefs.getString(_prefsDeviceName) ?? _defaultDeviceName();
    await prefs.setString(_prefsDeviceName, deviceName);

    pin = prefs.getString(_prefsPin) ?? _generatePin();
    await prefs.setString(_prefsPin, pin);

    await _loadPeerPins(prefs);
    await refreshAddresses();
  }

  String _defaultDeviceName() {
    try {
      return io.Platform.localHostname;
    } catch (_) {
      return 'CopyPasta device';
    }
  }

  String _generatePin() {
    final rng = Random.secure();
    return List.generate(6, (_) => rng.nextInt(10)).join();
  }

  Future<void> setDeviceName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    deviceName = trimmed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsDeviceName, deviceName);
    notifyListeners();
  }

  // Remembered PINs of peers, so syncing with a device you have already paired
  // with is one tap. Stored in plain SharedPreferences: it is a convenience
  // credential for a LAN service, not a secret worth a keystore.
  static const _prefsPeerPinPrefix = 'peer_pin_';
  final Map<String, String> _peerPins = {};

  String? savedPinFor(String peerId) => _peerPins[peerId];

  Future<void> rememberPin(String peerId, String pin) async {
    _peerPins[peerId] = pin;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefsPeerPinPrefix$peerId', pin);
  }

  Future<void> forgetPin(String peerId) async {
    _peerPins.remove(peerId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefsPeerPinPrefix$peerId');
    notifyListeners();
  }

  Future<void> _loadPeerPins(SharedPreferences prefs) async {
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefsPeerPinPrefix)) continue;
      final value = prefs.getString(key);
      if (value != null) {
        _peerPins[key.substring(_prefsPeerPinPrefix.length)] = value;
      }
    }
  }

  Future<void> regeneratePin() async {
    pin = _generatePin();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsPin, pin);
    _authAttempts.clear();
    notifyListeners();
  }

  // ------------------------------------------------------------- local addrs

  /// Local IPv4 addresses, private ranges first. Link-local (169.254) and
  /// loopback are excluded because nothing else on the LAN can reach them.
  Future<void> refreshAddresses() async {
    final found = <String>[];
    try {
      final interfaces = await io.NetworkInterface.list(
        type: io.InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.address.startsWith('169.254')) continue;
          found.add(addr.address);
        }
      }
    } catch (e) {
      lastError = 'Could not read network interfaces: $e';
    }
    found.sort((a, b) {
      final ap = _isPrivate(a) ? 0 : 1;
      final bp = _isPrivate(b) ? 0 : 1;
      return ap.compareTo(bp);
    });
    _addresses
      ..clear()
      ..addAll(found);

    // The lock-screen notification carries the address, so the user does not
    // have to unlock and open the app just to read it.
    unawaited(BackgroundService.instance.describe(
      _addresses.isEmpty
          ? 'Waiting for a Wi-Fi connection'
          : 'Open http://${_addresses.first}:$httpPort',
    ));

    notifyListeners();
  }

  static bool _isPrivate(String ip) {
    if (ip.startsWith('192.168.') || ip.startsWith('10.')) return true;
    final parts = ip.split('.');
    if (parts.length != 4 || parts[0] != '172') return false;
    final second = int.tryParse(parts[1]);
    return second != null && second >= 16 && second <= 31;
  }

  // ----------------------------------------------------------- server / disco

  Future<void> start() async {
    if (status == ServerStatus.running || status == ServerStatus.starting) {
      return;
    }
    status = ServerStatus.starting;
    lastError = null;
    notifyListeners();

    await refreshAddresses();

    try {
      await _startHttpServer();
      await _startDiscovery();
      status = ServerStatus.running;
    } catch (e) {
      lastError = _friendlyStartError(e);
      status = ServerStatus.failed;
      await _tearDown();
    }
    notifyListeners();
  }

  String _friendlyStartError(Object e) {
    final text = e.toString();
    if (text.contains('errno = 98') ||
        text.contains('errno = 48') ||
        text.contains('10048') ||
        text.toLowerCase().contains('address already in use')) {
      return 'Port $httpPort is already in use. Another copy of CopyPasta is '
          'probably running on this device.';
    }
    if (text.contains('errno = 13') || text.contains('errno = 1')) {
      return 'The system refused to open port $httpPort. Check that the app '
          'has network permission.';
    }
    return text;
  }

  Future<void> stop() async {
    await _tearDown();
    status = ServerStatus.stopped;
    _peers.clear();
    notifyListeners();
  }

  Future<void> _tearDown() async {
    _announceTimer?.cancel();
    _announceTimer = null;
    _reapTimer?.cancel();
    _reapTimer = null;
    _socket?.close();
    _socket = null;
    await _server?.close(force: true);
    _server = null;
  }

  @override
  void dispose() {
    _tearDown();
    _client.close();
    super.dispose();
  }

  Future<void> _startHttpServer() async {
    final router = srouter.Router();

    // Unauthenticated on purpose: this is the probe the subnet scan uses to
    // tell a CopyPasta device from anything else listening on the port. It
    // deliberately exposes nothing but a name and an id.
    router.get('/api/health', (Request req) {
      return _json({
        'app': _protocolMagic,
        'id': deviceId,
        'name': deviceName,
        'port': httpPort,
      });
    });

    router.post('/api/auth', (Request req) async {
      final remote = _remoteAddress(req);
      if (_isLockedOut(remote)) {
        return _json({'error': 'Too many attempts. Wait a few minutes.'},
            status: 429);
      }
      final body = await _readJson(req);
      final supplied = (body?['pin'] ?? '').toString();
      if (!_secureEquals(supplied, pin)) {
        _recordAuthFailure(remote);
        return _json({'error': 'Wrong PIN'}, status: 401);
      }
      _authAttempts.remove(remote);
      return Response.ok(
        jsonEncode({'ok': true, 'name': deviceName}),
        headers: {
          'content-type': 'application/json',
          // Session cookie so the browser does not re-ask on every request.
          // HttpOnly keeps it out of page scripts; SameSite=Strict keeps other
          // origins from riding on it.
          'set-cookie': 'cp_pin=$pin; HttpOnly; SameSite=Strict; Path=/',
        },
      );
    });

    router.get('/api/items', (Request req) {
      final denied = _requireAuth(req);
      if (denied != null) return denied;
      return _json({
        'device': deviceName,
        'items': _store.allItems.map((i) => i.toJson()).toList(),
      });
    });

    /// One round trip in both directions: the caller sends everything it has,
    /// we merge it, and we answer with everything we have for the caller to
    /// merge in turn.
    ///
    /// `haveFiles` on both sides lists the attachment ids each end already
    /// holds, so the caller knows exactly which files to pull and which to
    /// push. Only metadata moves here; bytes go over `/api/files/<id>`.
    router.post('/api/sync', (Request req) async {
      final denied = _requireAuth(req);
      if (denied != null) return denied;
      final body = await _readJson(req);
      final incoming = _itemsFromJson(body?['items']);
      final changed = await _store.merge(incoming);
      return _json({
        'device': deviceName,
        'accepted': changed,
        'items': _store.allItems.map((i) => i.toJson()).toList(),
        'haveFiles': _localFileIds().toList(),
      });
    });

    /// Streams one attachment's bytes. Never loads the file into memory: a
    /// phone serving a 200 MB video to a laptop must not allocate 200 MB.
    router.get('/api/files/<id>', (Request req, String id) async {
      final denied = _requireAuth(req);
      if (denied != null) return denied;

      final attachment = _store.attachmentById(id);
      if (attachment == null) return _json({'error': 'Unknown file'}, status: 404);
      if (!_files.isReady) {
        return _json({'error': 'File storage unavailable'}, status: 503);
      }

      final file = _files.fileFor(id);
      if (!await file.exists()) {
        return _json({'error': 'This device does not have that file'},
            status: 404);
      }

      final inline = req.url.queryParameters['inline'] == '1';
      return Response.ok(
        file.openRead(),
        headers: {
          'content-type': attachment.mimeType,
          'content-length': (await file.length()).toString(),
          'content-disposition':
              '${inline ? 'inline' : 'attachment'}; filename="${_headerSafe(attachment.name)}"',
          'x-file-sha256': attachment.sha256,
          'x-file-name': _headerSafe(attachment.name),
        },
      );
    });

    /// Accepts an attachment under an id the sender already uses, so the same
    /// file has the same id on every device.
    router.put('/api/files/<id>', (Request req, String id) async {
      final denied = _requireAuth(req);
      if (denied != null) return denied;
      if (!_files.isReady) {
        return _json({'error': 'File storage unavailable'}, status: 503);
      }

      final declared = int.tryParse(req.headers['content-length'] ?? '');
      if (declared != null && declared > AttachmentStore.maxFileBytes) {
        return _json({'error': 'File is over the transfer limit'}, status: 413);
      }

      final name = req.headers['x-file-name'] ?? id;
      final expected = req.headers['x-file-sha256'] ?? '';
      try {
        await _files.receiveFile(
          attachmentId: id,
          bytes: req.read(),
          name: name,
          expectedSha256: expected,
          declaredSize: declared,
        );
        return _json({'ok': true});
      } on AttachmentException catch (e) {
        return _json({'error': e.message}, status: 400);
      }
    });

    /// Browser upload. The server mints the id here because the browser has no
    /// store of its own to name the file in.
    router.post('/api/upload', (Request req) async {
      final denied = _requireAuth(req);
      if (denied != null) return denied;
      if (!_files.isReady) {
        return _json({'error': 'File storage unavailable'}, status: 503);
      }

      final declared = int.tryParse(req.headers['content-length'] ?? '');
      if (declared != null && declared > AttachmentStore.maxFileBytes) {
        return _json({'error': 'File is over the size limit'}, status: 413);
      }

      final name = req.headers['x-file-name'] ?? 'file';
      try {
        final attachment = await _files.importFile(
          bytes: req.read(),
          name: Uri.decodeComponent(name),
          knownSize: declared,
        );
        return _json({'ok': true, 'attachment': attachment.toJson()});
      } on AttachmentException catch (e) {
        return _json({'error': e.message}, status: 400);
      }
    });

    router.post('/api/items', (Request req) async {
      final denied = _requireAuth(req);
      if (denied != null) return denied;
      final body = await _readJson(req);
      final title = (body?['title'] ?? '').toString().trim();
      final bodyText = (body?['body'] ?? '').toString();
      final hasAttachments =
          body?['attachments'] is List && (body!['attachments'] as List).isNotEmpty;
      if (title.isEmpty && bodyText.trim().isEmpty && !hasAttachments) {
        return _json({'error': 'Empty item'}, status: 400);
      }
      final kind = (body?['kind'] ?? 'note') == 'link'
          ? PastaKind.link
          : PastaKind.note;

      // Attachments were uploaded to /api/upload first; only ids that actually
      // landed on disk are accepted, so a note can never reference a file that
      // is not there.
      final attachments = <Attachment>[];
      final rawAttachments = body?['attachments'];
      if (rawAttachments is List) {
        for (final entry in rawAttachments) {
          final attachment = Attachment.fromJson(entry);
          if (attachment == null) continue;
          if (!_files.isReady || !_files.has(attachment.id)) continue;
          attachments.add(attachment);
        }
      }

      final item = await _store.add(
        kind: kind,
        title: title.isEmpty ? bodyText.trim().split('\n').first : title,
        body: bodyText,
        attachments: attachments,
      );
      return _json({'ok': true, 'item': item.toJson()});
    });

    router.delete('/api/items/<id>', (Request req, String id) async {
      final denied = _requireAuth(req);
      if (denied != null) return denied;
      await _store.delete(id);
      return _json({'ok': true});
    });

    // The browser UI. This is what makes a Windows machine a first-class
    // client without installing anything.
    router.get('/', (Request req) {
      return Response.ok(
        buildWebUi(deviceName: deviceName),
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    });

    final handler = const Pipeline()
        .addMiddleware(_noStore())
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, io.InternetAddress.anyIPv4, httpPort,
        shared: false);
    _server!.autoCompress = true;
  }

  Middleware _noStore() {
    return (Handler inner) {
      return (Request request) async {
        final response = await inner(request);
        return response.change(headers: {
          'cache-control': 'no-store',
          'x-content-type-options': 'nosniff',
        });
      };
    };
  }

  // -------------------------------------------------------------------- auth

  String _remoteAddress(Request req) {
    final info = req.context['shelf.io.connection_info'];
    if (info is io.HttpConnectionInfo) return info.remoteAddress.address;
    return 'unknown';
  }

  Response? _requireAuth(Request req) {
    final remote = _remoteAddress(req);
    if (_isLockedOut(remote)) {
      return _json({'error': 'Too many attempts. Wait a few minutes.'},
          status: 429);
    }
    final header = req.headers['x-copypasta-pin'];
    final cookie = _cookieValue(req.headers['cookie'], 'cp_pin');
    final supplied = header ?? cookie ?? '';
    if (_secureEquals(supplied, pin)) {
      _authAttempts.remove(remote);
      return null;
    }
    _recordAuthFailure(remote);
    return _json({'error': 'PIN required'}, status: 401);
  }

  static String? _cookieValue(String? header, String name) {
    if (header == null) return null;
    for (final part in header.split(';')) {
      final trimmed = part.trim();
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      if (trimmed.substring(0, eq) == name) return trimmed.substring(eq + 1);
    }
    return null;
  }

  /// Compares in time independent of where the first difference falls, so the
  /// PIN cannot be recovered one digit at a time by timing the response.
  static bool _secureEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  bool _isLockedOut(String remote) {
    final attempts = _authAttempts[remote];
    if (attempts == null) return false;
    if (DateTime.now().difference(attempts.last) > _authLockout) {
      _authAttempts.remove(remote);
      return false;
    }
    return attempts.count >= _maxAuthFailures;
  }

  void _recordAuthFailure(String remote) {
    final existing = _authAttempts[remote];
    if (existing == null || DateTime.now().difference(existing.last) > _authLockout) {
      _authAttempts[remote] = _AuthAttempts(1, DateTime.now());
    } else {
      _authAttempts[remote] = _AuthAttempts(existing.count + 1, DateTime.now());
    }
  }

  // --------------------------------------------------------------- discovery

  Future<void> _startDiscovery() async {
    // reuseAddress lets a second app instance (or a fast restart) bind the
    // same port instead of failing outright.
    _socket = await io.RawDatagramSocket.bind(
      io.InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
    );
    _socket!.broadcastEnabled = true;

    _socket!.listen((event) {
      if (event != io.RawSocketEvent.read) return;
      final datagram = _socket!.receive();
      if (datagram == null) return;
      _handleAnnouncement(datagram);
    }, onError: (Object e) {
      lastError = 'Discovery socket error: $e';
      notifyListeners();
    });

    _announce();
    _announceTimer = Timer.periodic(_announceInterval, (_) => _announce());
    _reapTimer = Timer.periodic(const Duration(seconds: 4), (_) => _reapPeers());
  }

  void _handleAnnouncement(io.Datagram datagram) {
    Map<String, dynamic> payload;
    try {
      final decoded = json.decode(utf8.decode(datagram.data));
      if (decoded is! Map<String, dynamic>) return;
      payload = decoded;
    } catch (_) {
      return; // Not ours, or truncated. Ignore quietly.
    }
    if (payload['app'] != _protocolMagic) return;

    final id = payload['id'];
    // Identify by id, not by name: two devices can share a hostname, and the
    // old name comparison meant we happily listed ourselves.
    if (id is! String || id == deviceId) return;

    final peer = Peer(
      id: id,
      name: (payload['name'] ?? 'Unknown device').toString(),
      address: datagram.address.address,
      port: (payload['port'] as num?)?.toInt() ?? httpPort,
      lastSeen: DateTime.now(),
    );
    final existing = _peers[id];
    _peers[id] = peer;
    if (existing == null ||
        existing.address != peer.address ||
        existing.name != peer.name) {
      notifyListeners();
    }
  }

  void _announce() {
    final socket = _socket;
    if (socket == null) return;
    final message = utf8.encode(jsonEncode({
      'app': _protocolMagic,
      'id': deviceId,
      'name': deviceName,
      'port': httpPort,
    }));

    // Send to each interface's directed broadcast address as well as the
    // limited broadcast address. Android and several home routers drop
    // 255.255.255.255, which is all the previous implementation ever sent to.
    final targets = <String>{'255.255.255.255'};
    for (final addr in _addresses) {
      final directed = _directedBroadcast(addr);
      if (directed != null) targets.add(directed);
    }

    for (final target in targets) {
      try {
        socket.send(message, io.InternetAddress(target), discoveryPort);
      } catch (_) {
        // A single unreachable interface must not stop the others.
      }
    }
  }

  /// Assumes a /24, which is what home Wi-Fi hands out. Dart does not expose
  /// interface netmasks, so a wider subnet falls back to the subnet scan.
  static String? _directedBroadcast(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    return '${parts[0]}.${parts[1]}.${parts[2]}.255';
  }

  void _reapPeers() {
    final now = DateTime.now();
    final cutoff = now.subtract(_peerTtl);
    final before = _peers.length;
    _peers.removeWhere((_, p) => p.lastSeen.isBefore(cutoff));

    // Expired lockouts are otherwise only cleared when that same address comes
    // back, so the map would grow one entry per address that ever guessed
    // wrong and never shrink.
    _authAttempts.removeWhere((_, a) => now.difference(a.last) > _authLockout);

    if (_peers.length != before) notifyListeners();
  }

  // -------------------------------------------------------------------- scan

  /// Sweeps the local /24 for anything answering `/api/health`.
  ///
  /// This is the reliable path. UDP broadcast reception is filtered by the
  /// Wi-Fi stack on Android without a native multicast lock, and by plenty of
  /// consumer access points with client isolation part-way on, so discovery
  /// cannot depend on it alone.
  Future<void> scanSubnet({void Function(int done, int total)? onProgress}) async {
    if (isScanning) return;
    isScanning = true;
    notifyListeners();

    await refreshAddresses();
    final prefixes = <String>{};
    for (final addr in _addresses) {
      if (!_isPrivate(addr)) continue;
      final parts = addr.split('.');
      if (parts.length == 4) prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
    }

    final hosts = <String>[
      for (final prefix in prefixes)
        for (var i = 1; i <= 254; i++)
          if (!_addresses.contains('$prefix.$i')) '$prefix.$i',
    ];

    var done = 0;
    const batchSize = 32;
    for (var i = 0; i < hosts.length; i += batchSize) {
      if (!isScanning) break; // cancelled
      final batch = hosts.skip(i).take(batchSize);
      await Future.wait(batch.map((host) async {
        await _probe(host);
        done++;
        onProgress?.call(done, hosts.length);
      }));
    }

    isScanning = false;
    notifyListeners();
  }

  void cancelScan() {
    if (!isScanning) return;
    isScanning = false;
    notifyListeners();
  }

  Future<void> _probe(String host) async {
    try {
      final response = await _client
          .get(Uri.parse('http://$host:$httpPort/api/health'))
          .timeout(const Duration(milliseconds: 600));
      if (response.statusCode != 200) return;
      final body = json.decode(response.body);
      if (body is! Map || body['app'] != _protocolMagic) return;
      final id = body['id'];
      if (id is! String || id == deviceId) return;
      _peers[id] = Peer(
        id: id,
        name: (body['name'] ?? 'Unknown device').toString(),
        address: host,
        port: (body['port'] as num?)?.toInt() ?? httpPort,
        lastSeen: DateTime.now(),
      );
      notifyListeners();
    } catch (_) {
      // Nothing there, or not us. Expected for almost every address.
    }
  }

  /// Checks one hand-typed address and adds it as a peer if it answers.
  Future<Peer?> addManualPeer(String hostOrUrl) async {
    var host = hostOrUrl.trim();
    var port = httpPort;
    host = host.replaceFirst(RegExp(r'^https?://'), '');
    host = host.split('/').first;
    if (host.contains(':')) {
      final parts = host.split(':');
      host = parts.first;
      port = int.tryParse(parts.last) ?? httpPort;
    }
    if (host.isEmpty) return null;

    try {
      final response = await _client
          .get(Uri.parse('http://$host:$port/api/health'))
          .timeout(const Duration(seconds: 4));
      final body = json.decode(response.body);
      if (body is! Map || body['app'] != _protocolMagic) return null;
      final peer = Peer(
        id: (body['id'] ?? host).toString(),
        name: (body['name'] ?? host).toString(),
        address: host,
        port: port,
        lastSeen: DateTime.now(),
      );
      _peers[peer.id] = peer;
      notifyListeners();
      return peer;
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------- sync client

  /// Attachment ids whose bytes are actually on this device's disk.
  Set<String> _localFileIds() {
    if (!_files.isReady) return {};
    return _store.referencedAttachmentIds.where(_files.has).toSet();
  }

  /// Strips characters that would break out of a header value or a quoted
  /// filename. A peer chooses these names, so they are not trusted input.
  static String _headerSafe(String raw) {
    return raw
        .replaceAll(RegExp(r'[\r\n"\\]'), '')
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '')
        .trim();
  }

  /// Exchanges items with [peer] using the peer's PIN, then moves any files
  /// that only one side has.
  ///
  /// [onProgress] is called with a short line the UI can show while files are
  /// in flight, because a 40 MB video over Wi-Fi is not instant and a frozen
  /// button looks broken.
  ///
  /// Returns a short sentence for the UI to show. Throws [SyncException] with
  /// a message the user can act on rather than a raw socket error.
  Future<SyncResult> syncWith(
    Peer peer,
    String peerPin, {
    void Function(String message)? onProgress,
  }) async {
    Map<String, dynamic> body;
    int sent;
    int received;

    try {
      onProgress?.call('Exchanging notes');
      final response = await _client
          .post(
            Uri.parse('${peer.baseUrl}/api/sync'),
            headers: {
              'content-type': 'application/json',
              'x-copypasta-pin': peerPin,
            },
            body: jsonEncode({
              'device': deviceName,
              'items': _store.allItems.map((i) => i.toJson()).toList(),
              'haveFiles': _localFileIds().toList(),
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 401) {
        throw SyncException('${peer.name} rejected the PIN.');
      }
      if (response.statusCode == 429) {
        throw SyncException(
            'Too many wrong PINs. ${peer.name} is locked for a few minutes.');
      }
      if (response.statusCode != 200) {
        throw SyncException('${peer.name} answered ${response.statusCode}.');
      }

      final decoded = json.decode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw SyncException('Unreadable reply from ${peer.name}.');
      }
      body = decoded;

      received = await _store.merge(_itemsFromJson(body['items']));
      sent = (body['accepted'] as num?)?.toInt() ?? 0;
    } on SyncException {
      rethrow;
    } on TimeoutException {
      throw SyncException('${peer.name} did not answer in time.');
    } catch (e) {
      throw SyncException('Could not reach ${peer.name}: ${_socketHint(e)}');
    }

    // Notes are safe on both sides now. File transfer failures from here on
    // are reported but do not undo the merge that already succeeded.
    final peerFiles = <String>{
      for (final id in (body['haveFiles'] as List? ?? const []))
        if (id is String) id,
    };

    return _transferFiles(
      peer: peer,
      peerPin: peerPin,
      peerFiles: peerFiles,
      sent: sent,
      received: received,
      onProgress: onProgress,
    );
  }

  Future<SyncResult> _transferFiles({
    required Peer peer,
    required String peerPin,
    required Set<String> peerFiles,
    required int sent,
    required int received,
    void Function(String message)? onProgress,
  }) async {
    if (!_files.isReady) {
      return SyncResult(sent: sent, received: received, peerName: peer.name);
    }

    final referenced = _store.referencedAttachmentIds;
    final localFiles = referenced.where(_files.has).toSet();

    // Pull what the peer has and we do not, push what we have and it does not.
    final toPull = referenced
        .where((id) => !localFiles.contains(id) && peerFiles.contains(id))
        .toList();
    final toPush =
        localFiles.where((id) => !peerFiles.contains(id)).toList();

    var pulled = 0;
    var pushed = 0;
    final problems = <String>[];

    for (var i = 0; i < toPull.length; i++) {
      final attachment = _store.attachmentById(toPull[i]);
      if (attachment == null) continue;
      onProgress?.call(
          'Downloading ${attachment.name} (${i + 1} of ${toPull.length})');
      try {
        await _downloadFile(peer, peerPin, attachment);
        pulled++;
      } catch (e) {
        problems.add('${attachment.name}: ${_fileErrorText(e)}');
      }
    }

    for (var i = 0; i < toPush.length; i++) {
      final attachment = _store.attachmentById(toPush[i]);
      if (attachment == null) continue;
      onProgress?.call(
          'Uploading ${attachment.name} (${i + 1} of ${toPush.length})');
      try {
        await _uploadFile(peer, peerPin, attachment);
        pushed++;
      } catch (e) {
        problems.add('${attachment.name}: ${_fileErrorText(e)}');
      }
    }

    return SyncResult(
      sent: sent,
      received: received,
      peerName: peer.name,
      filesPulled: pulled,
      filesPushed: pushed,
      fileProblems: problems,
    );
  }

  /// A dedicated client for bytes. `dart:io` streams request and response
  /// bodies without buffering them, which `package:http` will not do for a
  /// plain request, and these files can be hundreds of megabytes.
  io.HttpClient _newFileClient() {
    return io.HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 30);
  }

  Future<void> _downloadFile(
      Peer peer, String peerPin, Attachment attachment) async {
    final client = _newFileClient();
    try {
      final request = await client
          .getUrl(Uri.parse('${peer.baseUrl}/api/files/${attachment.id}'));
      request.headers.set('x-copypasta-pin', peerPin);
      final response = await request.close();

      if (response.statusCode != 200) {
        // Drain, or the socket is left half-read and the connection leaks.
        await response.drain<void>();
        throw SyncException('the other device answered ${response.statusCode}');
      }

      await _files.receiveFile(
        attachmentId: attachment.id,
        bytes: response,
        name: attachment.name,
        expectedSha256: attachment.sha256,
        declaredSize: attachment.size,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _uploadFile(
      Peer peer, String peerPin, Attachment attachment) async {
    final file = _files.fileFor(attachment.id);
    if (!await file.exists()) return;

    final client = _newFileClient();
    try {
      final request = await client
          .putUrl(Uri.parse('${peer.baseUrl}/api/files/${attachment.id}'));
      request.headers
        ..set('x-copypasta-pin', peerPin)
        ..set('x-file-name', _headerSafe(attachment.name))
        ..set('x-file-sha256', attachment.sha256)
        ..set('content-type', 'application/octet-stream');
      request.contentLength = await file.length();

      await request.addStream(file.openRead());
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        String reason = 'the other device answered ${response.statusCode}';
        try {
          final decoded = json.decode(text);
          if (decoded is Map && decoded['error'] is String) {
            reason = decoded['error'] as String;
          }
        } catch (_) {}
        throw SyncException(reason);
      }
    } finally {
      client.close(force: true);
    }
  }

  static String _fileErrorText(Object e) {
    if (e is SyncException) return e.message;
    if (e is AttachmentException) return e.message;
    if (e is TimeoutException) return 'timed out';
    return e.toString();
  }

  String _socketHint(Object e) {
    final text = e.toString();
    if (text.contains('Connection refused')) {
      return 'nothing is listening. Is CopyPasta open on that device?';
    }
    if (text.contains('No route to host') || text.contains('Network is unreachable')) {
      return 'no route. Are both devices on the same Wi-Fi?';
    }
    if (text.contains('timed out')) {
      return 'timed out. A firewall may be blocking port $httpPort.';
    }
    return text;
  }

  static List<PastaItem> _itemsFromJson(Object? raw) {
    if (raw is! List) return const [];
    final out = <PastaItem>[];
    for (final entry in raw) {
      if (entry is! Map<String, dynamic>) continue;
      final item = PastaItem.fromJson(entry);
      if (item != null) out.add(item);
    }
    return out;
  }

  // ------------------------------------------------------------------ helpers

  static Response _json(Map<String, dynamic> body, {int status = 200}) {
    return Response(status,
        body: jsonEncode(body),
        headers: {'content-type': 'application/json; charset=utf-8'});
  }

  static Future<Map<String, dynamic>?> _readJson(Request req) async {
    try {
      final text = await req.readAsString();
      if (text.isEmpty) return null;
      final decoded = json.decode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

class SyncResult {
  final int sent;
  final int received;
  final String peerName;
  final int filesPulled;
  final int filesPushed;

  /// Files that failed to move, each already phrased for a person. The notes
  /// still synced; these are reported without calling the whole thing a
  /// failure.
  final List<String> fileProblems;

  const SyncResult({
    required this.sent,
    required this.received,
    required this.peerName,
    this.filesPulled = 0,
    this.filesPushed = 0,
    this.fileProblems = const [],
  });

  bool get hasProblems => fileProblems.isNotEmpty;

  String get summary {
    final parts = <String>[];
    if (received > 0) parts.add('pulled $received');
    if (sent > 0) parts.add('pushed $sent');

    final files = <String>[];
    if (filesPulled > 0) files.add('$filesPulled in');
    if (filesPushed > 0) files.add('$filesPushed out');
    if (files.isNotEmpty) {
      parts.add('${files.join(' and ')} ${_fileWord(filesPulled + filesPushed)}');
    }

    if (parts.isEmpty) return 'Already in sync with $peerName.';
    final line = '${parts.join(', ')} with $peerName.';
    if (fileProblems.isEmpty) return line;
    return '$line ${fileProblems.length} file'
        '${fileProblems.length == 1 ? '' : 's'} failed: ${fileProblems.first}';
  }

  static String _fileWord(int count) => count == 1 ? 'file' : 'files';
}

class SyncException implements Exception {
  final String message;
  const SyncException(this.message);
  @override
  String toString() => message;
}

class _AuthAttempts {
  final int count;
  final DateTime last;
  const _AuthAttempts(this.count, this.last);
}
