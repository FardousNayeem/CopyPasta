import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:copypasta/models/attachment.dart';
import 'package:copypasta/models/pasta_item.dart';
import 'package:copypasta/services/attachment_store.dart';
import 'package:copypasta/services/item_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final files = AttachmentStore.instance;
  final store = ItemStore.instance;
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('copypasta_attachments');
    await files.init(root: root);
    SharedPreferences.setMockInitialValues({});
    await store.load();
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Stream<List<int>> chunked(List<int> bytes, {int chunk = 7}) async* {
    for (var i = 0; i < bytes.length; i += chunk) {
      yield bytes.sublist(i, (i + chunk).clamp(0, bytes.length));
    }
  }

  group('import', () {
    test('records the real size and digest of the bytes it wrote', () async {
      final bytes = utf8.encode('the quick brown fox jumps over the lazy dog');

      final attachment = await files.importFile(
        bytes: chunked(bytes),
        name: 'fox.txt',
        knownSize: bytes.length,
      );

      expect(attachment.size, bytes.length);
      expect(attachment.sha256, sha256.convert(bytes).toString());
      expect(attachment.mimeType, 'text/plain');
      expect(files.has(attachment.id), isTrue);
      expect(await files.fileFor(attachment.id).readAsBytes(), bytes);
    });

    test('refuses a file the picker already says is too big', () async {
      expect(
        () => files.importFile(
          bytes: chunked(utf8.encode('small')),
          name: 'huge.bin',
          knownSize: AttachmentStore.maxFileBytes + 1,
        ),
        throwsA(isA<AttachmentException>()),
      );
    });

    test('stops writing once the bytes exceed the limit, whatever was declared',
        () async {
      // The declared size is not trusted: a sender can lie in Content-Length,
      // so the running count is the guard that has to hold.
      await expectLater(
        files.importFile(
          bytes: chunked(List<int>.filled(500, 65)),
          name: 'liar.bin',
          knownSize: 10,
          maxBytes: 100,
        ),
        throwsA(isA<AttachmentException>()),
      );

      final leftovers = root
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path)
          .toList();
      expect(leftovers, isEmpty,
          reason: 'a refused upload must not leave a truncated file behind');
    });

    test('strips any directory part out of the name', () async {
      final attachment = await files.importFile(
        bytes: chunked(utf8.encode('x')),
        name: '../../etc/passwd',
      );
      expect(attachment.name, 'passwd',
          reason: 'a peer must not be able to name a file into another folder');
    });

    test('leaves no partial file behind when the stream fails', () async {
      Stream<List<int>> broken() async* {
        yield utf8.encode('start');
        throw const SocketException('connection reset');
      }

      await expectLater(
        files.importFile(bytes: broken(), name: 'broken.bin'),
        throwsA(isA<AttachmentException>()),
      );

      final leftovers = root
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path)
          .toList();
      expect(leftovers, isEmpty);
    });
  });

  group('receive', () {
    test('accepts bytes that match the digest the sender promised', () async {
      final bytes = utf8.encode('a synced file');
      await files.receiveFile(
        attachmentId: 'given-id',
        bytes: chunked(bytes),
        name: 'note.txt',
        expectedSha256: sha256.convert(bytes).toString(),
        declaredSize: bytes.length,
      );
      expect(files.has('given-id'), isTrue);
    });

    test('discards a corrupted transfer instead of saving it', () async {
      await expectLater(
        files.receiveFile(
          attachmentId: 'bad-id',
          bytes: chunked(utf8.encode('these are not the bytes you wanted')),
          name: 'note.txt',
          expectedSha256: sha256.convert(utf8.encode('the real bytes')).toString(),
        ),
        throwsA(isA<AttachmentException>()),
      );
      expect(files.has('bad-id'), isFalse,
          reason: 'a file that failed its digest must not be left on disk');
    });
  });

  group('lifecycle with items', () {
    test('a file survives while a note points at it', () async {
      final attachment = await files.importFile(
        bytes: chunked(utf8.encode('kept')),
        name: 'kept.txt',
      );
      await store.add(
        kind: PastaKind.note,
        title: 'Has a file',
        attachments: [attachment],
      );

      await store.load();
      expect(files.has(attachment.id), isTrue);
    });

    test('deleting the note takes its files with it', () async {
      final attachment = await files.importFile(
        bytes: chunked(utf8.encode('doomed')),
        name: 'doomed.txt',
      );
      final item = await store.add(
        kind: PastaKind.note,
        title: 'Temporary',
        attachments: [attachment],
      );

      expect(files.has(attachment.id), isTrue);
      await store.delete(item.id);
      expect(files.has(attachment.id), isFalse);
    });

    test('an unreferenced file is collected, a referenced one is not', () async {
      final orphan = await files.importFile(
        bytes: chunked(utf8.encode('nobody wants me')),
        name: 'orphan.txt',
      );
      final kept = await files.importFile(
        bytes: chunked(utf8.encode('spoken for')),
        name: 'kept.txt',
      );
      await store.add(
        kind: PastaKind.note,
        title: 'Keeps one',
        attachments: [kept],
      );

      final removed = await files.collectGarbage(store.referencedAttachmentIds);

      expect(removed, 1);
      expect(files.has(orphan.id), isFalse);
      expect(files.has(kept.id), isTrue);
    });

    test('a tombstone carries no attachments, so peers do not chase them',
        () async {
      final attachment = await files.importFile(
        bytes: chunked(utf8.encode('gone soon')),
        name: 'gone.txt',
      );
      final item = await store.add(
        kind: PastaKind.note,
        title: 'Doomed',
        attachments: [attachment],
      );
      await store.delete(item.id);

      final tombstone = store.allItems.firstWhere((i) => i.id == item.id);
      expect(tombstone.deleted, isTrue);
      expect(tombstone.attachments, isEmpty);
    });
  });

  test('an item round-trips its attachments through JSON', () {
    final original = PastaItem(
      id: 'i1',
      kind: PastaKind.note,
      title: 'With files',
      body: '',
      createdAt: DateTime.utc(2026, 5, 1),
      updatedAt: DateTime.utc(2026, 5, 1),
      attachments: const [
        Attachment(
          id: 'a1',
          name: 'report.pdf',
          mimeType: 'application/pdf',
          size: 2048,
          sha256: 'deadbeef',
        ),
      ],
    );

    final restored = PastaItem.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>);

    expect(restored, isNotNull);
    expect(restored!.attachments, hasLength(1));
    expect(restored.attachments.single.name, 'report.pdf');
    expect(restored.attachments.single.sha256, 'deadbeef');
  });

  test('a note saved before attachments existed still loads', () {
    final restored = PastaItem.fromJson({
      'id': 'legacy',
      'title': 'Old note',
      'details': 'body',
      'createdAt': '09:30:00 AM 14-01-2026',
    });
    expect(restored, isNotNull);
    expect(restored!.attachments, isEmpty);
  });
}
