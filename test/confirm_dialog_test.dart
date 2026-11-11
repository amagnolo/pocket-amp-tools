import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_amp_tools/src/ui/home_page.dart';

Future<void> _show(WidgetTester t, ConfirmUpdateDialog d) async {
  t.view.physicalSize = const Size(900, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: Scaffold(body: d)));
}

bool _canUpdate(WidgetTester t) =>
    t
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Update'))
        .onPressed !=
    null;

void main() {
  testWidgets('a clone needs its own consent on top of the risk', (t) async {
    await _show(
      t,
      const ConfirmUpdateDialog(
        from: 'PIXIE1_007',
        to: 'Pocket AMP_105',
        rebrand: 'PIXIE1',
        family: 'Pocket AMP',
        official: true,
      ),
    );
    expect(_canUpdate(t), isFalse);
    await t.tap(find.textContaining('I backed up my presets'));
    await t.pump();
    expect(_canUpdate(t), isFalse, reason: 'clone consent still missing');
    await t.tap(find.textContaining('Turn my PIXIE1'));
    await t.pump();
    expect(_canUpdate(t), isTrue);
  });

  testWidgets('an unknown package needs its own consent', (t) async {
    await _show(
      t,
      const ConfirmUpdateDialog(
        from: 'Pocket AMP_103',
        to: 'Pocket AMP_106',
        rebrand: null,
        family: 'Pocket AMP',
        official: false,
      ),
    );
    await t.tap(find.textContaining('I backed up my presets'));
    await t.pump();
    expect(_canUpdate(t), isFalse);
    await t.tap(find.textContaining('I trust where this file came from'));
    await t.pump();
    expect(_canUpdate(t), isTrue);
  });

  testWidgets('the Donner consent states what was tested', (t) async {
    await _show(
      t,
      const ConfirmUpdateDialog(
        from: 'DONNER Pocket AMP_008',
        to: 'Pocket AMP_105',
        rebrand: 'DONNER Pocket AMP',
        family: 'Pocket AMP',
        official: true,
      ),
    );
    expect(
      find.textContaining('updated a Donner unit from 0.08'),
      findsOneWidget,
    );
    expect(find.textContaining('There is no'), findsNothing);
  });
}
