import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:copypasta/templates/title.dart';
import 'package:copypasta/templates/details.dart';

class AddNote extends StatefulWidget {
  const AddNote({Key? key});

  @override
  State<AddNote> createState() => _AddNoteState();
}

class _AddNoteState extends State<AddNote> {
  final titleController = TextEditingController();
  final detailsController = TextEditingController();

  Future<void> addNote(BuildContext context) async {
    final formattedDate = DateFormat('hh:mm:ss a dd-MM-yyyy').format(DateTime.now());
      
    final uuid = Uuid();
    final Map<String, dynamic> note = {
      'id': uuid.v4(),
      'title': titleController.text,
      'details': detailsController.text,
      'createdAt': formattedDate,
    };


    final prefs = await SharedPreferences.getInstance();
    final notesData = prefs.getStringList('notes') ?? [];
    notesData.add(json.encode(note));
    await prefs.setStringList('notes', notesData);

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
          'Add Note',
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
              DetailsField(controller: detailsController),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          addNote(context);
        },
        heroTag: "saveNoteA",
        label: const Text('Save Note', style: TextStyle(fontSize: 16)),
        icon: const Icon(Icons.save_rounded),
        elevation: 0,
      ),
    );
  }
}
