import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:copypasta/models/attachment.dart';
import 'package:copypasta/models/pasta_item.dart';
import 'package:copypasta/services/attachment_store.dart';
import 'package:copypasta/services/file_intake.dart';
import 'package:copypasta/services/item_store.dart';
import 'package:copypasta/templates/attachment_row.dart';
import 'package:copypasta/templates/theme.dart';

/// Reads the item by id out of the store rather than taking a copy.
///
/// The old screen was handed a decoded map and a list index. If a sync or a
/// delete landed while it was open, the index pointed at the wrong row and the
/// save wrote over a different note.
class NoteView extends StatefulWidget {
  final String itemId;
  const NoteView({super.key, required this.itemId});

  @override
  State<NoteView> createState() => _NoteViewState();
}

class _NoteViewState extends State<NoteView> {
  final _store = ItemStore.instance;

  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;

  bool _editing = false;
  bool _picking = false;
  String? _openingId;

  /// Attachments as they stand in the editor. Kept separate from the stored
  /// item so a removal can be undone by leaving edit mode without saving.
  late List<Attachment> _draftAttachments;

  static final _dateFormat = DateFormat('d MMM y, h:mm a');

  PastaItem? get _item {
    for (final item in _store.allItems) {
      if (item.id == widget.itemId && !item.deleted) return item;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final item = _item;
    _titleController = TextEditingController(text: item?.title ?? '');
    _bodyController = TextEditingController(text: item?.body ?? '');
    _draftAttachments = List.of(item?.attachments ?? const []);
  }

  bool _isAvailable(Attachment attachment) =>
      AttachmentStore.instance.isReady &&
      AttachmentStore.instance.has(attachment.id);

  Future<void> _openAttachment(Attachment attachment) async {
    setState(() => _openingId = attachment.id);
    final problem = await openAttachment(attachment);
    if (!mounted) return;
    setState(() => _openingId = null);
    if (problem != null) _toast(problem);
  }

  Future<void> _attachFiles() async {
    setState(() => _picking = true);
    final outcome = await pickAndImportFiles();
    if (!mounted) return;
    setState(() {
      _picking = false;
      _draftAttachments.addAll(outcome.imported);
    });
    final message = outcome.message;
    if (message != null) _toast(message);
  }

  void _removeAttachment(Attachment attachment) {
    // The bytes stay on disk until the edit is saved; the store's garbage
    // collection removes them once nothing points at them any more.
    setState(() => _draftAttachments.remove(attachment));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final item = _item;
    if (item == null) {
      _toast('This note no longer exists');
      return;
    }
    if (_titleController.text.trim().isEmpty &&
        _bodyController.text.trim().isEmpty &&
        _draftAttachments.isEmpty) {
      _toast('A note needs a title, some text or a file');
      return;
    }
    await _store.update(item.copyWith(
      title: _titleController.text.trim(),
      body: _bodyController.text,
      attachments: List.of(_draftAttachments),
    ));
    if (!mounted) return;
    setState(() => _editing = false);
    _toast('Saved');
  }

  Future<void> _copy() async {
    final item = _item;
    if (item == null) return;
    await Clipboard.setData(ClipboardData(text: item.copyPayload));
    if (!mounted) return;
    _toast('Copied to clipboard');
  }

  Future<void> _delete() async {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete note'),
        content: const Text(
            'It will be removed from this device and from any device you sync '
            'with next.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.delete(widget.itemId);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final item = _item;

        if (item == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Note')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_outline_rounded,
                        size: 44, color: scheme.onSurfaceVariant),
                    const SizedBox(height: 16),
                    Text('This note is gone',
                        style: text.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(
                      'It was deleted here or on a device you synced with.',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back to list'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(_editing ? 'Editing' : 'Note'),
            actions: [
              IconButton(
                tooltip: 'Copy',
                onPressed: _copy,
                icon: const Icon(Icons.copy_rounded),
              ),
              IconButton(
                tooltip: _editing ? 'Save' : 'Edit',
                onPressed: () {
                  if (_editing) {
                    _save();
                  } else {
                    setState(() {
                      _draftAttachments = List.of(item.attachments);
                      _editing = true;
                    });
                  }
                },
                icon: Icon(_editing ? Icons.check_rounded : Icons.edit_rounded),
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              TextField(
                controller: _titleController,
                enabled: _editing,
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                decoration: const InputDecoration(hintText: 'Title'),
              ),
              const SizedBox(height: 8),
              Text(
                'Saved ${_dateFormat.format(item.createdAt.toLocal())}'
                '${item.updatedAt.difference(item.createdAt).inMinutes > 1 ? '  edited ${_dateFormat.format(item.updatedAt.toLocal())}' : ''}',
                style: AppTheme.mono(context, size: 11.5),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _bodyController,
                enabled: _editing,
                minLines: 8,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Text'),
              ),
              const SizedBox(height: 24),
              AttachmentSection(
                attachments:
                    _editing ? _draftAttachments : item.attachments,
                isAvailable: _isAvailable,
                busyAttachmentId: _openingId,
                onOpen: _editing ? null : _openAttachment,
                onRemove: _editing ? _removeAttachment : null,
                action: _editing
                    ? TextButton.icon(
                        onPressed: _picking ? null : _attachFiles,
                        icon: _picking
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.attach_file_rounded, size: 18),
                        label: Text(_picking ? 'Adding' : 'Attach'),
                      )
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }
}
