import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:copypasta/models/attachment.dart';
import 'package:copypasta/services/attachment_store.dart';
import 'package:copypasta/services/background_service.dart';
import 'package:copypasta/services/lan_service.dart';
import 'package:copypasta/templates/theme.dart';

/// Everything about reaching this device from another one.
///
/// The server itself is owned by [LanService] and runs for the life of the
/// app; this screen only shows and steers it.
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final _lan = LanService.instance;
  final _background = BackgroundService.instance;

  bool _pinVisible = false;
  String? _syncingPeerId;
  String? _syncProgress;
  int _scanDone = 0;
  int _scanTotal = 0;
  int _storedBytes = 0;

  @override
  void initState() {
    super.initState();
    _lan.refreshAddresses();
    _refreshStorage();
  }

  Future<void> _refreshStorage() async {
    final bytes = await AttachmentStore.instance.totalBytes();
    if (!mounted) return;
    setState(() => _storedBytes = bytes);
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? scheme.errorContainer : null,
        // Long enough to actually read a failure reason.
        duration: Duration(seconds: error ? 5 : 3),
      ));
  }

  Future<void> _copy(String value, String what) async {
    await Clipboard.setData(ClipboardData(text: value));
    _toast('$what copied');
  }

  Future<void> _scan() async {
    setState(() {
      _scanDone = 0;
      _scanTotal = 0;
    });
    await _lan.scanSubnet(onProgress: (done, total) {
      if (!mounted) return;
      setState(() {
        _scanDone = done;
        _scanTotal = total;
      });
    });
    if (!mounted) return;
    _toast(_lan.peers.isEmpty
        ? 'No other CopyPasta devices answered on this network.'
        : 'Found ${_lan.peers.length} device${_lan.peers.length == 1 ? '' : 's'}.');
  }

  Future<void> _sync(Peer peer) async {
    final pin = await _askPin(peer);
    if (pin == null) return;

    setState(() {
      _syncingPeerId = peer.id;
      _syncProgress = 'Connecting';
    });
    try {
      final result = await _lan.syncWith(
        peer,
        pin,
        // Files can take a while. Saying which one is moving beats a spinner
        // that looks identical whether it is working or hung.
        onProgress: (message) {
          if (mounted) setState(() => _syncProgress = message);
        },
      );
      await _lan.rememberPin(peer.id, pin);
      if (!mounted) return;
      _toast(result.summary, error: result.hasProblems);
      await _refreshStorage();
    } on SyncException catch (e) {
      if (!mounted) return;
      _toast(e.message, error: true);
    } finally {
      if (mounted) {
        setState(() {
          _syncingPeerId = null;
          _syncProgress = null;
        });
      }
    }
  }

  Future<void> _toggleBackground(bool wanted) async {
    if (!wanted) {
      await _background.disable();
      return;
    }
    final result = await _background.enable(
      detail: _lan.reachableUrls.isEmpty
          ? 'Waiting for a Wi-Fi connection'
          : 'Open ${_lan.reachableUrls.first}',
    );
    if (!mounted) return;
    switch (result) {
      case BackgroundEnableResult.started:
        _toast('CopyPasta will keep sharing in the background.');
      case BackgroundEnableResult.notificationDenied:
        _toast('Android needs notification permission to keep this running.',
            error: true);
      case BackgroundEnableResult.notificationPermanentlyDenied:
        _toast(
            'Turn notifications on for CopyPasta in Android settings, then try '
            'again.',
            error: true);
      case BackgroundEnableResult.notSupported:
        _toast('This platform does not need it.');
      case BackgroundEnableResult.failed:
        _toast(_background.lastError ?? 'The background service did not start.',
            error: true);
    }
  }

  Future<String?> _askPin(Peer peer) async {
    final remembered = _lan.savedPinFor(peer.id);
    if (remembered != null) return remembered;

    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('PIN for ${peer.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Open CopyPasta on ${peer.name} and read the PIN on its Connect '
              'screen.',
              style: Theme.of(dialogContext).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 6,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 26, letterSpacing: 8),
              decoration: const InputDecoration(counterText: '', hintText: '000000'),
              onSubmitted: (value) => Navigator.pop(dialogContext, value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Sync'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (pin == null || pin.trim().length != 6) return null;
    return pin.trim();
  }

  Future<void> _addManually() async {
    final controller = TextEditingController();
    final entered = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add by address'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Type the address shown on the other device.',
              style: Theme.of(dialogContext).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(hintText: '192.168.1.42'),
              onSubmitted: (value) => Navigator.pop(dialogContext, value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Check'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (entered == null || entered.trim().isEmpty) return;

    final peer = await _lan.addManualPeer(entered);
    if (!mounted) return;
    _toast(
      peer == null
          ? 'Nothing answered at that address on port ${LanService.httpPort}.'
          : 'Found ${peer.name}.',
      error: peer == null,
    );
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _lan.deviceName);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Name this device'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Phone'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    await _lan.setDeviceName(name);
  }

  // --------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Share over Wi-Fi')),
      body: ListenableBuilder(
        listenable: _lan,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            _ThisDeviceCard(
              lan: _lan,
              pinVisible: _pinVisible,
              onTogglePin: () => setState(() => _pinVisible = !_pinVisible),
              onCopy: _copy,
              onRename: _rename,
              onRegeneratePin: () async {
                await _lan.regeneratePin();
                if (mounted) _toast('New PIN. Other devices will ask for it again.');
              },
            ),
            if (_lan.status == ServerStatus.failed && _lan.lastError != null) ...[
              const SizedBox(height: 12),
              _ErrorCard(
                message: _lan.lastError!,
                onRetry: () => _lan.start(),
              ),
            ],
            if (_background.isSupported) ...[
              const SizedBox(height: 12),
              ListenableBuilder(
                listenable: _background,
                builder: (context, _) => _BackgroundCard(
                  enabled: _background.isEnabled,
                  onChanged: _toggleBackground,
                ),
              ),
            ],
            const SizedBox(height: 12),
            _StorageCard(bytes: _storedBytes),
            const SizedBox(height: 28),
            _SectionHeader(
              title: 'Other devices',
              trailing: _lan.isScanning
                  ? TextButton(
                      onPressed: _lan.cancelScan,
                      child: const Text('Stop'),
                    )
                  : TextButton.icon(
                      onPressed: _scan,
                      icon: const Icon(Icons.radar_rounded, size: 18),
                      label: const Text('Scan'),
                    ),
            ),
            if (_lan.isScanning) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _scanTotal == 0 ? null : _scanDone / _scanTotal,
              ),
              const SizedBox(height: 6),
              Text(
                'Checking $_scanDone of $_scanTotal addresses',
                style: AppTheme.mono(context, size: 11.5),
              ),
            ],
            const SizedBox(height: 12),
            if (_lan.peers.isEmpty)
              _NoPeers(onScan: _lan.isScanning ? null : _scan, onManual: _addManually)
            else
              ..._lan.peers.map((peer) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _PeerTile(
                      peer: peer,
                      busy: _syncingPeerId == peer.id,
                      progress:
                          _syncingPeerId == peer.id ? _syncProgress : null,
                      onSync: () => _sync(peer),
                      onForgetPin: _lan.savedPinFor(peer.id) == null
                          ? null
                          : () async {
                              await _lan.forgetPin(peer.id);
                              if (mounted) _toast('PIN forgotten');
                            },
                    ),
                  )),
            if (_lan.peers.isNotEmpty) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addManually,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add by address'),
                ),
              ),
            ],
            const SizedBox(height: 28),
            const _TroubleshootingCard(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ThisDeviceCard extends StatelessWidget {
  final LanService lan;
  final bool pinVisible;
  final VoidCallback onTogglePin;
  final Future<void> Function(String value, String what) onCopy;
  final VoidCallback onRename;
  final VoidCallback onRegeneratePin;

  const _ThisDeviceCard({
    required this.lan,
    required this.pinVisible,
    required this.onTogglePin,
    required this.onCopy,
    required this.onRename,
    required this.onRegeneratePin,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final running = lan.status == ServerStatus.running;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('This device',
                          style: text.labelLarge
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              lan.deviceName,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Rename',
                            visualDensity: VisualDensity.compact,
                            onPressed: onRename,
                            icon: const Icon(Icons.edit_rounded, size: 18),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: running || lan.status == ServerStatus.starting,
                  onChanged: (value) => value ? lan.start() : lan.stop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            if (!running) ...[
              Text(
                lan.status == ServerStatus.starting
                    ? 'Starting the sharing server.'
                    : 'Sharing is off. Other devices cannot reach this one.',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ] else ...[
              Text('Open in a browser on the other device',
                  style: text.labelLarge
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              if (lan.reachableUrls.isEmpty)
                Text(
                  'No Wi-Fi address yet. Connect this device to a network.',
                  style: text.bodyMedium?.copyWith(color: scheme.error),
                )
              else
                ...lan.reachableUrls.map((url) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: InkWell(
                        borderRadius: AppTheme.borderRadius,
                        onTap: () => onCopy(url, 'Address'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(url,
                                    style: AppTheme.mono(context,
                                        size: 15, color: scheme.primary)),
                              ),
                              Icon(Icons.copy_rounded,
                                  size: 16, color: scheme.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ),
                    )),
              const SizedBox(height: 20),
              Text('PIN',
                  style: text.labelLarge
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    pinVisible ? lan.pin : String.fromCharCodes(List.filled(6, 0x2022)),
                    style: AppTheme.mono(context,
                            size: 28, color: scheme.onSurface, weight: 600)
                        .copyWith(letterSpacing: 6),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: pinVisible ? 'Hide PIN' : 'Show PIN',
                    onPressed: onTogglePin,
                    icon: Icon(pinVisible
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded),
                  ),
                  IconButton(
                    tooltip: 'New PIN',
                    onPressed: onRegeneratePin,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'The other device asks for this once, then remembers it.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PeerTile extends StatelessWidget {
  final Peer peer;
  final bool busy;
  final String? progress;
  final VoidCallback onSync;
  final VoidCallback? onForgetPin;

  const _PeerTile({
    required this.peer,
    required this.busy,
    required this.progress,
    required this.onSync,
    required this.onForgetPin,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Icon(Icons.devices_rounded, color: scheme.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(peer.name,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    progress ?? '${peer.address}:${peer.port}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.mono(
                      context,
                      size: 12,
                      color: progress == null ? null : scheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            if (onForgetPin != null)
              IconButton(
                tooltip: 'Forget saved PIN',
                onPressed: busy ? null : onForgetPin,
                icon: const Icon(Icons.key_off_rounded, size: 20),
              ),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: busy ? null : onSync,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded, size: 18),
              label: Text(busy ? 'Syncing' : 'Sync'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        ?trailing,
      ],
    );
  }
}

class _NoPeers extends StatelessWidget {
  final VoidCallback? onScan;
  final VoidCallback onManual;
  const _NoPeers({required this.onScan, required this.onManual});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('No devices found yet',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              'Devices announce themselves every few seconds. If nothing shows '
              'up, scan the network or type the address by hand.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onScan,
                  icon: const Icon(Icons.radar_rounded, size: 18),
                  label: const Text('Scan network'),
                ),
                OutlinedButton.icon(
                  onPressed: onManual,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add by address'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Sharing could not start',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: scheme.onErrorContainer,
                          )),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(message,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onErrorContainer)),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.onErrorContainer,
                  foregroundColor: scheme.errorContainer,
                ),
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TroubleshootingCard extends StatelessWidget {
  const _TroubleshootingCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    const points = <String>[
      'Both devices have to be on the same Wi-Fi network, and the router must '
          'not have client isolation or guest mode switched on.',
      'On Windows, allow CopyPasta through the firewall the first time it asks. '
          'A browser needs no permission at all.',
      'CopyPasta has to be running on the device that is sharing. Turn on '
          '"Keep sharing in the background" so leaving the app does not stop it.',
      'A VPN on either device usually breaks this, because it moves traffic off '
          'the local network.',
    ];

    return Card(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('If nothing connects',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ...points.map((point) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 7, right: 10),
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: scheme.onSurfaceVariant,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(point,
                            style: text.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}


/// The one control that decides whether closing the app stops sharing.
class _BackgroundCard extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _BackgroundCard({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.motion_photos_on_rounded,
                    size: 20, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Keep sharing in the background',
                      style: text.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                Switch(value: enabled, onChanged: onChanged),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                enabled
                    ? 'A notification keeps this device reachable while you are '
                        'in other apps or the screen is off. Swiping CopyPasta '
                        'out of recents still stops it.'
                    : 'Without this, Android may stop sharing as soon as you '
                        'leave the app.',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How much disk the attached files take, so a phone does not quietly fill up.
class _StorageCard extends StatelessWidget {
  final int bytes;
  const _StorageCard({required this.bytes});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Row(
          children: [
            Icon(Icons.folder_outlined, size: 20, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Attached files on this device',
                  style: text.bodyLarge),
            ),
            Text(
              Attachment(
                id: '',
                name: '',
                mimeType: '',
                size: bytes,
                sha256: '',
              ).readableSize,
              style: AppTheme.mono(context, size: 14, color: scheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
