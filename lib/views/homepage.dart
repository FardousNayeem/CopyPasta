import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import 'package:copypasta/views/add_note.dart';
import 'package:copypasta/views/edit_note.dart';
import 'package:copypasta/views/add_link.dart';
import 'package:copypasta/templates/tile.dart';

import 'package:copypasta/network/local_server.dart';
import 'package:copypasta/network/mdns_service.dart';
import 'package:copypasta/sync/sync_service.dart';
import 'package:copypasta/network/peer_api.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> items = [];
  OverlayEntry? overlayEntry;
  bool isOverlayVisible = false;
  bool isRefreshed = false;
  bool isConnected = false;
  String? localIp;
  String? connectedPeer;
  String? connectedPeerName;

  late LocalServer _server;
  final MdnsService _mdns = MdnsService();
  final SyncService _sync = SyncService();
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _server = LocalServer(navigatorKey);
    _loadConnection();
    constRefresh();
  }

  Future<void> _loadConnection() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      connectedPeer = prefs.getString('connectedPeer');
      connectedPeerName = prefs.getString('connectedPeerName');
    });
  }

  Future<void> getItems() async {
    final prefs = await SharedPreferences.getInstance();
    final notesData = prefs.getStringList('notes');
    final linksData = prefs.getStringList('links');
    setState(() => items.clear());

    if (notesData != null) {
      items.addAll(notesData.map((e) => jsonDecode(e)).cast<Map<String, dynamic>>());
    }
    if (linksData != null) {
      items.addAll(linksData.map((e) => jsonDecode(e)).cast<Map<String, dynamic>>());
    }

    sortItems();
  }

  void sortItems() {
    items.sort((a, b) {
      final aTime = DateFormat('hh:mm:ss a dd-MM-yyyy').parse(a['createdAt']);
      final bTime = DateFormat('hh:mm:ss a dd-MM-yyyy').parse(b['createdAt']);
      return bTime.compareTo(aTime);
    });
  }

  void constRefresh() {
    Timer.periodic(const Duration(seconds: 0), (_) => getItems());
  }

  Future<void> launchURL(Uri url) async {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }

  void toggleOverlay() {
    if (isOverlayVisible) {
      overlayEntry?.remove();
      isOverlayVisible = false;
    } else {
      showOverlay();
    }
  }

  Future<void> deleteItem(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> notesData = prefs.getStringList('notes') ?? [];
    final List<String> linksData = prefs.getStringList('links') ?? [];

    // Item selected from the merged UI list
    final Map<String, dynamic> itemToDelete = items[index];

    // Try remove from notes (exact JSON match)
    final encoded = jsonEncode(itemToDelete);
    if (notesData.contains(encoded)) {
      notesData.remove(encoded);
      await prefs.setStringList('notes', notesData);
    }
    // Otherwise try remove from links
    else if (linksData.contains(encoded)) {
      linksData.remove(encoded);
      await prefs.setStringList('links', linksData);
    } else {
      // Fallback: match by createdAt + title (handles slight JSON key-order differences)
      final createdAt = itemToDelete['createdAt'] as String?;
      final title = itemToDelete['title'] as String?;

      // notes fallback
      final nIdx = notesData.indexWhere((s) {
        final m = jsonDecode(s) as Map<String, dynamic>;
        return m['createdAt'] == createdAt && m['title'] == title;
      });
      if (nIdx != -1) {
        notesData.removeAt(nIdx);
        await prefs.setStringList('notes', notesData);
      } else {
        // links fallback
        final lIdx = linksData.indexWhere((s) {
          final m = jsonDecode(s) as Map<String, dynamic>;
          return m['createdAt'] == createdAt && m['title'] == title;
        });
        if (lIdx != -1) {
          linksData.removeAt(lIdx);
          await prefs.setStringList('links', linksData);
        }
      }
    }

    // Refresh merged list in UI
    await getItems();
  }


  void showOverlay() {
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 90,
        left: 12,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 120,
              height: 55,
              child: FloatingActionButton.extended(
                label: Text(isConnected ? 'Disconnect' : 'Connect'),
                icon: const Icon(Icons.route),
                heroTag: "connect",
                onPressed: () async {
                  if (!_server.isRunning) {
                    await _server.start();
                    setState(() {
                      isConnected = true;
                      localIp = _server.ip;
                    });

                    final peers = await _mdns.discoverPeers();
                    if (peers.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('No peers found.')),
                      );
                      return;
                    }

                    await showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Select a CopyPasta Peer'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: peers.map((p) {
                            return ListTile(
                              title: Text(p),
                              onTap: () async {
                                Navigator.pop(context);
                                try {
                                  final peer = PeerAPI(p);
                                  await peer.sendData({
                                    'ip': localIp,
                                    'name': 'CopyPasta Device',
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Request sent to $p')),
                                  );
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Connect failed: $e')),
                                  );
                                }
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    );
                  } else {
                    await _server.stop();
                    setState(() {
                      isConnected = false;
                      localIp = null;
                    });
                  }
                },
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: 120,
              height: 55,
              child: FloatingActionButton.extended(
                label: const Text('Sync'),
                icon: const Icon(Icons.sync),
                heroTag: "sync",
                onPressed: () async {
                  if (connectedPeer == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No connected peer yet!')),
                    );
                    return;
                  }
                  try {
                    await _sync.syncWith(connectedPeer!);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Synced with $connectedPeerName')),
                    );
                    getItems();
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Sync failed: $e')),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
    Overlay.of(context)!.insert(overlayEntry!);
    isOverlayVisible = true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    return MaterialApp(
      navigatorKey: navigatorKey,
      home: Scaffold(
        backgroundColor: theme.background,
        appBar: AppBar(
          backgroundColor: theme.primaryContainer,
          centerTitle: true,
          title: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('CopyPasta',
                      style: TextStyle(
                          color: theme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                          fontSize: 25)),
                  const SizedBox(width: 10),
                  Icon(Icons.circle,
                      color: isConnected
                          ? Colors.greenAccent.shade400
                          : Colors.grey.shade500,
                      size: 14),
                ],
              ),
              if (connectedPeerName != null)
                Text('Connected to $connectedPeerName',
                    style: TextStyle(
                        color: theme.onPrimaryContainer.withOpacity(0.8),
                        fontSize: 14)),
              if (localIp != null)
                Text('Local IP: $localIp',
                    style: TextStyle(
                        color: theme.onPrimaryContainer.withOpacity(0.6),
                        fontSize: 13)),
            ],
          ),
          actions: [
            IconButton(
              onPressed: getItems,
              icon: const Icon(Icons.refresh_rounded, size: 30),
            ),
            const SizedBox(width: 15),
          ],
          actionsIconTheme: IconThemeData(color: theme.onPrimaryContainer),
        ),
        floatingActionButton: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SizedBox(
              width: 90,
              height: 50,
              child: FloatingActionButton.extended(
                onPressed: toggleOverlay,
                heroTag: "share",
                label: const Text('Sync', style: TextStyle(fontSize: 16)),
                icon: const Icon(Icons.sync_alt),
                elevation: 0,
              ),
            ),
            const SizedBox(width: 7),
            FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AddNote()));
              },
              heroTag: "addNote",
              label: const Text('Add Note', style: TextStyle(fontSize: 15)),
              icon: const Icon(Icons.note_add),
              elevation: 0,
            ),
            const SizedBox(width: 7),
            FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AddLink()));
              },
              heroTag: "addLink",
              label: const Text('Add Link', style: TextStyle(fontSize: 15)),
              icon: const Icon(Icons.link),
              elevation: 0,
            ),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endContained,
        body: Padding(
          padding: const EdgeInsets.all(8),
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Tile(
                  title: item['title'],
                  date: item['createdAt'],
                  onTap: () {
                    if (item.containsKey('details')) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                EditNote(note: item, noteIndex: index)),
                      );
                    } else {
                      final uri = Uri.parse(item['title']);
                      final scheme = uri.scheme.isNotEmpty ? uri.scheme : 'https';
                      final host = uri.host.isNotEmpty ? uri.host : uri.path;
                      final path = uri.host.isNotEmpty ? uri.path : '/';
                      launchURL(Uri(scheme: scheme, host: host, path: path));
                    }
                  },
                  onLongPress: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: Text(item.containsKey('details')
                            ? 'Delete Note'
                            : 'Delete Link'),
                        content: Text('Delete this item?'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel')),
                          TextButton(
                              onPressed: () {
                                deleteItem(index);
                                Navigator.pop(context);
                              },
                              child: const Text('Delete')),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
