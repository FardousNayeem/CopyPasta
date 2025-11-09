import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class NoteView extends StatefulWidget {
  final Map<String, dynamic> note;
  final int noteIndex;

  const NoteView({required this.note, required this.noteIndex, Key? key})
      : super(key: key);

  @override
  State<NoteView> createState() => _NoteViewState();
}

class _NoteViewState extends State<NoteView> {
  late TextEditingController titleController;
  late TextEditingController detailsController;
  bool isEditing = false;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.note['title']);
    detailsController = TextEditingController(text: widget.note['details']);
  }

  /// 🧠 Save the edited note safely using its UUID
  Future<void> saveNote() async {
    final prefs = await SharedPreferences.getInstance();
    final notesData = prefs.getStringList('notes') ?? [];

    final updatedNote = {
      'id': widget.note['id'], // Keep same UUID
      'title': titleController.text,
      'details': detailsController.text,
      'createdAt': widget.note['createdAt'],
    };

    final index = notesData.indexWhere((note) {
      final decoded = jsonDecode(note);
      return decoded['id'] == widget.note['id'];
    });

    if (index != -1) {
      notesData[index] = jsonEncode(updatedNote);
      await prefs.setStringList('notes', notesData);
    }

    setState(() {
      isEditing = false;
    });
  }

  /// 🗑 Delete the note using its UUID
  Future<void> deleteNote() async {
    final prefs = await SharedPreferences.getInstance();
    final notesData = prefs.getStringList('notes') ?? [];

    final index = notesData.indexWhere((note) {
      final decoded = jsonDecode(note);
      return decoded['id'] == widget.note['id'];
    });

    if (index != -1) {
      notesData.removeAt(index);
      await prefs.setStringList('notes', notesData);
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.primaryContainer,
        title: Text(
          'Note Details',
          style: TextStyle(
            color: theme.onPrimaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              isEditing ? Icons.save : Icons.edit,
              color: theme.onPrimaryContainer,
            ),
            onPressed: () {
              if (isEditing) {
                saveNote();
              } else {
                setState(() {
                  isEditing = true;
                });
              }
            },
          ),
          IconButton(
            icon: Icon(Icons.delete, color: theme.onPrimaryContainer),
            onPressed: deleteNote,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Title Box
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                labelText: 'Title',
                labelStyle: TextStyle(
                  color: theme.onSurface.withOpacity(0.8),
                  fontSize: 20,
                ),
                filled: true,
                fillColor: theme.surfaceVariant,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: theme.outline.withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: theme.primary, width: 2),
                ),
              ),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: theme.onSurface,
              ),
              enabled: isEditing,
            ),

            const SizedBox(height: 16),

            // Description Box (leaves bottom margin)
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(bottom: 24),
                child: TextField(
                  controller: detailsController,
                  decoration: InputDecoration(
                    labelText: 'Description',
                    labelStyle: TextStyle(
                      color: theme.onSurface.withOpacity(0.8),
                      fontSize: 18,
                    ),
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: theme.surfaceVariant,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: theme.outline.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: theme.primary, width: 2),
                    ),
                  ),
                  style: TextStyle(
                    fontSize: 18,
                    color: theme.onSurface,
                  ),
                  enabled: isEditing,
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
