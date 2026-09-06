import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:copypasta/models/pasta_item.dart';
import 'package:copypasta/templates/theme.dart';

/// One row in the list.
///
/// Copy is a button of its own rather than something buried in a detail
/// screen: getting text onto the clipboard is what the app is for.
class Tile extends StatelessWidget {
  final PastaItem item;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final VoidCallback onLongPress;

  const Tile({
    super.key,
    required this.item,
    required this.onTap,
    required this.onCopy,
    required this.onLongPress,
  });

  static final _dateFormat = DateFormat('d MMM y, h:mm a');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final preview = item.body.trim();

    return Material(
      color: scheme.surfaceContainer,
      borderRadius: AppTheme.borderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 12),
                child: Icon(
                  item.isLink ? Icons.link_rounded : Icons.notes_rounded,
                  size: 20,
                  color: scheme.primary,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title.isEmpty ? 'Untitled' : item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: item.isLink ? scheme.primary : scheme.onSurface,
                      ),
                    ),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (item.hasAttachments) ...[
                          Icon(Icons.attach_file_rounded,
                              size: 13, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 2),
                          Text(
                            '${item.attachments.length} \u00b7 ',
                            style: AppTheme.mono(context, size: 11.5),
                          ),
                        ],
                        Flexible(
                          child: Text(
                            '${item.isLink ? 'Link' : 'Note'} \u00b7 '
                            '${_dateFormat.format(item.createdAt.toLocal())}',
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.mono(context, size: 11.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Copy',
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded, size: 20),
                style: IconButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
