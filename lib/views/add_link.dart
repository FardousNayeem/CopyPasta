import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:copypasta/templates/title.dart';

class AddLink extends StatefulWidget {
  const AddLink({Key? key});

  @override
  State<AddLink> createState() => _AddLinkState();
}

class _AddLinkState extends State<AddLink> {
  final titleController = TextEditingController();

  Future<void> addLink(BuildContext context) async {
    final formattedDate = DateFormat('hh:mm:ss a dd-MM-yyyy').format(DateTime.now());
      
    final uuid = Uuid();
    final Map<String, dynamic> link = {
      'id': uuid.v4(),
      'title': titleController.text,
      'createdAt': formattedDate,
    };

    final prefs = await SharedPreferences.getInstance();
    final linksData = prefs.getStringList('links') ?? [];
    linksData.add(json.encode(link));
    await prefs.setStringList('links', linksData);

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.primaryContainer,
        centerTitle: true,
        title: Text(
          'Add Link',
          style: TextStyle(
            color: theme.onPrimaryContainer,
            fontWeight: FontWeight.w600,
            fontSize: 25,
          ),
        ),
        iconTheme: IconThemeData(color: theme.onPrimaryContainer),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              TitleField(controller: titleController, focus: true),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          addLink(context);
        },
        heroTag: "saveLinkA",
        label: const Text('Save Link', style: TextStyle(fontSize: 16)),
        icon: const Icon(Icons.save_rounded),
        elevation: 0,
      ),
    );
  }
}
