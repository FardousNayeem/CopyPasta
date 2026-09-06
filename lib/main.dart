import 'dart:async';

import 'package:flutter/foundation.dart' show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:copypasta/services/attachment_store.dart';
import 'package:copypasta/services/background_service.dart';
import 'package:copypasta/services/item_store.dart';
import 'package:copypasta/services/lan_service.dart';
import 'package:copypasta/templates/theme.dart';
import 'package:copypasta/views/homepage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  _registerFontLicences();

  // Attachments first: the item store garbage-collects orphaned files as part
  // of loading, and can only do that once it knows where they live.
  await AttachmentStore.instance.init();
  await ItemStore.instance.load();
  await LanService.instance.init();
  await BackgroundService.instance.init();

  // Started here rather than from a page, so the device stays reachable for as
  // long as the app is running instead of only while one screen is open.
  // Deliberately not awaited: a firewall prompt or a busy port must not hold
  // up the first frame. Failures surface on the Connect screen.
  unawaited(LanService.instance.start());

  runApp(const CopyPastaApp());
}

/// Mukta and JetBrains Mono ship inside the app under the SIL Open Font
/// License, which asks that the licence travel with the font. Registering them
/// here puts both texts in `showLicensePage`, where a person can actually find
/// them, rather than in a file nothing ever opens.
void _registerFontLicences() {
  LicenseRegistry.addLicense(() async* {
    for (final entry in const {
      'Mukta': 'assets/fonts/OFL-Mukta.txt',
      'JetBrainsMono': 'assets/fonts/OFL-JetBrainsMono.txt',
    }.entries) {
      final text = await rootBundle.loadString(entry.value);
      yield LicenseEntryWithLineBreaks([entry.key], text);
    }
  });
}

class CopyPastaApp extends StatelessWidget {
  const CopyPastaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CopyPasta',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}
