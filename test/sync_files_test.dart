import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart' as srouter;

import 'package:copypasta/models/attachment.dart';
import 'package:copypasta/models/pasta_item.dart';
import 'package:copypasta/services/attachment_store.dart';
import 'package:copypasta/services/item_store.dart';
import 'package:copypasta/services/lan_service.dart';

/// Drives a full two-way sync against a stand-in peer.
///
/// The peer is a real HTTP server on a real socket implementing the same three
/// endpoints, so this exercises the client end for real: the item merge, the
/// decision about which files each side is missing, and the streamed download
/// and upload.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final lan = LanService.instance;
  final store = ItemStore.instance;
  final files = AttachmentStore.instance;

  late Directory localRoot;
  late Directory peerRoot;
  late HttpServer peerServer;
  late Peer peer;

  const peerPin = '424242';
  const peerPort = 45710;

  // What the peer has and we do not.
  final peerFileBytes = List<int>.generate(9000, (i) => (i * 7) % 256);
  final peerFileDigest = sha256.convert(peerFileBytes).toString();

  // What we have and the peer does not.
  final localFileBytes = List<int>.generate(4000, (i) => (i * 11) % 256);

  /// Files the stand-in peer holds, by attachment id.
  final peerFiles = <String, List<int>>{};

  /// Items the stand-in peer will offer.
  late List<Map<String, dynamic>> peerItems;

  setUp(() async {
    HttpOverrides.global = null;

    localRoot = await Directory.systemTemp.createTemp('copypasta_local');
    peerRoot = await Directory.systemTemp.createTemp('copypasta_peer');

    await files.init(root: localRoot);
    SharedPreferences.setMockInitialValues({});
    await store.load();
    await lan.init();

    final peerAttachment = Attachment(
      id: 'peer-file-1',
      name: 'invoice.pdf',
      mimeType: 'application/pdf',
      size: peerFileBytes.length,
      sha256: peerFileDigest,
    );

    peerFiles
      ..clear()
      ..['peer-file-1'] = peerFileBytes;

    peerItems = [
      PastaItem(
        id: 'peer-note',
        kind: PastaKind.note,
        title: 'Scan from the phone',
        body: '',
        createdAt: DateTime.utc(2026, 6, 1),
        updatedAt: DateTime.utc(2026, 6, 1),
        attachments: [peerAttachment],
      ).toJson(),
    ];

    final received = <String, List<int>>{};

    final router = srouter.Router();

    router.post('/api/sync', (Request request) async {
      if (request.headers['x-copypasta-pin'] != peerPin) {
        return Response(401, body: '{"error":"nope"}');
      }
      final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final incoming = (body['items'] as List).length;
      return Response.ok(
        jsonEncode({
          'device': 'Stand-in peer',
          'accepted': incoming,
          'items': peerItems,
          'haveFiles': peerFiles.keys.toList(),
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    router.get('/api/files/<id>', (Request request, String id) {
      if (request.headers['x-copypasta-pin'] != peerPin) return Response(401);
      final bytes = peerFiles[id];
      if (bytes == null) return Response.notFound('{"error":"unknown"}');
      return Response.ok(bytes, headers: {
        'content-type': 'application/pdf',
        'content-length': bytes.length.toString(),
      });
    });

    router.put('/api/files/<id>', (Request request, String id) async {
      if (request.headers['x-copypasta-pin'] != peerPin) return Response(401);
      final bytes = <int>[];
      await for (final chunk in request.read()) {
        bytes.addAll(chunk);
      }
      received[id] = bytes;
      peerFiles[id] = bytes;
      return Response.ok('{"ok":true}');
    });

    peerServer = await shelf_io.serve(
        router.call, InternetAddress.loopbackIPv4, peerPort);

    peer = Peer(
      id: 'stand-in',
      name: 'Stand-in peer',
      address: '127.0.0.1',
      port: peerPort,
      lastSeen: DateTime.now(),
    );
  });

  tearDown(() async {
    await peerServer.close(force: true);
    for (final dir in [localRoot, peerRoot]) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });

  test('pulls the file the peer has and pushes the file it lacks', () async {
    // Something on this side, with a file attached.
    final mine = await files.importFile(
      bytes: Stream.value(localFileBytes),
      name: 'receipt.png',
    );
    await store.add(
      kind: PastaKind.note,
      title: 'Saved on the laptop',
      attachments: [mine],
    );

    final progress = <String>[];
    final result = await lan.syncWith(peer, peerPin,
        onProgress: progress.add);

    expect(result.received, 1, reason: 'the peer note should have merged in');
    expect(result.filesPulled, 1);
    expect(result.filesPushed, 1);
    expect(result.fileProblems, isEmpty);

    // The peer's file is now on this device, byte for byte.
    expect(files.has('peer-file-1'), isTrue);
    expect(await files.fileFor('peer-file-1').readAsBytes(), peerFileBytes);

    // And ours reached the peer intact.
    expect(peerFiles[mine.id], localFileBytes);

    expect(progress, isNotEmpty,
        reason: 'a long file transfer has to say what it is doing');
    expect(progress.any((line) => line.contains('invoice.pdf')), isTrue);
    expect(result.summary, contains('Stand-in peer'));
  });

  test('a file that fails its digest is reported, and the notes still sync',
      () async {
    // The peer serves the right length but the wrong bytes.
    peerFiles['peer-file-1'] = List<int>.filled(peerFileBytes.length, 0);

    final result = await lan.syncWith(peer, peerPin);

    expect(result.received, 1, reason: 'the note merge is independent of files');
    expect(store.visibleItems.any((i) => i.id == 'peer-note'), isTrue);

    expect(result.filesPulled, 0);
    expect(result.hasProblems, isTrue);
    expect(result.fileProblems.single, contains('invoice.pdf'));
    expect(files.has('peer-file-1'), isFalse,
        reason: 'corrupt bytes must never become a file the user can open');
  });

  test('a file both sides already have is not moved again', () async {
    // Pull it once.
    await lan.syncWith(peer, peerPin);
    expect(files.has('peer-file-1'), isTrue);

    // Second run has nothing left to do.
    final second = await lan.syncWith(peer, peerPin);
    expect(second.filesPulled, 0);
    expect(second.filesPushed, 0);
  });

  test('a wrong PIN fails before any file is touched', () async {
    await expectLater(
      lan.syncWith(peer, '000000'),
      throwsA(isA<SyncException>()),
    );
    expect(files.has('peer-file-1'), isFalse);
  });
}
