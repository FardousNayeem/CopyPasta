import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:copypasta/models/attachment.dart';
import 'package:copypasta/models/pasta_item.dart';
import 'package:copypasta/services/attachment_store.dart';
import 'package:copypasta/services/file_intake.dart';
import 'package:copypasta/services/item_store.dart';
import 'package:copypasta/templates/attachment_row.dart';

/// One screen for both kinds. The two old screens differed by a single field
/// and each carried its own copy of the save logic.
class AddItemPage extends StatefulWidget {
  final PastaKind kind;
  const AddItemPage({super.key, required this.kind});

  @override
  State<AddItemPage> createState() => _AddItemPageState();
}

class _AddItemPageState extends State<AddItemPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _attachments = <Attachment>[];

  bool _saving = false;
  bool _saved = false;
  bool _picking = false;

  bool get _isLink => widget.kind == PastaKind.link;

  @override
  void dispose() {
    // Files were copied into the store the moment they were picked. If the
    // screen is abandoned they belong to no note, so take them back out rather
    // than leaving them to the next garbage collection.
    if (!_saved) {
      for (final attachment in _attachments) {
        AttachmentStore.instance.deleteFile(attachment.id);
      }
    }
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _pasteIntoBody() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      if (mounted) _toast('Clipboard is empty');
      return;
    }
    final controller = _isLink ? _titleController : _bodyController;
    controller.text = text;
    controller.selection =
        TextSelection.collapsed(offset: controller.text.length);
    // A pasted link is usually the whole point, so give the note a title from
    // its first line instead of leaving the field empty.
    if (!_isLink && _titleController.text.trim().isEmpty) {
      _titleController.text = text.trim().split('\n').first.trim();
    }
    setState(() {});
  }

  Future<void> _attachFiles() async {
    setState(() => _picking = true);
    final outcome = await pickAndImportFiles();
    if (!mounted) return;

    setState(() {
      _picking = false;
      _attachments.addAll(outcome.imported);
      // An attached file with no title is almost always "here is this file",
      // so name the note after it rather than making the user type it twice.
      if (_titleController.text.trim().isEmpty && _attachments.isNotEmpty) {
        _titleController.text = _attachments.first.name;
      }
    });

    final message = outcome.message;
    if (message != null) _toast(message);
  }

  void _removeAttachment(Attachment attachment) {
    setState(() => _attachments.remove(attachment));
    AttachmentStore.instance.deleteFile(attachment.id);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      await ItemStore.instance.add(
        kind: widget.kind,
        title: _titleController.text,
        body: _isLink ? '' : _bodyController.text,
        attachments: _isLink ? const [] : List.of(_attachments),
      );
      _saved = true;
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not save: $e');
    }
  }

  String? _validateTitle(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      if (!_isLink &&
          (_attachments.isNotEmpty || _bodyController.text.trim().isNotEmpty)) {
        return null;
      }
      return _isLink ? 'Enter a link' : 'Give the note a title';
    }
    if (!_isLink) return null;

    final candidate = text.contains('://') ? text : 'https://$text';
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.host.isEmpty || !uri.host.contains('.')) {
      return 'That does not look like a web address';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isLink ? 'Add link' : 'Add note'),
        actions: [
          IconButton(
            tooltip: 'Paste from clipboard',
            onPressed: _pasteIntoBody,
            icon: const Icon(Icons.content_paste_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            Text(
              _isLink ? 'Link' : 'Title',
              style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _titleController,
              autofocus: true,
              validator: _validateTitle,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              textCapitalization: _isLink
                  ? TextCapitalization.none
                  : TextCapitalization.sentences,
              keyboardType: _isLink ? TextInputType.url : TextInputType.text,
              decoration: InputDecoration(
                hintText: _isLink ? 'https://example.com/page' : 'What is this?',
              ),
              style: text.titleMedium,
              onFieldSubmitted: (_) => _isLink ? _save() : null,
            ),
            if (!_isLink) ...[
              const SizedBox(height: 20),
              Text(
                'Text',
                style:
                    text.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _bodyController,
                minLines: 6,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Paste anything you want on the other device',
                ),
              ),
              const SizedBox(height: 24),
              AttachmentSection(
                attachments: _attachments,
                // Everything here was just copied in, so it is always present.
                isAvailable: (_) => true,
                onRemove: _removeAttachment,
                action: TextButton.icon(
                  onPressed: _picking ? null : _attachFiles,
                  icon: _picking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.attach_file_rounded, size: 18),
                  label: Text(_picking ? 'Adding' : 'Attach'),
                ),
              ),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'save',
        onPressed: _saving ? null : _save,
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        icon: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save_rounded),
        label: Text(_saving ? 'Saving' : 'Save'),
      ),
    );
  }
}
