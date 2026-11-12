// SPDX-License-Identifier: GPL-3.0-only

import 'dart:typed_data';

import 'ir_upload.dart';
import 'mefcs.dart';

/// Amp captures for the 20 AMP slots, in the two formats firmware V1.05
/// takes (probe-pocket-amp `PROTOCOLO_IR.md`, pocket-amp-firmware
/// `reconstrucao/UPLOAD.md`):
///
/// - `AM3\0`: what M-EFCS sends, 6204 B (20 B header and GRU weights) plus the
///   `LMT\0` block M-EFCS computes with its own DLL, 6272 B in all. A file
///   without that block is refused: the app cannot compute it yet.
/// - `NAM\0`: the pedal's own fixed network (3 channels, 23 layers), 7548 B,
///   or 7836 B with the optional `BEND` block. Not the community `.nam`.
///
/// Both are sent like an IR, through the same 12 KiB buffer, in 1015-byte
/// chunks: the file as it is, "apply", the file again with the slot name in
/// bytes 4..17, and "store", which writes the slot in flash.
const int ampSlotCount = 20;
const int am3Length = 6204;
const int am3WithLmtLength = am3Length + 4 + 16 * 4;
const int namLength = 7548;
const int namWithBendLength = 7836;

/// Every image length the guard lets through.
const Set<int> ampImageLengths = <int>{
  am3WithLmtLength,
  namLength,
  namWithBendLength,
};

const List<int> am3Magic = <int>[0x41, 0x4D, 0x33, 0x00]; // "AM3\0"
const List<int> namMagic = <int>[0x4E, 0x41, 0x4D, 0x00]; // "NAM\0"
const List<int> _lmtMagic = <int>[0x4C, 0x4D, 0x54, 0x00]; // "LMT\0"
const List<int> _bendMagic = <int>[0x42, 0x45, 0x4E, 0x44]; // "BEND"

/// Checks a capture file and returns it as the image to send.
Uint8List parseAmpFile(List<int> bytes) {
  final Uint8List b = Uint8List.fromList(bytes);
  bool at(int o, List<int> magic) =>
      b.length >= o + magic.length &&
      Iterable<int>.generate(magic.length)
          .every((int i) => b[o + i] == magic[i]);
  if (at(0, am3Magic)) {
    if (b.length == am3Length) {
      throw const InvalidIrFile(
        'This .am3 has no LMT block. M-EFCS adds it when it sends a capture, '
        'and this app cannot compute it yet: send it once with M-EFCS, or '
        'use a file that already has it.',
      );
    }
    if (b.length != am3WithLmtLength || !at(am3Length, _lmtMagic)) {
      throw InvalidIrFile(
        'An AM3 capture has $am3WithLmtLength bytes with its LMT block; this '
        'one has ${b.length}.',
      );
    }
    _checkFloats(b, 20, am3Length);
    return b;
  }
  if (at(0, namMagic)) {
    if (b.length != namLength && b.length != namWithBendLength) {
      throw InvalidIrFile(
        'A pedal NAM model has $namLength or $namWithBendLength bytes; this '
        'one has ${b.length}. A .nam from Tone3000 or the NAM project is a '
        'different network and must be converted first.',
      );
    }
    if (b.length == namWithBendLength && !at(7544, _bendMagic)) {
      throw const InvalidIrFile(
        'The model is 7836 bytes but has no BEND block.',
      );
    }
    // The firmware refuses inf and NaN in the weights (UPLOAD.md §3).
    _checkFloats(b, 60, 7544);
    return b;
  }
  if (b.isNotEmpty && b[0] == 0x7B) {
    throw const InvalidIrFile(
      'This is a .nam from the NAM project (Tone3000), a different network '
      'from the pedal\'s. Convert it to the pedal format first.',
    );
  }
  throw const InvalidIrFile(
    'Not an amp capture the pedal takes (AM3 with LMT, or the pedal\'s NAM).',
  );
}

void _checkFloats(Uint8List b, int from, int to) {
  final ByteData d = ByteData.sublistView(b);
  for (int o = from; o + 4 <= to; o += 4) {
    if (!d.getFloat32(o, Endian.little).isFinite) {
      throw InvalidIrFile('The weights hold an infinite or NaN value at $o.');
    }
  }
}

/// [image] with [name] in bytes 4..17, padded with NULs.
Uint8List withAmpName(Uint8List image, String name) {
  final List<int> n = sanitizeIrName(name).codeUnits;
  return Uint8List.fromList(image)
    ..setAll(4, <int>[for (int i = 0; i < irNameMaxLength + 1; i++) 0])
    ..setAll(4, n);
}

/// The 1015-byte chunks of an image, by offset.
Map<int, int> ampChunkGrid(int length) => <int, int>{
  for (int at = 0; at < length; at += irChunkLength)
    at: length - at < irChunkLength ? length - at : irChunkLength,
};

/// The packets that put [image] in AMP slot [slot] (0..19) as [name], in
/// order; the last one writes flash.
List<(Uint8List, String)> ampUploadPackets(
  int slot,
  String name,
  Uint8List image,
) {
  if (slot < 0 ||
      slot >= ampSlotCount ||
      !ampImageLengths.contains(image.length)) {
    throw ArgumentError('invalid amp upload');
  }
  final Uint8List named = withAmpName(image, name);
  List<(Uint8List, String)> send(Uint8List img, String what) =>
      <(Uint8List, String)>[
        for (final MapEntry<int, int> e in ampChunkGrid(img.length).entries)
          (irBufferPacket(e.key, img.sublist(e.key, e.key + e.value)), what),
      ];
  return <(Uint8List, String)>[
    ...send(image, 'sending the capture'),
    (ampApplyPacket(), 'applying the capture'),
    ...send(named, 'naming the capture'),
    (ampSaveToSlotPacket(slot), 'storing the capture in AMP slot ${slot + 1}'),
  ];
}

/// Plays the capture in the buffer. Stores nothing.
Uint8List ampApplyPacket() => _sealed(<int>[
  0x00, 0x59, 0x22, 0x09, 0x00, 0x00, 0x05, //
  0x00, 0x00, 0x00, 0xA0, 0x01, 0x00, 0x00, 0x01, 0x00,
]);

/// Copies the buffer to AMP slot [slot] (0..19). Writes to flash.
Uint8List ampSaveToSlotPacket(int slot) {
  if (slot < 0 || slot >= ampSlotCount) {
    throw ArgumentError('invalid AMP slot $slot');
  }
  return _sealed(<int>[
    0x00, 0x59, 0x22, 0x09, 0x00, 0x00, 0x05, //
    slot, 0x00, 0x00, 0xF0, 0x01, 0x00, 0x00, 0x00, 0x00,
  ]);
}

Uint8List _sealed(List<int> p) {
  p[p.length - 1] = mefcsChecksum(p);
  return Uint8List.fromList(p);
}
