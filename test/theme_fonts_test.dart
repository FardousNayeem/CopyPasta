import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:copypasta/templates/theme.dart';

/// Guards the thing that broke silently before: the app used to fetch its
/// fonts over the network at run time and fall back to the system face when
/// that failed. Nothing on screen said so.
void main() {
  testWidgets('text uses the bundled families, not a downloaded one',
      (tester) async {
    late TextStyle body;
    late TextStyle mono;
    late TextStyle appBarTitle;

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Builder(builder: (context) {
        final theme = Theme.of(context);
        body = theme.textTheme.bodyMedium!;
        appBarTitle = theme.appBarTheme.titleTextStyle!;
        mono = AppTheme.mono(context, weight: 600);
        return const SizedBox();
      }),
    ));

    // ThemeData.fontFamily is what every unstyled Text inherits.
    expect(Theme.of(tester.element(find.byType(SizedBox))).textTheme, isNotNull);
    expect(body.fontFamily ?? AppTheme.sansFamily, AppTheme.sansFamily);
    expect(appBarTitle.fontFamily, AppTheme.sansFamily);
    expect(mono.fontFamily, AppTheme.monoFamily);
  });

  testWidgets('mono weight rides the variable axis, not a synthetic bold',
      (tester) async {
    late TextStyle regular;
    late TextStyle bold;

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        regular = AppTheme.mono(context);
        bold = AppTheme.mono(context, weight: 700);
        return const SizedBox();
      }),
    ));

    // Only one face of JetBrainsMono is registered. Asking for a bold
    // fontWeight would make the engine smear the regular one; a FontVariation
    // drives the font's own wght axis instead.
    expect(regular.fontWeight, isNull);
    expect(bold.fontWeight, isNull);
    expect(regular.fontVariations, [const FontVariation('wght', 400)]);
    expect(bold.fontVariations, [const FontVariation('wght', 700)]);
  });
}
