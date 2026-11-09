import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_amp_upgrader/src/ui/home_page.dart';

import 'support/fake_pedal.dart';

void main() {
  testWidgets(
    'detects the pedal on start and keeps update disabled without a package',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final FakePedal pedal = FakePedal(image: Uint8List(1024));
      await tester.pumpWidget(MaterialApp(home: HomePage(backend: pedal)));

      final Finder update = find.ancestor(
        of: find.text('Update firmware'),
        matching: find.byWidgetPredicate((Widget w) => w is ButtonStyleButton),
      );
      expect(tester.widget<ButtonStyleButton>(update).onPressed, isNull);

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      await tester.pump();

      expect(find.text('1.03'), findsOneWidget);
      expect(find.text('Detect again'), findsOneWidget);
      expect(tester.widget<ButtonStyleButton>(update).onPressed, isNull);
    },
  );

  group('update without a preset backup', () {
    testWidgets('continues only on "Update without a backup"', (
      WidgetTester tester,
    ) async {
      expect(
        await _askWithoutBackup(tester, 'Update without a backup'),
        isTrue,
      );
    });

    testWidgets('Cancel stops the update', (WidgetTester tester) async {
      expect(await _askWithoutBackup(tester, 'Cancel'), isFalse);
    });

    testWidgets('tapping outside does not close it', (
      WidgetTester tester,
    ) async {
      expect(await _askWithoutBackup(tester, ''), isNull);
      expect(find.text('Presets cannot be backed up'), findsOneWidget);
    });
  });
}

Future<bool?> _askWithoutBackup(WidgetTester tester, String button) async {
  bool? answer;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () async =>
              answer = await confirmUpdateWithoutBackup(context, '/raw.bin'),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.text('Presets cannot be backed up'), findsOneWidget);
  expect(find.textContaining('/raw.bin'), findsOneWidget);
  if (button.isEmpty) {
    await tester.tapAt(const Offset(5, 5)); // the barrier
  } else {
    await tester.tap(find.text(button));
  }
  await tester.pumpAndSettle();
  return answer;
}
