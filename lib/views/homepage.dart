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

class HomePage extends StatefulWidget {
  const HomePage({Key? key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey<OverlayState> overlayKey = GlobalKey<OverlayState>();
  List<Map<String, dynamic>> items = [];
  OverlayEntry? overlayEntry;
  bool isOverlayVisible = false;
  bool isRefreshed = false;

  // For sync connection simulation (for later WLAN feature)
  bool isConnected = false;

  @override
  void initState() {
    super.initState();
    items = [];
    constRefresh();
  }

  Future<void> getItems() async {
    final prefs = await SharedPreferences.getInstance();
    final notesData = prefs.getStringList('notes');
    final linksData = prefs.getStringList('links');

    setState(() {
      items.clear();
    });

    if (notesData != null) {
      setState(() {
        items.addAll(notesData
            .map((note) => json.decode(note))
            .cast<Map<String, dynamic>>()
            .toList());
      });
    }

    if (linksData != null) {
      setState(() {
        items.addAll(linksData
            .map((link) => json.decode(link))
            .cast<Map<String, dynamic>>()
            .toList());
      });
    }
    sortItems();
  }

  void sortItems() {
    items.sort((a, b) {
      DateTime timeA =
          DateFormat('hh:mm:ss a dd-MM-yyyy').parse(a['createdAt']);
      DateTime timeB =
          DateFormat('hh:mm:ss a dd-MM-yyyy').parse(b['createdAt']);
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
      setState(() {
        isRefreshed = true;
      });
      Future.delayed(const Duration(seconds: 1), () {
        setState(() {
          isRefreshed = false;
        });
      });
    }
  }

  void constRefresh() {
    Timer.periodic(const Duration(seconds: 0), (Timer timer) {
      refreshData();
    });
  }

  Future<void> launchURL(Uri url) async {
    if (!await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    )) {
      throw Exception('Could not launch $url');
    }
  }

  // ---------- Overlay Logic ----------
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
            // Connect button
            SizedBox(
              width: 120,
              height: 55,
              child: FloatingActionButton.extended(
                onPressed: () async {
                  // Placeholder: simulate connect toggle
                  setState(() => isConnected = !isConnected);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isConnected
                            ? 'Connected to device successfully'
                            : 'Disconnected',
                      ),
                    ),
                  );
                },
                label: Text(isConnected ? 'Disconnect' : 'Connect'),
                icon: const Icon(Icons.route),
                heroTag: "connect",
              ),
            ),
            const SizedBox(height: 10),
            // Sync button
            SizedBox(
              width: 120,
              height: 55,
              child: FloatingActionButton.extended(
                onPressed: () {
                  if (!isConnected) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please connect first!'),
                      ),
                    );
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Syncing data between devices...'),
                    ),
                  );
                  // Placeholder for WLAN sync logic later
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

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.primaryContainer,
        centerTitle: true,
        title: Text(
          'CopyPasta',
          style: TextStyle(
            color: theme.onPrimaryContainer,
            fontWeight: FontWeight.w600,
            fontSize: 25,
          ),
        ),
        actions: [
          IconButton(
            onPressed: refreshData,
            icon: const Icon(
              Icons.refresh_rounded,
              size: 30,
            ),
          ),
          const SizedBox(width: 15),
        ],
        actionsIconTheme: IconThemeData(color: theme.onPrimaryContainer),
      ),

      //Bottom FAB Row
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

      // Items list
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
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
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
