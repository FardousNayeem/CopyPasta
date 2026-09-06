import 'dart:math' as math;

/// A file hanging off a note.
///
/// [id] doubles as the name the file is stored under on every device, so the
/// same attachment lands at the same path everywhere and sync can ask for it
/// by name. [sha256] is what makes a transfer verifiable: a file that arrives
/// with the wrong digest is discarded rather than saved.
class Attachment {
  final String id;
  final String name;
  final String mimeType;
  final int size;
  final String sha256;

  const Attachment({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.sha256,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mimeType': mimeType,
        'size': size,
        'sha256': sha256,
      };

  static Attachment? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    return Attachment(
      id: id,
      name: (raw['name'] ?? id).toString(),
      mimeType: (raw['mimeType'] ?? 'application/octet-stream').toString(),
      size: (raw['size'] as num?)?.toInt() ?? 0,
      sha256: (raw['sha256'] ?? '').toString(),
    );
  }

  /// `1.4 MB`, not `1468006 bytes`.
  String get readableSize {
    if (size < 1024) return '$size B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = size / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final decimals = value >= 100 ? 0 : (value >= 10 ? 1 : 1);
    return '${value.toStringAsFixed(decimals)} ${units[unit]}';
  }

  String get extension {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  bool get isImage => mimeType.startsWith('image/');

  /// A short label for the file-type badge, capped so a long extension cannot
  /// blow out the layout.
  String get typeLabel {
    final ext = extension;
    if (ext.isEmpty) return 'FILE';
    return ext.substring(0, math.min(4, ext.length)).toUpperCase();
  }
}

/// Extension to MIME type. Deliberately a small table rather than a dependency:
/// the list only has to cover what a person actually moves between their phone
/// and their laptop, and anything unknown falls back to a type every platform
/// treats as "just bytes".
String mimeTypeForName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return 'application/octet-stream';
  switch (name.substring(dot + 1).toLowerCase()) {
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'heic':
      return 'image/heic';
    case 'svg':
      return 'image/svg+xml';
    case 'bmp':
      return 'image/bmp';
    case 'pdf':
      return 'application/pdf';
    case 'txt':
    case 'log':
      return 'text/plain';
    case 'md':
      return 'text/markdown';
    case 'csv':
      return 'text/csv';
    case 'json':
      return 'application/json';
    case 'xml':
      return 'application/xml';
    case 'html':
    case 'htm':
      return 'text/html';
    case 'zip':
      return 'application/zip';
    case '7z':
      return 'application/x-7z-compressed';
    case 'rar':
      return 'application/vnd.rar';
    case 'gz':
      return 'application/gzip';
    case 'tar':
      return 'application/x-tar';
    case 'mp3':
      return 'audio/mpeg';
    case 'm4a':
      return 'audio/mp4';
    case 'wav':
      return 'audio/wav';
    case 'ogg':
      return 'audio/ogg';
    case 'mp4':
      return 'video/mp4';
    case 'mov':
      return 'video/quicktime';
    case 'mkv':
      return 'video/x-matroska';
    case 'webm':
      return 'video/webm';
    case 'doc':
      return 'application/msword';
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'xls':
      return 'application/vnd.ms-excel';
    case 'xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    case 'ppt':
      return 'application/vnd.ms-powerpoint';
    case 'pptx':
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    case 'apk':
      return 'application/vnd.android.package-archive';
    default:
      return 'application/octet-stream';
  }
}
