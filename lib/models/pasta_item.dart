import 'package:intl/intl.dart';

import 'package:copypasta/models/attachment.dart';

/// The kind of thing stored. Files hang off a note as [PastaItem.attachments]
/// rather than being a kind of their own, because in practice a file always
/// arrives with something written about it.
enum PastaKind { note, link, file }

PastaKind _kindFrom(Object? raw) {
  switch (raw) {
    case 'link':
      return PastaKind.link;
    case 'file':
      return PastaKind.file;
    default:
      return PastaKind.note;
  }
}

/// A single note / link.
///
/// Every field that sync depends on is explicit: [id] identifies the item
/// across devices, [updatedAt] resolves conflicts (last write wins) and
/// [deleted] is a tombstone so a delete on one device propagates instead of
/// being resurrected by the next merge.
class PastaItem {
  final String id;
  final PastaKind kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;
  final List<Attachment> attachments;

  const PastaItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
    this.attachments = const [],
  });

  bool get isLink => kind == PastaKind.link;
  bool get hasAttachments => attachments.isNotEmpty;

  /// What gets put on the clipboard. A link has no body, so its title is the
  /// payload; a note's payload is its body when it has one.
  String get copyPayload => body.trim().isEmpty ? title : body;

  PastaItem copyWith({
    String? title,
    String? body,
    DateTime? updatedAt,
    bool? deleted,
    List<Attachment>? attachments,
  }) {
    return PastaItem(
      id: id,
      kind: kind,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
      deleted: deleted ?? this.deleted,
      // A tombstone keeps no attachment list: the files are gone, and carrying
      // the metadata would make peers try to fetch what nobody has.
      attachments: (deleted ?? this.deleted)
          ? const []
          : (attachments ?? this.attachments),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'title': title,
        'body': body,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deleted': deleted,
        'attachments': attachments.map((a) => a.toJson()).toList(),
      };

  /// Tolerant of anything the old schema wrote. Returns null rather than
  /// throwing, because one corrupt entry must not take the whole list down.
  static PastaItem? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;

    final created = _parseDate(json['createdAt']) ?? DateTime.now().toUtc();
    final updated = _parseDate(json['updatedAt']) ?? created;

    // Legacy rows had no `kind`: a note carried `details`, a link did not.
    final PastaKind kind = json.containsKey('kind')
        ? _kindFrom(json['kind'])
        : (json.containsKey('details') ? PastaKind.note : PastaKind.link);

    final attachments = <Attachment>[];
    final rawAttachments = json['attachments'];
    if (rawAttachments is List) {
      for (final entry in rawAttachments) {
        final attachment = Attachment.fromJson(entry);
        if (attachment != null) attachments.add(attachment);
      }
    }

    return PastaItem(
      id: id,
      kind: kind,
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? json['details'] ?? '').toString(),
      createdAt: created,
      updatedAt: updated,
      deleted: json['deleted'] == true,
      attachments: attachments,
    );
  }

  /// Accepts ISO-8601 (current) and `hh:mm:ss a dd-MM-yyyy` (legacy). The old
  /// format is local-time and has no zone, so it is read as local and
  /// normalised to UTC.
  static DateTime? _parseDate(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    final iso = DateTime.tryParse(raw);
    if (iso != null) return iso.toUtc();
    try {
      return DateFormat('hh:mm:ss a dd-MM-yyyy').parse(raw).toUtc();
    } catch (_) {
      return null;
    }
  }
}
