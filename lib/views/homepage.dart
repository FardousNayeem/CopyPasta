import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:copypasta/models/pasta_item.dart';
import 'package:copypasta/services/item_store.dart';
import 'package:copypasta/services/lan_service.dart';
import 'package:copypasta/templates/tile.dart';
import 'package:copypasta/views/add_item.dart';
import 'package:copypasta/views/connect.dart';
import 'package:copypasta/views/note_view.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _store = ItemStore.instance;
  final _lan = LanService.instance;
  final _searchController = TextEditingController();

  String _query = '';
  bool _searching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<PastaItem> _filtered() {
    final all = _store.visibleItems;
    if (_query.isEmpty) return all;
    final needle = _query.toLowerCase();
    return all
        .where((i) =>
            i.title.toLowerCase().contains(needle) ||
            i.body.toLowerCase().contains(needle))
        .toList();
  }

  // ------------------------------------------------------------------ actions

  Future<void> _copy(PastaItem item) async {
    await Clipboard.setData(ClipboardData(text: item.copyPayload));
    if (!mounted) return;
    _toast('Copied to clipboard');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1600),
      ));
  }

  Future<void> _open(PastaItem item) async {
    if (!item.isLink) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => NoteView(itemId: item.id)),
      );
      return;
    }

    // Parse the whole thing. The previous version rebuilt the URL from scheme,
    // host and path alone, which silently dropped every query string and
    // fragment, so a link like `youtube.com/watch?v=...` opened the wrong page.
    final raw = item.title.trim();
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
    if (uri == null || uri.host.isEmpty) {
      _toast('That does not look like a link');
      return;
    }
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) _toast('No app could open that link');
    } catch (_) {
      if (mounted) _toast('Could not open that link');
    }
  }

  Future<void> _confirmDelete(PastaItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(item.isLink ? 'Delete link' : 'Delete note'),
        content: Text('"${item.title}" will be removed from this device and '
            'from any device you sync with next.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.delete(item.id);
    if (mounted) _toast('Deleted');
  }

  Future<void> _addItem(PastaKind kind) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddItemPage(kind: kind)),
    );
  }

  // --------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search notes and links',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _query = value.trim()),
              )
            : const Text('CopyPasta'),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _searchController.clear();
                _query = '';
              }
            }),
          ),
          const SizedBox(width: 4),
        ],
      ),

      body: ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          if (!_store.isLoaded) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = _filtered();
          if (items.isEmpty) {
            return _EmptyState(
              searching: _query.isNotEmpty,
              onAddNote: () => _addItem(PastaKind.note),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 120),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              return Tile(
                item: item,
                onTap: () => _open(item),
                onCopy: () => _copy(item),
                onLongPress: () => _confirmDelete(item),
              );
            },
          );
        },
      ),

      bottomNavigationBar: BottomAppBar(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            ListenableBuilder(
              listenable: _lan,
              builder: (context, _) => _ConnectionChip(
                status: _lan.status,
                peerCount: _lan.peers.length,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ConnectPage()),
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),

      floatingActionButtonLocation: FloatingActionButtonLocation.endContained,
      floatingActionButton: MenuAnchor(
        style: MenuStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        menuChildren: [
          MenuItemButton(
            leadingIcon: const Icon(Icons.notes_rounded),
            onPressed: () => _addItem(PastaKind.note),
            child: const Text('Note'),
          ),
          MenuItemButton(
            leadingIcon: const Icon(Icons.link_rounded),
            onPressed: () => _addItem(PastaKind.link),
            child: const Text('Link'),
          ),
        ],
        builder: (context, controller, _) => FloatingActionButton.extended(
          heroTag: 'add',
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add'),
        ),
      ),
    );
  }
}

/// The one place the app reports whether other devices can reach it.
class _ConnectionChip extends StatelessWidget {
  final ServerStatus status;
  final int peerCount;
  final VoidCallback onTap;

  const _ConnectionChip({
    required this.status,
    required this.peerCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    late final IconData icon;
    late final String label;
    late final Color color;

    switch (status) {
      case ServerStatus.running:
        icon = Icons.wifi_tethering_rounded;
        label = peerCount == 0
            ? 'Sharing'
            : 'Sharing  $peerCount ${peerCount == 1 ? 'device' : 'devices'}';
        color = scheme.primary;
      case ServerStatus.starting:
        icon = Icons.wifi_tethering_rounded;
        label = 'Starting';
        color = scheme.onSurfaceVariant;
      case ServerStatus.failed:
        icon = Icons.wifi_tethering_error_rounded;
        label = 'Sharing failed';
        color = scheme.error;
      case ServerStatus.stopped:
        icon = Icons.wifi_tethering_off_rounded;
        label = 'Sharing off';
        color = scheme.onSurfaceVariant;
    }

    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20, color: color),
      label: Text(label, style: TextStyle(color: color)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool searching;
  final VoidCallback onAddNote;

  const _EmptyState({required this.searching, required this.onAddNote});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching ? Icons.search_off_rounded : Icons.content_paste_rounded,
              size: 44,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              searching ? 'No matches' : 'Nothing saved yet',
              style: theme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              searching
                  ? 'Try a shorter search.'
                  : 'Save a note or a link here, then open it from your other '
                      'device over Wi-Fi.',
              textAlign: TextAlign.center,
              style: theme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (!searching) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAddNote,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add a note'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
