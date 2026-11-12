// SPDX-License-Identifier: GPL-3.0-only

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Copies of the IRs (or, with [amp], the amp captures) this app sent, one
/// per slot.
///
/// The pedal cannot give an IR back: firmware V1.05 only reads the preset and
/// settings area of its flash, and keeps just the first 1024 of the 2048
/// samples it is sent, from a reading of its code (pocket-amp-firmware, `reconstrucao/UPLOAD.md`). So the
/// only copy is the one kept here when the IR is sent, as the WAV file the
/// user chose, named `cab-NN--<name on the pedal>.wav`.
class IrCopies {
  IrCopies(this.dir, {this.amp = false})
    : _file = RegExp(
        amp ? r'^amp-(\d{2})--(.*)\.bin$' : r'^cab-(\d{2})--(.*)\.wav$',
      );
  final Directory dir;

  /// AMP slots (`amp-NN--name.bin`) instead of CAB slots
  /// (`cab-NN--name.wav`).
  final bool amp;
  final RegExp _file;

  /// The copies in `Documents/Pocket AMP Tools/IRs` (or `Amps`).
  static Future<IrCopies> standard({bool amp = false}) async {
    final Directory docs = await getApplicationDocumentsDirectory();
    final String sep = Platform.pathSeparator;
    return IrCopies(
      Directory(
        '${docs.path}${sep}Pocket AMP Tools$sep${amp ? 'Amps' : 'IRs'}',
      ),
      amp: amp,
    );
  }

  /// Keeps [wav] as the copy of [slot] (0..19), sent as [name]; replaces the
  /// slot's earlier copy, which is no longer on the pedal.
  Future<File> keep(int slot, String name, Uint8List wav) async {
    await dir.create(recursive: true);
    final String nn = (slot + 1).toString().padLeft(2, '0');
    // Written first, then the old one removed: a failure leaves a copy.
    final String safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
    final File f = File(
      '${dir.path}${Platform.pathSeparator}'
      '${amp ? 'amp' : 'cab'}-$nn--$safe.${amp ? 'bin' : 'wav'}',
    );
    await f.writeAsBytes(wav, flush: true);
    for (final (int s, _, File old) in await _all()) {
      if (s == slot && old.path != f.path) {
        await old.delete();
      }
    }
    return f;
  }

  /// The kept copies by slot (0..19): the name sent and the file.
  Future<Map<int, (String, File)>> list() async => <int, (String, File)>{
    for (final (int slot, String name, File f) in await _all()) slot: (name, f),
  };

  Future<List<(int, String, File)>> _all() async {
    if (!await dir.exists()) {
      return <(int, String, File)>[];
    }
    return <(int, String, File)>[
      await for (final FileSystemEntity e in dir.list())
        if (e is File)
          if (_file.firstMatch(e.uri.pathSegments.last)
              case final RegExpMatch m)
            if (int.parse(m.group(1)!) case final int n when n >= 1 && n <= 20)
              (n - 1, m.group(2)!, e),
    ];
  }
}
