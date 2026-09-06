import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:copypasta/models/attachment.dart';
import 'package:copypasta/models/pasta_item.dart';
import 'package:copypasta/services/attachment_store.dart';

/// Single source of truth for items, on disk and in memory.
///
/// Everything (the UI, the LAN server, the sync client) reads and writes
/// through this one object, so a change from any of them reaches the others
/// immediately. That replaces the old three-second polling timer.
class ItemStore extends ChangeNotifier {
  ItemStore._();
  static final ItemStore instance = ItemStore._();

  static const _key = 'items';
  static const _legacyNotesKey = 'notes';
  static const _legacyLinksKey = 'links';

  /// How long a deleted item's tombstone is kept so the delete can propagate
  /// to peers that were offline. After this it is purged for good.
  static const _tombstoneTtl = Duration(days: 30);

  final _uuid = const Uuid();
  final Map<String, PastaItem> _items = {};

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Visible items, newest first. Tombstones never reach the UI.
  List<PastaItem> get visibleItems {
    final list = _items.values.where((i) => !i.deleted).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Everything including tombstones. This is what sync exchanges.
  List<PastaItem> get allItems => _items.values.toList(growable: false);

  /// Every attachment id any surviving item still points at. Anything on disk
  /// outside this set is garbage.
  Set<String> get referencedAttachmentIds => {
        for (final item in _items.values)
          for (final attachment in item.attachments) attachment.id,
      };

  /// Attachment metadata by id, so a transfer can look up a name and a digest
  /// without walking every item at the call site.
  Attachment? attachmentById(String id) {
    for (final item in _items.values) {
      for (final attachment in item.attachments) {
        if (attachment.id == id) return attachment;
      }
    }
    return null;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _items
      ..clear()
      ..addEntries(
        _decodeList(prefs.getStringList(_key)).map((i) => MapEntry(i.id, i)),
      );

    await _migrateLegacy(prefs);
    _purgeExpiredTombstones();
    await _collectGarbage();

    _loaded = true;
    notifyListeners();
  }

  /// Deletes attachment files nothing points at any more. Safe to call when
  /// the attachment store has not been initialised (tests, headless runs); it
  /// simply does nothing.
  Future<void> _collectGarbage() async {
    if (!AttachmentStore.instance.isReady) return;
    await AttachmentStore.instance.collectGarbage(referencedAttachmentIds);
  }

  /// Folds the pre-0.2 `notes` and `links` lists into the unified store and
  /// removes them. Runs at most once; if it is interrupted the keys survive
  /// and it simply runs again next launch.
  Future<void> _migrateLegacy(SharedPreferences prefs) async {
    final legacy = <PastaItem>[
      ..._decodeList(prefs.getStringList(_legacyNotesKey)),
      ..._decodeList(prefs.getStringList(_legacyLinksKey)),
    ];
    if (legacy.isEmpty) return;

    for (final item in legacy) {
      _items.putIfAbsent(item.id, () => item);
    }
    await _persist(prefs);
    await prefs.remove(_legacyNotesKey);
    await prefs.remove(_legacyLinksKey);
  }

  List<PastaItem> _decodeList(List<String>? raw) {
    if (raw == null) return const [];
    final out = <PastaItem>[];
    for (final line in raw) {
      try {
        final decoded = json.decode(line);
        if (decoded is! Map<String, dynamic>) continue;
        // Legacy rows predate ids. Mint one so the row survives instead of
        // being dropped, and so it can take part in sync.
        if (decoded['id'] is! String || (decoded['id'] as String).isEmpty) {
          decoded['id'] = const Uuid().v4();
        }
        final item = PastaItem.fromJson(decoded);
        if (item != null) out.add(item);
      } catch (_) {
        // One unreadable row must not take down the whole list.
      }
    }
    return out;
  }

  void _purgeExpiredTombstones() {
    final cutoff = DateTime.now().toUtc().subtract(_tombstoneTtl);
    _items.removeWhere((_, i) => i.deleted && i.updatedAt.isBefore(cutoff));
  }

  Future<void> _persist([SharedPreferences? existing]) async {
    final prefs = existing ?? await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      _items.values.map((i) => json.encode(i.toJson())).toList(),
    );
  }

  Future<PastaItem> add({
    required PastaKind kind,
    required String title,
    String body = '',
    List<Attachment> attachments = const [],
  }) async {
    final now = DateTime.now().toUtc();
    final item = PastaItem(
      id: _uuid.v4(),
      kind: kind,
      title: title.trim(),
      body: body.trim(),
      createdAt: now,
      updatedAt: now,
      attachments: attachments,
    );
    _items[item.id] = item;
    await _persist();
    notifyListeners();
    return item;
  }

  Future<void> update(PastaItem item) async {
    _items[item.id] = item.copyWith(updatedAt: DateTime.now().toUtc());
    await _persist();
    // An edit that drops an attachment leaves its bytes behind otherwise.
    await _collectGarbage();
    notifyListeners();
  }

  /// Soft delete. The row stays as a tombstone so peers learn about it; see
  /// [_tombstoneTtl].
  Future<void> delete(String id) async {
    final existing = _items[id];
    if (existing == null) return;
    _items[id] = existing.copyWith(
      deleted: true,
      updatedAt: DateTime.now().toUtc(),
    );
    await _persist();
    // The tombstone carries no attachments, so the note's files are now
    // unreferenced and go with it.
    await _collectGarbage();
    notifyListeners();
  }

  /// Merges a peer's items in. Last write wins on [PastaItem.updatedAt]; a
  /// tombstone beats a live row at the same timestamp, so a delete is never
  /// undone by an equally-old edit.
  ///
  /// Returns how many rows actually changed, which is what the UI reports.
  Future<int> merge(Iterable<PastaItem> incoming) async {
    var changed = 0;
    for (final remote in incoming) {
      final local = _items[remote.id];
      if (local == null) {
        _items[remote.id] = remote;
        changed++;
        continue;
      }
      final remoteWins = remote.updatedAt.isAfter(local.updatedAt) ||
          (remote.updatedAt.isAtSameMomentAs(local.updatedAt) &&
              remote.deleted &&
              !local.deleted);
      if (remoteWins) {
        _items[remote.id] = remote;
        changed++;
      }
    }
    if (changed > 0) {
      await _persist();
      // A note deleted on another device should not leave its video sitting on
      // this one.
      await _collectGarbage();
      notifyListeners();
    }
    return changed;
  }
}
