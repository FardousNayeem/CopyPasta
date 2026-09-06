import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';

import 'package:copypasta/models/attachment.dart';
import 'package:copypasta/services/attachment_store.dart';

/// What came back from a pick. Partial success is normal: one file over the
/// size limit should not throw away the four that were fine.
class ImportOutcome {
  final List<Attachment> imported;
  final List<String> problems;
  final bool cancelled;

  const ImportOutcome({
    this.imported = const [],
    this.problems = const [],
    this.cancelled = false,
  });

  bool get isEmpty => imported.isEmpty && problems.isEmpty;

  /// One line for a snackbar, or null when there is nothing worth saying.
  String? get message {
    if (cancelled || isEmpty) return null;
    if (problems.isEmpty) {
      return 'Attached ${imported.length} file'
          '${imported.length == 1 ? '' : 's'}';
    }
    if (imported.isEmpty) return problems.first;
    return 'Attached ${imported.length}, skipped ${problems.length}: '
        '${problems.first}';
  }
}

/// Opens the platform file picker and copies whatever the user chose into the
/// attachment store.
///
/// Files are streamed from the picker straight to disk, never held whole in
/// memory, so attaching a long video does not put the app at risk of being
/// killed for its heap size.
Future<ImportOutcome> pickAndImportFiles() async {
  final List<PlatformFile> picked;
  try {
    picked = await FilePicker.pickFiles(dialogTitle: 'Attach files');
  } catch (e) {
    return ImportOutcome(problems: ['Could not open the file picker: $e']);
  }

  if (picked.isEmpty) return const ImportOutcome(cancelled: true);

  final imported = <Attachment>[];
  final problems = <String>[];

  for (final file in picked) {
    try {
      final size = file.lengthSync() ?? await file.length();
      final attachment = await AttachmentStore.instance.importFile(
        bytes: file.readAsByteStream(),
        name: file.name,
        knownSize: size,
      );
      imported.add(attachment);
    } on AttachmentException catch (e) {
      problems.add(e.message);
    } catch (e) {
      problems.add('${file.name}: $e');
    }
  }

  return ImportOutcome(imported: imported, problems: problems);
}

/// Hands an attachment to whatever app on the device handles that type.
///
/// Returns null on success, or a sentence explaining why not.
Future<String?> openAttachment(Attachment attachment) async {
  try {
    final path =
        await AttachmentStore.instance.materialiseForOpening(attachment);
    final result = await OpenFilex.open(path, type: attachment.mimeType);
    switch (result.type) {
      case ResultType.done:
        return null;
      case ResultType.noAppToOpen:
        return 'No app on this device can open ${attachment.name}.';
      case ResultType.permissionDenied:
        return 'Permission to open ${attachment.name} was denied.';
      case ResultType.fileNotFound:
        return '${attachment.name} is not on this device yet.';
      case ResultType.error:
        return 'Could not open ${attachment.name}.';
    }
  } on AttachmentException catch (e) {
    return e.message;
  } catch (e) {
    return 'Could not open ${attachment.name}: $e';
  }
}
