// SPDX-License-Identifier: GPL-3.0-only

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_amp_tools/src/pedal_updater.dart';
import 'package:pocket_amp_tools/src/presets/amp_upload.dart';
import 'package:pocket_amp_tools/src/presets/ir_upload.dart';
import 'package:pocket_amp_tools/src/presets/preset_service.dart';
import 'package:pocket_amp_tools/src/presets/write_guard.dart';

import 'support/fake_pedal.dart';

Uint8List nam({String name = 'PassaSinal', int length = namLength}) {
  final Uint8List b = Uint8List(length)
    ..setAll(0, namMagic)
    ..setAll(4, name.codeUnits);
  if (length == namWithBendLength) {
    b.setAll(7544, 'BEND'.codeUnits);
  }
  return b;
}

Uint8List am3({bool lmt = true}) {
  final Uint8List b = Uint8List(lmt ? am3WithLmtLength : am3Length)
    ..setAll(0, am3Magic)
    ..setAll(4, 'AGStomp'.codeUnits)
    ..setAll(18, <int>[0x64, 0x64]);
  if (lmt) {
    b.setAll(am3Length, 'LMT\u0000'.codeUnits);
  }
  return b;
}

void main() {
  test('the formats the pedal takes, and the reasons for the others', () {
    expect(parseAmpFile(nam()), hasLength(namLength));
    expect(parseAmpFile(nam(length: namWithBendLength)), hasLength(7836));
    expect(parseAmpFile(am3()), hasLength(am3WithLmtLength));
    expect(
      () => parseAmpFile(am3(lmt: false)),
      throwsA(
        isA<InvalidIrFile>().having(
          (InvalidIrFile e) => e.message,
          'm',
          contains('LMT'),
        ),
      ),
    );
    final Uint8List nan = nam();
    ByteData.sublistView(nan).setFloat32(100, double.nan, Endian.little);
    expect(() => parseAmpFile(nan), throwsA(isA<InvalidIrFile>()));
    expect(
      () => parseAmpFile(
        utf8.encode('{"version": "0.5.4", "architecture": "WaveNet"}'),
      ),
      throwsA(
        isA<InvalidIrFile>().having(
          (InvalidIrFile e) => e.message,
          'm',
          contains('Convert'),
        ),
      ),
    );
    expect(
      () => parseAmpFile(nam(length: 7000)),
      throwsA(isA<InvalidIrFile>()),
    );
  });

  test('a NAM upload is the image, apply, the named image, store', () {
    final List<(Uint8List, String)> p = ampUploadPackets(19, 'Clean', nam());
    // 7548 B = 7 chunks of 1015 + 443, sent twice, plus apply and store.
    expect(p, hasLength(8 + 1 + 8 + 1));
    for (final (Uint8List packet, String what) in p) {
      expect(() => checkOutgoing(packet), returnsNormally, reason: what);
    }
    expect(p[8].$1, ampApplyPacket());
    expect(p.last.$1, ampSaveToSlotPacket(19));
    expect(p.last.$1[7], 19);
    expect(p.last.$1[8], 0x00, reason: 'AMP, not CAB');
    // The second pass carries the new name.
    expect(String.fromCharCodes(p[9].$1.sublist(18, 23)), 'Clean');
    expect(p[9].$1[23], 0);
  });

  test('an AM3 with LMT goes in 7 chunks each way', () {
    final List<(Uint8List, String)> p = ampUploadPackets(0, 'X', am3());
    expect(p, hasLength(7 + 1 + 7 + 1));
    for (final (Uint8List packet, String what) in p) {
      expect(() => checkOutgoing(packet), returnsNormally, reason: what);
    }
  });

  test('the guard refuses AMP chunks off the grid or a stray store', () {
    final Uint8List img = nam();
    expect(
      () => checkOutgoing(irBufferPacket(1015, img.sublist(1015, 2000))),
      throwsA(isA<BlockedPacket>()),
    );
    expect(
      () => checkOutgoing(irBufferPacket(0, Uint8List(irChunkLength))),
      throwsA(isA<BlockedPacket>()),
    );
    final Uint8List bad = ampSaveToSlotPacket(3)..[8] = 0x02;
    expect(() => checkOutgoing(bad), throwsA(isA<BlockedPacket>()));
  });

  test('uploading puts the capture and its name in the AMP slot', () async {
    final FakePedal pedal = FakePedal(image: Uint8List(1024), bank: demoBank());
    final List<String> names = await PresetService(pedal).uploadAmp(
      DetectedPedal(pedal.port, 'Pocket AMP_105'),
      19,
      'Clean',
      nam(),
    );
    expect(names[19], 'Clean');
    expect(pedal.ampSlots[19]!.sublist(0, 4), namMagic);
    expect(pedal.ampSlots[19]!.sublist(60, namLength), nam().sublist(60));
    expect(pedal.cabNames.contains('Clean'), isFalse);
  });
}
