import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_amp_tools/src/presets/preset_backup.dart';
import 'package:pocket_amp_tools/src/ui/backups_page.dart';

void main() {
  testWidgets('backing up now reloads the list without a setState error', (
    t,
  ) async {
    int listed = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BackupsPage(
            list: () async {
              listed++;
              return <(File, PresetBackup?, String?)>[];
            },
            canRestore: true,
            onEdit: (_, _) {},
            onRestore: (_, _) {},
            onRestoreRaw: (_) {},
            onSaveNew: () async {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(listed, 1);

    await t.tap(find.text('Back up the pedal now'));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    expect(listed, 2);
  });
}
