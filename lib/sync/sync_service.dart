import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:copypasta/network/peer_api.dart';

class SyncService {
  Future<Map<String, dynamic>> _localData() async {
    final prefs = await SharedPreferences.getInstance();
    final notes = prefs.getStringList('notes') ?? [];
    final links = prefs.getStringList('links') ?? [];
    return {'notes': notes, 'links': links};
  }

  Future<void> _saveData(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('notes', List<String>.from(data['notes']));
    await prefs.setStringList('links', List<String>.from(data['links']));
  }

  /// Merges both device data, removing duplicates and marking synced entries
  Future<void> mergeAndSave(
      Map<String, dynamic> local, Map<String, dynamic> remote) async {
    final localNotes = (local['notes'] as List).cast<String>();
    final remoteNotes = (remote['notes'] as List).cast<String>();
    final localLinks = (local['links'] as List).cast<String>();
    final remoteLinks = (remote['links'] as List).cast<String>();

    List<String> allNotes = {...localNotes, ...remoteNotes}.toList();
    List<String> allLinks = {...localLinks, ...remoteLinks}.toList();


    allNotes = allNotes.map((e) {
      final note = jsonDecode(e);
      if (!localNotes.contains(e)) {
        note['title'] = '${note['title']} (S)';
      }
      return jsonEncode(note);
    }).toList();

    allLinks = allLinks.map((e) {
      final link = jsonDecode(e);
      if (!localLinks.contains(e)) {
        link['title'] = '${link['title']} (S)';
      }
      return jsonEncode(link);
    }).toList();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('notes', allNotes);
    await prefs.setStringList('links', allLinks);
  }

  Future<void> syncWith(String ip) async {
    final peer = PeerAPI(ip);
    final ok = await peer.check();
    if (!ok) throw Exception('Peer not reachable');

    final localData = await _localData();
    final remoteData = await peer.getData();
    if (remoteData == null) throw Exception('No data from peer');

    // Merge and save both sides
    await mergeAndSave(localData, remoteData);
    await peer.sendData(await _localData());
  }
}
