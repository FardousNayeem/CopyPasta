import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:copypasta/models/pasta_item.dart';
import 'package:copypasta/services/item_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = ItemStore.instance;

  group('legacy migration', () {
    test('folds the old notes and links lists into one store', () async {
      SharedPreferences.setMockInitialValues({
        'notes': [
          jsonEncode({
            'id': 'note-1',
            'title': 'Old note',
            'details': 'body text',
            'createdAt': '09:30:00 AM 14-01-2026',
          }),
        ],
        'links': [
          jsonEncode({
            'id': 'link-1',
            'title': 'example.com/a?b=c',
            'createdAt': '10:00:00 AM 14-01-2026',
          }),
        ],
      });

      await store.load();

      final items = store.visibleItems;
      expect(items, hasLength(2));

      final note = items.firstWhere((i) => i.id == 'note-1');
      expect(note.kind, PastaKind.note, reason: 'had `details`, so it is a note');
      expect(note.body, 'body text');

      final link = items.firstWhere((i) => i.id == 'link-1');
      expect(link.kind, PastaKind.link, reason: 'no `details`, so it is a link');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('notes'), isNull, reason: 'legacy key removed');
      expect(prefs.getStringList('links'), isNull);
      expect(prefs.getStringList('items'), hasLength(2));
    });

    test('mints an id for rows that predate ids instead of dropping them',
        () async {
      SharedPreferences.setMockInitialValues({
        'notes': [
          jsonEncode({'title': 'No id here', 'details': '', 'createdAt': '09:30:00 AM 14-01-2026'}),
        ],
      });
      await store.load();
      expect(store.visibleItems, hasLength(1));
      expect(store.visibleItems.single.id, isNotEmpty);
    });

    test('one corrupt row does not take down the rest of the list', () async {
      SharedPreferences.setMockInitialValues({
        'items': [
          '{not json at all',
          jsonEncode({
            'id': 'good',
            'kind': 'note',
            'title': 'Survivor',
            'body': '',
            'createdAt': '2026-01-14T09:30:00.000Z',
            'updatedAt': '2026-01-14T09:30:00.000Z',
          }),
        ],
      });
      await store.load();
      expect(store.visibleItems.map((i) => i.id), ['good']);
    });
  });

  group('merge', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await store.load();
    });

    PastaItem make(String id, {required DateTime at, String title = 'a', bool deleted = false}) {
      return PastaItem(
        id: id,
        kind: PastaKind.note,
        title: title,
        body: '',
        createdAt: at,
        updatedAt: at,
        deleted: deleted,
      );
    }

    test('takes the newer side and leaves the older one alone', () async {
      final early = DateTime.utc(2026, 1, 1);
      final late_ = DateTime.utc(2026, 2, 1);

      await store.merge([make('x', at: late_, title: 'newer')]);
      final changed = await store.merge([make('x', at: early, title: 'older')]);

      expect(changed, 0, reason: 'the older copy must not win');
      expect(store.visibleItems.single.title, 'newer');
    });

    test('a tombstone beats a live row written at the same instant', () async {
      final at = DateTime.utc(2026, 1, 1);
      await store.merge([make('x', at: at, title: 'alive')]);
      await store.merge([make('x', at: at, title: 'alive', deleted: true)]);

      expect(store.visibleItems, isEmpty);
      expect(store.allItems.single.deleted, isTrue,
          reason: 'the tombstone has to survive so peers learn about the delete');
    });

    test('a delete is not resurrected by syncing with a peer that still has it',
        () async {
      final created = DateTime.utc(2026, 1, 1);
      await store.merge([make('x', at: created)]);
      await store.delete('x');

      // The peer never heard about the delete and still offers the old row.
      final changed = await store.merge([make('x', at: created)]);

      expect(changed, 0);
      expect(store.visibleItems, isEmpty);
    });

    test('deleted items stay out of the list but stay in the sync payload',
        () async {
      await store.add(kind: PastaKind.note, title: 'gone');
      final id = store.visibleItems.single.id;
      await store.delete(id);

      expect(store.visibleItems, isEmpty);
      expect(store.allItems, hasLength(1));
    });
  });
}
