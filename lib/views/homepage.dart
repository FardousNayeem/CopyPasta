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
  const HomePage({Key? key});

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

  final LocalServer _server = LocalServer();
  final SyncService _sync = SyncService();
  final MdnsService _mdns = MdnsService();

  @override
  void initState() {
    super.initState();
    constRefresh();
  }

  Future<void> getItems() async {
    final prefs = await SharedPreferences.getInstance();
    final notesData = prefs.getStringList('notes');
    final linksData = prefs.getStringList('links');

    setState(() => items.clear());

    if (notesData != null) {
      items.addAll(notesData.map((note) => json.decode(note)).cast<Map<String, dynamic>>());
    }

    if (linksData != null) {
      items.addAll(linksData.map((link) => json.decode(link)).cast<Map<String, dynamic>>());
    }

    sortItems();
  }

  void sortItems() {
    items.sort((a, b) {
      DateTime timeA = DateFormat('hh:mm:ss a dd-MM-yyyy').parse(a['createdAt']);
      DateTime timeB = DateFormat('hh:mm:ss a dd-MM-yyyy').parse(b['createdAt']);
      return timeB.compareTo(timeA);
    });
  }

  Future<void> deleteItem(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> notesData = prefs.getStringList('notes') ?? [];
    final List<String> linksData = prefs.getStringList('links') ?? [];

    Map<String, dynamic> itemToDelete = items[index];

    if (notesData.contains(jsonEncode(itemToDelete))) {
      notesData.remove(jsonEncode(itemToDelete));
      await prefs.setStringList('notes', notesData);
    } else if (linksData.contains(jsonEncode(itemToDelete))) {
      linksData.remove(jsonEncode(itemToDelete));
      await prefs.setStringList('links', linksData);
    }
    refreshData();
  }

  void refreshData() {
    if (!isRefreshed) {
      getItems();
      setState(() => isRefreshed = true);
      Future.delayed(const Duration(seconds: 1), () {
        setState(() => isRefreshed = false);
      });
    }
  }

  void constRefresh() {
    Timer.periodic(const Duration(seconds: 0), (Timer timer) {
      refreshData();
    });
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

  void showOverlay() {
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 90,
        left: 12,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Connect
            SizedBox(
              width: 120,
              height: 55,
              child: FloatingActionButton.extended(
                onPressed: () async {
                  if (!_server.isRunning) {
                    await _server.start();
                    setState(() {
                      isConnected = true;
                      localIp = _server.ip;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Hosting CopyPasta at ${_server.ip}:${_server.port}')),
                    );
                  } else {
                    await _server.stop();
                    setState(() {
                      isConnected = false;
                      localIp = null;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Server stopped')),
                    );
                  }
                },
                label: Text(isConnected ? 'Disconnect' : 'Connect'),
                icon: const Icon(Icons.route),
                heroTag: "connect",
              ),
            ),
            const SizedBox(height: 10),

            // Sync
            SizedBox(
              width: 120,
              height: 55,
              child: FloatingActionButton.extended(
                onPressed: () async {
                  if (!isConnected) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Start server or connect first!')),
                    );
                    return;
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Searching for CopyPasta peers...')),
                  );

                  final peers = await _mdns.discoverPeers();
                  final verifiedPeers = <String>[];
                  for (final ip in peers) {
                    final peer = PeerAPI(ip);
                    if (await peer.check()) verifiedPeers.add(ip);
                  }

                  if (verifiedPeers.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No CopyPasta peers found.')),
                    );
                    return;
                  }

                  await showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Select a CopyPasta Peer'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: verifiedPeers
                            .map((p) => ListTile(
                                  title: Text(p),
                                  onTap: () async {
                                    Navigator.pop(context);
                                    try {
                                      await _sync.syncWith(p);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Synced successfully with $p!')),
                                      );
                                      refreshData();
                                    } catch (e) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Sync failed: $e')),
                                      );
                                    }
                                  },
                                ))
                            .toList(),
                      ),
                    ),
                  );
                },
                label: const Text('Sync'),
                icon: const Icon(Icons.sync),
                heroTag: "sync",
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
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.primaryContainer,
        centerTitle: true,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'CopyPasta',
              style: TextStyle(
                color: theme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
                fontSize: 25,
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.circle,
              color: isConnected ? Colors.greenAccent.shade400 : Colors.grey.shade500,
              size: 14,
            ),
          ],
        ),
        bottom: localIp != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(18),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Connected: $localIp',
                    style: TextStyle(
                      color: theme.onPrimaryContainer.withOpacity(0.8),
                      fontSize: 14,
                    ),
                  ),
                ),
              )
            : null,
        actions: [
          IconButton(
            onPressed: refreshData,
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
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddNote()),
              );
            },
            heroTag: "addNote",
            label: const Text('Add Note', style: TextStyle(fontSize: 15)),
            icon: const Icon(Icons.note_add),
            elevation: 0,
          ),
          const SizedBox(width: 7),
          FloatingActionButton.extended(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddLink()),
              );
            },
            heroTag: "addLink",
            label: const Text('Add Link', style: TextStyle(fontSize: 15)),
            icon: const Icon(Icons.link),
            elevation: 0,
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endContained,
      bottomNavigationBar: const BottomAppBar(child: Row()),

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
                        builder: (context) => EditNote(
                          note: item,
                          noteIndex: index,
                        ),
                      ),
                    );
                  } else {
                    final uriParts = Uri.parse(item['title']);
                    final scheme = uriParts.scheme;
                    final host = uriParts.host;
                    final path = uriParts.path;
                    final urlL = Uri(
                      scheme: scheme.isNotEmpty ? scheme : 'https',
                      host: host,
                      path: path.isNotEmpty ? path : '/',
                    );
                    launchURL(urlL);
                  }
                },
                onLongPress: () {
                  showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        title: Text(item.containsKey('details')
                            ? 'Delete Note'
                            : 'Delete Link'),
                        content: Text(
                            'Are you sure you want to delete this ${item.containsKey('details') ? 'note' : 'link'}?'),
                        actions: <Widget>[
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () {
                              deleteItem(index);
                              Navigator.of(context).pop();
                            },
                            child: const Text('Delete'),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
