import 'package:flutter/material.dart';

import 'package:copypasta/models/attachment.dart';
import 'package:copypasta/templates/theme.dart';

/// Icon by file family. Type is carried by the icon and the extension badge,
/// never by colour: the app has one accent and mixing in a palette of
/// file-type colours would break that everywhere a list of files appears.
IconData iconForAttachment(Attachment attachment) {
  final mime = attachment.mimeType;
  if (mime.startsWith('image/')) return Icons.image_outlined;
  if (mime.startsWith('video/')) return Icons.movie_outlined;
  if (mime.startsWith('audio/')) return Icons.audiotrack_rounded;
  if (mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
  if (mime.startsWith('text/') ||
      mime == 'application/json' ||
      mime == 'application/xml') {
    return Icons.description_outlined;
  }
  if (mime.contains('zip') ||
      mime.contains('compressed') ||
      mime.contains('tar') ||
      mime.contains('rar')) {
    return Icons.folder_zip_outlined;
  }
  if (mime.contains('spreadsheet') || mime.contains('excel')) {
    return Icons.table_chart_outlined;
  }
  if (mime.contains('word') || mime.contains('presentation')) {
    return Icons.article_outlined;
  }
  return Icons.insert_drive_file_outlined;
}

/// One attachment in a list.
///
/// [available] is false when the note arrived from another device but the
/// bytes have not. The row stays visible and says so rather than hiding the
/// file, because a note that says "see the attached invoice" with no row at
/// all is more confusing than one that says the file is still on the phone.
class AttachmentRow extends StatelessWidget {
  final Attachment attachment;
  final bool available;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  /// Shown while this specific file is being opened or fetched.
  final bool busy;

  const AttachmentRow({
    super.key,
    required this.attachment,
    this.available = true,
    this.onTap,
    this.onRemove,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final enabled = available && !busy;

    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: AppTheme.borderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 10, onRemove == null ? 14 : 6, 10),
          child: Row(
            children: [
              _TypeBadge(attachment: attachment, muted: !available),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: available
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      busy
                          ? 'Opening'
                          : available
                              ? attachment.readableSize
                              : '${attachment.readableSize} · not on this device yet',
                      style: AppTheme.mono(context, size: 11.5),
                    ),
                  ],
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (onRemove != null)
                IconButton(
                  tooltip: 'Remove',
                  onPressed: onRemove,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 20),
                  style: IconButton.styleFrom(
                      foregroundColor: scheme.onSurfaceVariant),
                )
              else if (available)
                Icon(Icons.open_in_new_rounded,
                    size: 18, color: scheme.onSurfaceVariant)
              else
                Icon(Icons.cloud_off_rounded,
                    size: 18, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final Attachment attachment;
  final bool muted;
  const _TypeBadge({required this.attachment, required this.muted});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground =
        muted ? scheme.onSurfaceVariant : scheme.onPrimaryContainer;

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: muted
            ? scheme.surfaceContainerHighest
            : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(iconForAttachment(attachment), size: 18, color: foreground),
          const SizedBox(height: 1),
          Text(
            attachment.typeLabel,
            style: AppTheme.mono(context, size: 8, color: foreground, weight: 700)
                .copyWith(height: 1),
          ),
        ],
      ),
    );
  }
}

/// A labelled list of attachments with a consistent header, used on both the
/// add screen and the note screen so the two never drift apart.
class AttachmentSection extends StatelessWidget {
  final List<Attachment> attachments;
  final bool Function(Attachment) isAvailable;
  final void Function(Attachment)? onOpen;
  final void Function(Attachment)? onRemove;
  final String? busyAttachmentId;
  final Widget? action;

  const AttachmentSection({
    super.key,
    required this.attachments,
    required this.isAvailable,
    this.onOpen,
    this.onRemove,
    this.busyAttachmentId,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              attachments.isEmpty
                  ? 'Files'
                  : 'Files · ${attachments.length}',
              style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            ?action,
          ],
        ),
        const SizedBox(height: 8),
        if (attachments.isEmpty)
          Text(
            'Nothing attached.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          )
        else
          ...attachments.map((attachment) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AttachmentRow(
                  attachment: attachment,
                  available: isAvailable(attachment),
                  busy: busyAttachmentId == attachment.id,
                  onTap: onOpen == null ? null : () => onOpen!(attachment),
                  onRemove:
                      onRemove == null ? null : () => onRemove!(attachment),
                ),
              )),
      ],
    );
  }
}
