// SPDX-License-Identifier: GPL-3.0-only
//
// Uploading a user IR to one of the 20 CAB slots. Ported from the
// pocket-amp-editor project, where the official M-EFCS app was traced
// sending eight IRs on firmware V1.05 (probe-pocket-amp/PROTOCOLO_IR.md):
//
// 1. the image (20-byte header + PCM) goes to the pedal's IR buffer in
//    chunks of 1015 bytes, and the buffer is applied to the sound;
// 2. the header is written again, now with the name;
// 3. the buffer is copied to the slot. This step writes to flash.
//
// The PCM is sent as it is in the file: 2048 frames, 24-bit, mono.

import 'dart:typed_data';

import 'mefcs.dart';

const int irSampleCount = 2048;
const int irPcmLength = irSampleCount * 3;
const int irHeaderLength = 20;
const int irImageLength = irHeaderLength + irPcmLength;
const int irChunkLength = 1015;
const int irNameMaxLength = 13;
const int irSlotCount = 20;

/// Header byte 19 as the official app sends it when its Level slider is not
/// touched; the scale of this byte is not measured.
const int irDefaultLevel = 0x32;
const List<int> irHeaderMagic = <int>[0x43, 0x41, 0x42, 0x00]; // "CAB\0"

/// The only chunk offsets and sizes the pedal was seen to take: six of 1015
/// bytes and a last one of 74.
final Map<int, int> irChunkGrid = <int, int>{
  for (int at = 0; at < irImageLength; at += irChunkLength)
    at: irImageLength - at < irChunkLength ? irImageLength - at : irChunkLength,
};

class InvalidIrFile implements Exception {
  const InvalidIrFile(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Printable ASCII, trimmed, at most 13 characters.
String sanitizeIrName(String name) {
  final String ascii = String.fromCharCodes(
    name.trim().codeUnits.map((int c) => c >= 0x20 && c < 0x7F ? c : 0x5F),
  );
  return ascii.length > irNameMaxLength
      ? ascii.substring(0, irNameMaxLength)
      : ascii;
}

Uint8List irHeader({String name = ''}) {
  final List<int> n = sanitizeIrName(name).codeUnits;
  return Uint8List.fromList(<int>[
    ...irHeaderMagic,
    ...n,
    for (int i = n.length; i < irNameMaxLength + 1; i++) 0,
    0x01,
    irDefaultLevel,
  ]);
}

/// The PCM frames of a WAV in the one format whose upload was measured:
/// 44.1 kHz, mono, 24-bit, 2048 samples. Nothing is converted.
Uint8List parseIrWav(List<int> bytes) {
  int u16(int o) => bytes[o] | (bytes[o + 1] << 8);
  int u32(int o) => u16(o) | (u16(o + 2) << 16);
  if (bytes.length < 12 ||
      String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
    throw const InvalidIrFile('Not a WAV file.');
  }
  int? format, channels, rate, bits;
  List<int>? data;
  for (int pos = 12; pos + 8 <= bytes.length;) {
    final String id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
    final int size = u32(pos + 4);
    final int start = pos + 8;
    if (start + size > bytes.length) {
      throw InvalidIrFile('The "$id" chunk runs past the end of the file.');
    }
    if (id == 'fmt ' && size >= 16) {
      format = u16(start);
      channels = u16(start + 2);
      rate = u32(start + 4);
      bits = u16(start + 14);
      if (format == 0xFFFE) {
        // WAVE_FORMAT_EXTENSIBLE: PCM only with the whole PCM subformat GUID.
        format =
            size >= 40 &&
                _same(bytes.sublist(start + 24, start + 40), _pcmSubformat)
            ? 1
            : 0xFFFE;
      }
    } else if (id == 'data') {
      data = bytes.sublist(start, start + size);
    }
    pos = start + size + (size.isOdd ? 1 : 0);
  }
  if (format == null || data == null) {
    throw const InvalidIrFile('The WAV has no format or no audio.');
  }
  final String? wrong = format != 1
      ? 'it is not integer PCM'
      : channels != 1
      ? 'it has $channels channels, not 1'
      : rate != 44100
      ? 'it is $rate Hz, not 44100'
      : bits != 24
      ? 'it is $bits-bit, not 24'
      : data.length != irPcmLength
      ? 'it has ${data.length ~/ 3} samples, not $irSampleCount'
      : null;
  if (wrong != null) {
    throw InvalidIrFile(
      'The pedal takes 44.1 kHz, mono, 24-bit IRs of $irSampleCount '
      'samples; $wrong. Convert it first (with sox, for example).',
    );
  }
  return Uint8List.fromList(data);
}

/// KSDATAFORMAT_SUBTYPE_PCM, 00000001-0000-0010-8000-00AA00389B71.
const List<int> _pcmSubformat = <int>[
  0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x00, //
  0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71,
];

bool _same(List<int> a, List<int> b) {
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// The packets that put [pcm] in CAB slot [slot] (0..19) named [name], in
/// order, with what each one does.
List<(Uint8List, String)> irUploadPackets(
  int slot,
  String name,
  Uint8List pcm,
) {
  if (slot < 0 || slot >= irSlotCount || pcm.length != irPcmLength) {
    throw ArgumentError('invalid IR upload');
  }
  final Uint8List image = Uint8List.fromList(<int>[...irHeader(), ...pcm]);
  return <(Uint8List, String)>[
    for (final MapEntry<int, int> e in irChunkGrid.entries)
      (
        irBufferPacket(e.key, image.sublist(e.key, e.key + e.value)),
        'sending the IR',
      ),
    (irApplyPacket(), 'applying the IR'),
    (irBufferPacket(0, irHeader(name: name)), 'naming the IR'),
    (irSaveToSlotPacket(slot), 'storing the IR in slot ${slot + 1}'),
  ];
}

/// Writes [bytes] at [offset] of the IR buffer (RAM).
Uint8List irBufferPacket(int offset, List<int> bytes) {
  final int length = 14 + bytes.length + 1 - 7;
  final List<int> p = <int>[
    0x00, 0x59, 0x22, length & 0xFF, length >> 8, 0x00, 0x05, //
    offset & 0xFF, (offset >> 8) & 0xFF, (offset >> 16) & 0xFF, offset >> 24,
    bytes.length & 0xFF, bytes.length >> 8, 0x00,
    ...bytes,
    0x00,
  ];
  p[p.length - 1] = mefcsChecksum(p);
  return Uint8List.fromList(p);
}

/// Plays the IR in the buffer. Stores nothing.
Uint8List irApplyPacket() => _sealed(<int>[
  0x00, 0x59, 0x22, 0x09, 0x00, 0x00, 0x05, //
  0x00, 0x00, 0x00, 0xA0, 0x01, 0x00, 0x00, 0x02, 0x00,
]);

/// Copies the buffer to CAB slot [slot] (0..19). Writes to flash.
Uint8List irSaveToSlotPacket(int slot) {
  if (slot < 0 || slot >= irSlotCount) {
    throw ArgumentError('invalid IR slot $slot');
  }
  return _sealed(<int>[
    0x00, 0x59, 0x22, 0x09, 0x00, 0x00, 0x05, //
    slot, 0x01, 0x00, 0xF0, 0x01, 0x00, 0x00, 0x00, 0x00,
  ]);
}

Uint8List _sealed(List<int> p) {
  p[p.length - 1] = mefcsChecksum(p);
  return Uint8List.fromList(p);
}
