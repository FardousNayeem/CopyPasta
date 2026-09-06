import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crypto/crypto.dart';

import 'package:copypasta/models/pasta_item.dart';
import 'package:copypasta/services/attachment_store.dart';
import 'package:copypasta/services/item_store.dart';
import 'package:copypasta/services/lan_service.dart';

/// Drives the real HTTP server over a real socket, because the failure this
/// replaces was entirely about the server not being reachable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final lan = LanService.instance;
  final store = ItemStore.instance;
  final files = AttachmentStore.instance;
  late Directory root;

  final base = 'http://127.0.0.1:${LanService.httpPort}';

  setUpAll(() async {
    // flutter_test swaps in an HttpClient that answers 400 to everything.
    // These tests are about real sockets, so put the real one back.
    HttpOverrides.global = null;
    root = await Directory.systemTemp.createTemp('copypasta_lan');
    await files.init(root: root);
    SharedPreferences.setMockInitialValues({});
    await store.load();
    await lan.init();
    await lan.start();
    expect(lan.status, ServerStatus.running,
        reason: 'server must bind before any of this means anything: '
            '${lan.lastError}');
  });

  tearDownAll(() async {
    await lan.stop();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('health is answerable without a PIN and identifies the app', () async {
    final response = await http.get(Uri.parse('$base/api/health'));
    expect(response.statusCode, 200);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    expect(body['app'], 'copypasta/1');
    expect(body['id'], lan.deviceId);
  });

  test('items are refused without the PIN', () async {
    final response = await http.get(Uri.parse('$base/api/items'));
    expect(response.statusCode, 401);
  });

  test('items are served with the PIN', () async {
    await store.add(kind: PastaKind.note, title: 'On the host', body: 'hello');

    final response = await http.get(
      Uri.parse('$base/api/items'),
      headers: {'x-copypasta-pin': lan.pin},
    );
    expect(response.statusCode, 200);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final titles = (body['items'] as List)
        .map((i) => (i as Map)['title'])
        .toList();
    expect(titles, contains('On the host'));
  });

  test('sync accepts the caller\'s items and returns its own', () async {
    final incoming = {
      'id': 'from-peer',
      'kind': 'note',
      'title': 'From the other device',
      'body': 'pasted',
      'createdAt': '2026-03-01T10:00:00.000Z',
      'updatedAt': '2026-03-01T10:00:00.000Z',
      'deleted': false,
    };

    final response = await http.post(
      Uri.parse('$base/api/sync'),
      headers: {
        'content-type': 'application/json',
        'x-copypasta-pin': lan.pin,
      },
      body: jsonEncode({'items': [incoming]}),
    );

    expect(response.statusCode, 200);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    expect(body['accepted'], 1, reason: 'the new row should have been taken');

    expect(store.visibleItems.map((i) => i.id), contains('from-peer'));
    expect(
      (body['items'] as List).map((i) => (i as Map)['title']),
      contains('On the host'),
      reason: 'the reply carries the host side back for the caller to merge',
    );
  });

  test('a browser gets a self-contained page with no external requests',
      () async {
    final response = await http.get(Uri.parse('$base/'));
    expect(response.statusCode, 200);
    expect(response.headers['content-type'], contains('text/html'));

    final html = response.body;
    expect(html, contains('<title>'));
    // Nothing may be fetched from off-device: the LAN often has no route out.
    expect(html, isNot(contains('https://fonts.')));
    expect(html, isNot(contains('cdn.')));
    expect(RegExp(r'<script[^>]+src=').hasMatch(html), isFalse);
    expect(RegExp(r'<link[^>]+stylesheet').hasMatch(html), isFalse);
  });

  test('the device name is escaped into the page, not injected', () async {
    await lan.setDeviceName('<script>alert(1)</script>');
    final response = await http.get(Uri.parse('$base/'));
    expect(response.body, isNot(contains('<script>alert(1)</script>')));
    expect(response.body, contains('&lt;script&gt;'));
    await lan.setDeviceName('Test device');
  });

  group('files', () {
    final payload = List<int>.generate(5000, (i) => i % 256);
    final digest = sha256.convert(payload).toString();
    late String attachmentId;

    test('a browser can upload a file and hang it on a new note', () async {
      final upload = await http.post(
        Uri.parse('$base/api/upload'),
        headers: {
          'x-copypasta-pin': lan.pin,
          'content-type': 'application/octet-stream',
          'x-file-name': Uri.encodeComponent('holiday photo.png'),
        },
        body: payload,
      );

      expect(upload.statusCode, 200);
      final attachment =
          (jsonDecode(upload.body) as Map<String, dynamic>)['attachment']
              as Map<String, dynamic>;

      attachmentId = attachment['id'] as String;
      expect(attachment['name'], 'holiday photo.png');
      expect(attachment['mimeType'], 'image/png');
      expect(attachment['size'], payload.length);
      expect(attachment['sha256'], digest,
          reason: 'the digest is what makes the transfer verifiable later');

      final create = await http.post(
        Uri.parse('$base/api/items'),
        headers: {
          'x-copypasta-pin': lan.pin,
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'kind': 'note',
          'title': 'From the laptop',
          'body': '',
          'attachments': [attachment],
        }),
      );
      expect(create.statusCode, 200);

      final saved = store.visibleItems
          .firstWhere((i) => i.title == 'From the laptop');
      expect(saved.attachments.single.id, attachmentId);
    });

    test('a note cannot claim a file that was never uploaded', () async {
      final create = await http.post(
        Uri.parse('$base/api/items'),
        headers: {
          'x-copypasta-pin': lan.pin,
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'kind': 'note',
          'title': 'Liar',
          'body': '',
          'attachments': [
            {
              'id': 'not-on-disk',
              'name': 'ghost.pdf',
              'mimeType': 'application/pdf',
              'size': 10,
              'sha256': 'x',
            }
          ],
        }),
      );

      expect(create.statusCode, 200);
      final saved = store.visibleItems.firstWhere((i) => i.title == 'Liar');
      expect(saved.attachments, isEmpty,
          reason: 'referencing a missing file would leave a permanently '
              'broken row that every sync tries to fetch');
    });

    test('the bytes come back exactly as they went in', () async {
      final response = await http.get(
        Uri.parse('$base/api/files/$attachmentId'),
        headers: {'x-copypasta-pin': lan.pin},
      );

      expect(response.statusCode, 200);
      expect(response.bodyBytes, payload);
      expect(response.headers['content-type'], contains('image/png'));
      expect(response.headers['x-file-sha256'], digest);
      expect(response.headers['content-disposition'],
          contains('filename="holiday photo.png"'));
    });

    test('files are behind the PIN like everything else', () async {
      final response =
          await http.get(Uri.parse('$base/api/files/$attachmentId'));
      expect(response.statusCode, 401);
    });

    test('asking for a file this device does not have says so', () async {
      final response = await http.get(
        Uri.parse('$base/api/files/nothing-here'),
        headers: {'x-copypasta-pin': lan.pin},
      );
      expect(response.statusCode, 404);
    });

    test('sync advertises which files this device is holding', () async {
      final response = await http.post(
        Uri.parse('$base/api/sync'),
        headers: {
          'x-copypasta-pin': lan.pin,
          'content-type': 'application/json',
        },
        body: jsonEncode({'items': [], 'haveFiles': []}),
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(body['haveFiles'], contains(attachmentId),
          reason: 'the peer decides what to pull from this list');
    });

    test('a peer can push a file under an id it already uses', () async {
      final incoming = List<int>.generate(300, (i) => (i * 3) % 256);
      final incomingDigest = sha256.convert(incoming).toString();

      final response = await http.put(
        Uri.parse('$base/api/files/peer-chosen-id'),
        headers: {
          'x-copypasta-pin': lan.pin,
          'x-file-name': 'from-peer.bin',
          'x-file-sha256': incomingDigest,
        },
        body: incoming,
      );

      expect(response.statusCode, 200);
      expect(files.has('peer-chosen-id'), isTrue);
      expect(await files.fileFor('peer-chosen-id').readAsBytes(), incoming);
    });

    test('a push whose digest does not match is rejected, not stored',
        () async {
      final response = await http.put(
        Uri.parse('$base/api/files/corrupt-id'),
        headers: {
          'x-copypasta-pin': lan.pin,
          'x-file-name': 'corrupt.bin',
          'x-file-sha256': sha256.convert(utf8.encode('something else')).toString(),
        },
        body: utf8.encode('actual bytes'),
      );

      expect(response.statusCode, 400);
      expect(files.has('corrupt-id'), isFalse);
    });

    test('an oversize upload writes nothing to disk', () async {
      // Note on what this does and does not show: dart:io holds the response
      // until the request body has been read, so a client that announces
      // 256 MB will not see the 413 until it has actually sent 256 MB. What is
      // guaranteed, and what this checks, is that nothing lands on disk. The
      // byte-count guard itself is covered in attachment_store_test.
      final socket = await Socket.connect('127.0.0.1', LanService.httpPort);
      final oversize = AttachmentStore.maxFileBytes + 1;
      socket.write(
        'PUT /api/files/too-big HTTP/1.1\r\n'
        'Host: 127.0.0.1:${LanService.httpPort}\r\n'
        'x-copypasta-pin: ${lan.pin}\r\n'
        'x-file-name: huge.bin\r\n'
        'Content-Length: $oversize\r\n'
        'Connection: close\r\n'
        '\r\n'
        'x',
      );
      await socket.flush();
      socket.destroy();

      expect(files.has('too-big'), isFalse);
    });
  });

  test('a PIN cannot be enumerated: repeated failures lock the caller out',
      () async {
    late http.Response last;
    for (var i = 0; i < 12; i++) {
      last = await http.get(
        Uri.parse('$base/api/items'),
        headers: {'x-copypasta-pin': '000000'},
      );
    }
    expect(last.statusCode, 429,
        reason: 'ten wrong tries should stop a script walking all 10^6 PINs');

    // And the lockout is not bypassed by suddenly presenting the right PIN.
    final withRealPin = await http.get(
      Uri.parse('$base/api/items'),
      headers: {'x-copypasta-pin': lan.pin},
    );
    expect(withRealPin.statusCode, 429);
  });
}
