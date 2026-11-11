import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_amp_tools/src/pedal_updater.dart';
import 'package:pocket_amp_tools/src/presets/ir_upload.dart';
import 'package:pocket_amp_tools/src/presets/preset_service.dart';
import 'package:pocket_amp_tools/src/presets/write_guard.dart';

import 'support/fake_pedal.dart';

String hex(List<int> b) => b
    .map((int x) => x.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(' ');

/// A WAV header (44 bytes) for [frames] frames of [bits]-bit audio.
Uint8List wav({
  int channels = 1,
  int rate = 44100,
  int bits = 24,
  int frames = irSampleCount,
}) {
  final int dataLength = frames * channels * bits ~/ 8;
  final ByteData h = ByteData(44 + dataLength);
  void tag(int at, String t) {
    for (int i = 0; i < 4; i++) {
      h.setUint8(at + i, t.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  h.setUint32(4, 36 + dataLength, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  h.setUint32(16, 16, Endian.little);
  h.setUint16(20, 1, Endian.little);
  h.setUint16(22, channels, Endian.little);
  h.setUint32(24, rate, Endian.little);
  h.setUint32(28, rate * channels * bits ~/ 8, Endian.little);
  h.setUint16(32, channels * bits ~/ 8, Endian.little);
  h.setUint16(34, bits, Endian.little);
  tag(36, 'data');
  h.setUint32(40, dataLength, Endian.little);
  final Uint8List b = h.buffer.asUint8List();
  for (int i = 44; i < b.length; i++) {
    b[i] = i * 7;
  }
  return b;
}

void main() {
  test('IR packets match the bytes traced from the official app', () {
    expect(
      hex(irApplyPacket()),
      '00 59 22 09 00 00 05 00 00 00 A0 01 00 00 02 57',
    );
    expect(
      hex(irSaveToSlotPacket(1)),
      '00 59 22 09 00 00 05 01 01 00 F0 01 00 00 00 07',
    );
    expect(irChunkGrid.values, <int>[1015, 1015, 1015, 1015, 1015, 1015, 74]);
  });

  test('an upload is ten packets, all allowed, the flash write last', () {
    final List<(Uint8List, String)> packets = irUploadPackets(
      3,
      'My Cab',
      Uint8List(irPcmLength),
    );
    expect(packets, hasLength(10));
    for (final (Uint8List p, _) in packets) {
      expect(() => checkOutgoing(p), returnsNormally);
    }
    expect(packets.last.$2, 'storing the IR in slot 4');
  });

  test('the guard refuses an IR chunk off the grid or without a header', () {
    final Uint8List image = Uint8List.fromList(<int>[
      ...irHeader(),
      ...Uint8List(irPcmLength),
    ]);
    expect(
      () => checkOutgoing(irBufferPacket(1, image.sublist(1, 1016))),
      throwsA(isA<BlockedPacket>()),
    );
    expect(
      () => checkOutgoing(irBufferPacket(0, Uint8List(irChunkLength))),
      throwsA(isA<BlockedPacket>()),
    );
    expect(() => checkOutgoing(irSaveToSlotPacket(19)), returnsNormally);
  });

  test('only the measured WAV format is taken, with the reason', () {
    expect(parseIrWav(wav()), hasLength(irPcmLength));
    expect(
      () => parseIrWav(wav(channels: 2)),
      throwsA(
        isA<InvalidIrFile>().having(
          (InvalidIrFile e) => e.message,
          'm',
          contains('2 channels'),
        ),
      ),
    );
    expect(
      () => parseIrWav(wav(rate: 48000)),
      throwsA(
        isA<InvalidIrFile>().having(
          (InvalidIrFile e) => e.message,
          'm',
          contains('48000 Hz'),
        ),
      ),
    );
    expect(
      () => parseIrWav(wav(bits: 16)),
      throwsA(
        isA<InvalidIrFile>().having(
          (InvalidIrFile e) => e.message,
          'm',
          contains('16-bit'),
        ),
      ),
    );
    expect(
      () => parseIrWav(wav(frames: 1024)),
      throwsA(
        isA<InvalidIrFile>().having(
          (InvalidIrFile e) => e.message,
          'm',
          contains('1024 samples'),
        ),
      ),
    );
    expect(() => parseIrWav(Uint8List(10)), throwsA(isA<InvalidIrFile>()));
  });

  test('an extensible WAV needs the whole PCM subformat', () {
    Uint8List extensible(List<int> subformat) {
      final Uint8List plain = wav();
      final ByteData fmt = ByteData(48)
        ..setUint32(0, 0x20746D66, Endian.little) // "fmt "
        ..setUint32(4, 40, Endian.little)
        ..setUint16(8, 0xFFFE, Endian.little)
        ..setUint16(10, 1, Endian.little)
        ..setUint32(12, 44100, Endian.little)
        ..setUint16(22, 24, Endian.little);
      final Uint8List f = fmt.buffer.asUint8List()..setAll(32, subformat);
      return Uint8List.fromList(<int>[
        ...plain.sublist(0, 12),
        ...f,
        ...plain.sublist(36),
      ]);
    }

    const List<int> pcm = <int>[
      1, 0, 0, 0, 0, 0, 0x10, 0, 0x80, 0, 0, 0xAA, 0, 0x38, 0x9B, 0x71, //
    ];
    expect(parseIrWav(extensible(pcm)), hasLength(irPcmLength));
    final List<int> other = List<int>.of(pcm)..[15] = 0x72;
    expect(() => parseIrWav(extensible(other)), throwsA(isA<InvalidIrFile>()));
  });

  test('uploading puts the image and the name in the slot', () async {
    final FakePedal pedal = FakePedal(image: Uint8List(1024), bank: demoBank());
    final Uint8List bank = Uint8List.fromList(pedal.bank!);
    final Uint8List pcm = parseIrWav(wav());
    final List<String> names = await PresetService(pedal).uploadIr(
      DetectedPedal(pedal.port, 'Pocket AMP_105'),
      4,
      'Tay816_Pz3_2048',
      pcm,
    );
    expect(names[4], 'Tay816_Pz3_20');
    expect(pedal.irSlots[4]!.sublist(irHeaderLength), pcm);
    expect(pedal.bank, bank, reason: 'presets untouched');
  });
}
