// Renders the README and website screenshots from the real UI, with a fake
// pedal on V1.03 and the official V1.05 package:
//
//   POCKET_AMP_FWSC=/path/Pocket\ AMP.fwsc \
//     flutter test test_screens --update-goldens
//
// The PNGs land in test_screens/goldens/.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocket_amp_upgrader/main.dart';

import '../test/support/fake_pedal.dart';

Future<void> _loadFont(String family, List<String> files) async {
  final FontLoader loader = FontLoader(family);
  for (final String f in files) {
    final Uint8List b = File(f).readAsBytesSync();
    loader.addFont(Future<ByteData>.value(ByteData.sublistView(b)));
  }
  await loader.load();
}

void main() {
  final String? fwsc = Platform.environment['POCKET_AMP_FWSC'];
  final String fonts =
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';

  setUpAll(() async {
    await _loadFont('Roboto', <String>[
      '$fonts/Roboto-Regular.ttf',
      '$fonts/Roboto-Medium.ttf',
      '$fonts/Roboto-Bold.ttf',
    ]);
    await _loadFont('MaterialIcons', <String>[
      '$fonts/MaterialIcons-Regular.otf',
    ]);
  });

  for (final Brightness b in Brightness.values) {
    testWidgets('ready to update, ${b.name}', (WidgetTester tester) async {
      // Real shadows instead of the test framework's flat outlines.
      debugDisableShadows = false;
      tester.view.physicalSize = const Size(1440, 2200);
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.platformBrightnessTestValue = b;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      final Uint8List pkg = File(fwsc!).readAsBytesSync();
      await http.runWithClient(() async {
        await tester.pumpWidget(
          UpgraderApp(backend: FakePedal(image: Uint8List(1024))),
        );
        // Detection and the download run on real time, as in home_page_test.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 2)),
        );
        await tester.pump();
        await tester.tap(find.text('Download from M-VAVE'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 1)),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => MockClient((_) async => http.Response.bytes(pkg, 200)));

      await expectLater(
        find.byType(UpgraderApp),
        matchesGoldenFile('goldens/ready-${b.name}.png'),
      );
      debugDisableShadows = true; // checked before tear-down runs
    }, skip: fwsc == null);
  }
}
