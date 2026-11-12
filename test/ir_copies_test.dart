// SPDX-License-Identifier: GPL-3.0-only

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_amp_tools/src/presets/ir_copies.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('irs-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('one copy per slot, the newest one, with its name', () async {
    final IrCopies c = IrCopies(dir);
    expect(await c.list(), isEmpty);
    await c.keep(1, 'Tay816_Pz3_20', Uint8List.fromList(<int>[1]));
    await c.keep(3, 'HolyGrail/Pz1', Uint8List.fromList(<int>[2]));
    final File last = await c.keep(1, 'D35', Uint8List.fromList(<int>[3]));

    final Map<int, (String, File)> all = await c.list();
    expect(all.keys, unorderedEquals(<int>[1, 3]));
    expect(all[1]!.$1, 'D35');
    expect(all[1]!.$2.readAsBytesSync(), <int>[3]);
    expect(last.path, all[1]!.$2.path);
    // A character that cannot go in a file name is replaced.
    expect(all[3]!.$1, 'HolyGrail_Pz1');
    expect(dir.listSync(), hasLength(2));
  });

  test('other files in the folder are left out', () async {
    File('${dir.path}/notes.txt').writeAsStringSync('x');
    File('${dir.path}/cab-21--x.wav').writeAsStringSync('x');
    expect(await IrCopies(dir).list(), isEmpty);
  });

  test('amp copies live apart from IR copies, as .bin', () async {
    final IrCopies amps = IrCopies(dir, amp: true);
    await amps.keep(19, 'Clean', Uint8List.fromList(<int>[9]));
    await IrCopies(dir).keep(19, 'Cab', Uint8List.fromList(<int>[8]));
    expect((await amps.list())[19]!.$1, 'Clean');
    expect((await amps.list())[19]!.$2.path, endsWith('amp-20--Clean.bin'));
    expect((await IrCopies(dir).list())[19]!.$1, 'Cab');
  });
}
