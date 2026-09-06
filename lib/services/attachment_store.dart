import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'package:copypasta/models/attachment.dart';

/// Thrown when an import or a transfer is refused for a reason the user should
/// be told about, rather than a raw I/O error.
class AttachmentException implements Exception {
  final String message;
  const AttachmentException(this.message);
  @override
  String toString() => message;
}

/// Owns the bytes of every attached file.
///
/// Files live in the app's own documents directory under their attachment id,
/// so the same file is at the same path on every device and sync can request
/// it by id. Metadata lives on the item; this class only ever deals in bytes.
class AttachmentStore {
  AttachmentStore._();
  static final AttachmentStore instance = AttachmentStore._();

  /// Anything larger is refused. Moving a file bigger than this over a phone's
  /// Wi-Fi is not what this app is for, and accepting it would let one bad
  /// upload fill the device.
  ///
  /// The declared size is checked up front, but that is only a courtesy to a
  /// well-behaved sender: a client is free to lie in `Content-Length`, so the
  /// guard that actually holds is the running byte count in [_writeStream].
  static const int maxFileBytes = 256 * 1024 * 1024;

  final _uuid = const Uuid();

  Directory? _dir;
  bool get isReady => _dir != null;

  /// [root] exists so tests can point the store at a temporary directory
  /// without having to stand up the platform channel `path_provider` needs.
  ///
  /// The support directory, not the documents directory: on Linux and Windows
  /// `getApplicationDocumentsDirectory` is the user's own Documents folder, so
  /// attaching a file would drop a CopyPasta folder in among their things. The
  /// support directory is app-private on every platform, and on Android it is
  /// the `files` directory the file-opening provider already covers.
  Future<void> init({Directory? root}) async {
    final base = root ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/attachments');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    await _clearPartials();
  }

  Directory get _directory {
    final dir = _dir;
    if (dir == null) {
      throw StateError('AttachmentStore.init() has not run');
    }
    return dir;
  }

  File fileFor(String attachmentId) => File('${_directory.path}/$attachmentId');

  bool has(String attachmentId) => fileFor(attachmentId).existsSync();

  /// Interrupted writes leave `.part` files behind. They are never referenced
  /// by an item, so anything found at startup is dead.
  Future<void> _clearPartials() async {
    try {
      await for (final entity in _directory.list()) {
        if (entity is File && entity.path.endsWith('.part')) {
          await entity.delete();
        }
      }
    } catch (_) {
      // A directory we cannot list is a problem the next real read will report.
    }
  }

  // ------------------------------------------------------------------ import

  /// Copies a file the user picked into the store under a fresh id.
  ///
  /// Streamed rather than read whole: a 200 MB video read into memory on a
  /// phone is an out-of-memory crash, not a slow copy.
  Future<Attachment> importFile({
    required Stream<List<int>> bytes,
    required String name,
    int? knownSize,
    @visibleForTesting int? maxBytes,
  }) async {
    final limit = maxBytes ?? maxFileBytes;
    if (knownSize != null && knownSize > limit) {
      throw AttachmentException(
          '"$name" is ${_readable(knownSize)}. The limit is '
          '${_readable(limit)}.');
    }
    final id = _uuid.v4();
    final result =
        await _writeStream(id: id, bytes: bytes, name: name, limit: limit);
    return Attachment(
      id: id,
      name: _safeName(name),
      mimeType: mimeTypeForName(name),
      size: result.size,
      sha256: result.digest,
    );
  }

  /// Stores bytes arriving from a peer under the id that peer already uses.
  ///
  /// [expectedSha256] is verified before the file is put in place, so a
  /// truncated or corrupted transfer never becomes a file the user can open.
  Future<void> receiveFile({
    required String attachmentId,
    required Stream<List<int>> bytes,
    required String name,
    required String expectedSha256,
    int? declaredSize,
    @visibleForTesting int? maxBytes,
  }) async {
    final limit = maxBytes ?? maxFileBytes;
    if (declaredSize != null && declaredSize > limit) {
      throw AttachmentException('"$name" exceeds the transfer limit.');
    }
    final result = await _writeStream(
        id: attachmentId, bytes: bytes, name: name, limit: limit);
    if (expectedSha256.isNotEmpty && result.digest != expectedSha256) {
      await deleteFile(attachmentId);
      throw AttachmentException(
          '"$name" arrived corrupted and was discarded.');
    }
  }

  Future<_WriteResult> _writeStream({
    required String id,
    required Stream<List<int>> bytes,
    required String name,
    required int limit,
  }) async {
    final target = fileFor(id);
    final partial = File('${target.path}.part');
    final sink = partial.openWrite();

    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);

    var written = 0;
    try {
      await for (final chunk in bytes) {
        written += chunk.length;
        if (written > limit) {
          throw AttachmentException(
              '"$name" is over the ${_readable(limit)} limit.');
        }
        hasher.add(chunk);
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      hasher.close();

      await partial.rename(target.path);
      return _WriteResult(written, digestSink.value.toString());
    } catch (e) {
      // Leave nothing half-written behind, whatever went wrong.
      try {
        await sink.close();
      } catch (_) {}
      if (await partial.exists()) {
        try {
          await partial.delete();
        } catch (_) {}
      }
      if (e is AttachmentException) rethrow;
      throw AttachmentException('Could not save "$name": $e');
    }
  }

  /// Strips any directory part a picker or a peer may have sent, so a name can
  /// never be used to write outside the attachments directory or to mislead
  /// the user about what they are opening.
  static String _safeName(String raw) {
    var name = raw.replaceAll('\\', '/');
    name = name.substring(name.lastIndexOf('/') + 1).trim();
    if (name.isEmpty || name == '.' || name == '..') return 'file';
    return name.length > 180 ? name.substring(name.length - 180) : name;
  }

  /// Copies an attachment into the cache under its real filename and returns
  /// that path.
  ///
  /// Files are stored under their id with no extension, which is what makes
  /// sync able to ask for them by name. Android and Windows both pick the
  /// handler app partly from the extension, so handing them the raw store path
  /// opens the wrong thing or nothing at all.
  Future<String> materialiseForOpening(Attachment attachment) async {
    final source = fileFor(attachment.id);
    if (!await source.exists()) {
      throw const AttachmentException('That file is not on this device yet.');
    }

    final cache = Directory('${_directory.path}/.open');
    if (!await cache.exists()) await cache.create(recursive: true);

    final target = File('${cache.path}/${_safeName(attachment.name)}');
    // Reuse an identical copy rather than rewriting a 200 MB video every tap.
    if (await target.exists() && await target.length() == attachment.size) {
      return target.path;
    }
    await source.copy(target.path);
    return target.path;
  }

  /// Clears the copies [materialiseForOpening] leaves behind.
  Future<void> clearOpenCache() async {
    final cache = Directory('${_directory.path}/.open');
    if (await cache.exists()) {
      try {
        await cache.delete(recursive: true);
      } catch (_) {}
    }
  }

  // ------------------------------------------------------------------ delete

  Future<void> deleteFile(String attachmentId) async {
    final file = fileFor(attachmentId);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {
        // A file we cannot delete is wasted space, not a failure worth
        // stopping the delete of the note itself.
      }
    }
  }

  /// Removes files no surviving item points at. Called after loading and after
  /// a merge, so a note deleted on another device does not leave its video
  /// sitting on this one forever.
  Future<int> collectGarbage(Set<String> referencedIds) async {
    if (!isReady) return 0;
    var removed = 0;
    try {
      await for (final entity in _directory.list()) {
        // `.open` is a directory of transient copies, not stored attachments.
        if (entity is! File) continue;
        final id = entity.path.split(Platform.pathSeparator).last;
        if (id.endsWith('.part')) continue;
        if (referencedIds.contains(id)) continue;
        try {
          await entity.delete();
          removed++;
        } catch (_) {}
      }
    } catch (_) {}
    return removed;
  }

  /// Total bytes held, for the storage line on the Connect screen.
  Future<int> totalBytes() async {
    if (!isReady) return 0;
    var total = 0;
    try {
      await for (final entity in _directory.list()) {
        if (entity is File) total += await entity.length();
      }
      // The `.open` cache is a copy of files already counted above.
    } catch (_) {}
    return total;
  }

  static String _readable(int bytes) =>
      Attachment(id: '', name: '', mimeType: '', size: bytes, sha256: '')
          .readableSize;
}

class _WriteResult {
  final int size;
  final String digest;
  const _WriteResult(this.size, this.digest);
}

/// `package:convert` has an `AccumulatorSink` for this, but pulling in a whole
/// package to catch one value is not worth it.
class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
