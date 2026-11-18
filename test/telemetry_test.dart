// SPDX-License-Identifier: GPL-3.0-only

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_amp_tools/src/telemetry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('scrub', () {
    test('null and text without the home folder pass through', () {
      expect(Telemetry.scrub(null, home: <String>['/home/ana']), isNull);
      expect(
        Telemetry.scrub('no paths here', home: <String>['/home/ana']),
        'no paths here',
      );
    });

    test('replaces the home folder wherever it appears', () {
      expect(
        Telemetry.scrub(
          'open /home/ana/x.bin failed; /home/ana/y.bin too',
          home: <String>['/home/ana'],
        ),
        'open ~/x.bin failed; ~/y.bin too',
      );
    });

    test('a trailing slash on HOME does not leave the name behind', () {
      expect(
        Telemetry.scrub('/home/ana/x', home: <String>['/home/ana/']),
        '~/x',
      );
    });

    test('a root as HOME is ignored instead of turning slashes into ~', () {
      for (final String root in <String>['/', r'C:\', 'C:', '', ' ']) {
        expect(
          Telemetry.scrub('/var/log/x C:\\y', home: <String>[root]),
          '/var/log/x C:\\y',
          reason: 'home "$root"',
        );
      }
    });

    test('HOME and USERPROFILE are both removed, the longer first', () {
      expect(
        Telemetry.scrub(
          '/home/ana/work/x and /home/ana/y',
          home: <String>['/home/ana', '/home/ana/work'],
        ),
        '~/x and ~/y',
      );
    });

    test('on Windows either slash and any letter case match', () {
      const List<String> home = <String>[r'C:\Users\Ana'];
      for (final String path in <String>[
        r'C:\Users\Ana\x.bin',
        'C:/Users/Ana/x.bin',
        r'c:\users\ana\x.bin',
      ]) {
        expect(
          Telemetry.scrub('read $path', home: home, windows: true),
          startsWith('read ~'),
          reason: path,
        );
        expect(
          Telemetry.scrub('read $path', home: home, windows: true),
          isNot(contains('Ana')),
          reason: path,
        );
      }
    });

    test('off Windows the match is exact, so another user is kept', () {
      expect(
        Telemetry.scrub('/home/Ana/x', home: <String>['/home/ana']),
        '/home/Ana/x',
      );
    });

    test('characters that mean something in a pattern are taken as text', () {
      expect(
        Telemetry.scrub(
          '/home/a.b+c/x /home/aXb+c/x',
          home: <String>['/home/a.b+c'],
        ),
        '~/x /home/aXb+c/x',
      );
    });
  });

  group('choice', () {
    late Directory dir;
    late File file;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('telemetry');
      file = File('${dir.path}${Platform.pathSeparator}telemetry');
      const MethodChannel channel = MethodChannel(
        'plugins.flutter.io/path_provider',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (MethodCall call) async => dir.path,
          );
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      await dir.delete(recursive: true);
    });

    test('is null until the user answers', () async {
      expect(await Telemetry.choice(), isNull);
    });

    test('reads on and off, and anything else as not answered', () async {
      await file.writeAsString('on\n');
      expect(await Telemetry.choice(), isTrue);
      await file.writeAsString('off');
      expect(await Telemetry.choice(), isFalse);
      await file.writeAsString('maybe');
      expect(await Telemetry.choice(), isNull);
    });

    test('choosing off is kept and nothing is reported', () async {
      await Telemetry.choose(false);
      expect(file.readAsStringSync(), 'off');
      expect(await Telemetry.choice(), isFalse);
      expect(Telemetry.on, isFalse);
    });

    test(
      'builds without a DSN never start, even if the user said on',
      () async {
        await file.writeAsString('on');
        await Telemetry.startIfAllowed();
        expect(Telemetry.available, isFalse);
        expect(Telemetry.on, isFalse);
      },
    );
  });
}
