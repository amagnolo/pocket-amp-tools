// ignore_for_file: avoid_print
// Read-only check of the preset tools on a real pedal on Linux: reads the
// whole bank, the model names and the live preset, and checks them against
// the rules the app enforces before writing. Nothing is written.
//   SAVE_TO=/path.json flutter test test_hardware/preset_readonly_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_amp_tools/src/midi/alsa_backend.dart';
import 'package:pocket_amp_tools/src/pedal_updater.dart';
import 'package:pocket_amp_tools/src/presets/block_models.dart';
import 'package:pocket_amp_tools/src/presets/mefcs.dart';
import 'package:pocket_amp_tools/src/presets/preset_backup.dart';
import 'package:pocket_amp_tools/src/presets/preset_session.dart';
import 'package:pocket_amp_tools/src/presets/write_guard.dart';

void main() {
  test('the real bank, names and live preset', () async {
    final AlsaBackend backend = AlsaBackend();
    final DetectedPedal pedal = (await PedalUpdater(backend).detect())!;
    print('pedal: ${pedal.identity}');
    final PresetSession s = PresetSession(await backend.open(pedal.port));
    try {
      final PresetBackup bank = await readPresetBank(s, pedal.identity);
      final String? to = Platform.environment['SAVE_TO'];
      if (to != null) {
        File(to).writeAsStringSync(bank.toJson());
        print('backup kept at $to');
      }

      // Every preset the pedal holds must pass the guard as it is, or the
      // app could never write a change to that slot.
      final List<String> refused = <String>[];
      for (int id = 0; id < presetCount; id++) {
        try {
          checkOutgoing(savePresetPacket(id, bank.preset(id)));
        } on BlockedPacket catch (e) {
          refused.add('P${id + 1}: ${e.reason}');
        }
      }
      print('presets refused by the guard: ${refused.length} $refused');

      final List<String> oddEq = <String>[];
      for (int id = 0; id < presetCount; id++) {
        try {
          saveEqPacket(id, bank.eqRecord(id));
        } on ArgumentError {
          oddEq.add('P${id + 1} ${bank.eqRecord(id)}');
        }
      }
      print('EQ records the app cannot write back: ${oddEq.length} $oddEq');

      // Model bytes past the lists, per block.
      for (int b = 0; b < blockNames.length; b++) {
        final int count = blockModels[blockNames[b]]!.length;
        int top = 0;
        for (int id = 0; id < presetCount; id++) {
          top = bank.model(id, b) > top ? bank.model(id, b) : top;
        }
        print('${blockNames[b]}: highest model ${top + 1} of $count listed');
      }

      final PresetBackup back = PresetBackup.fromJson(bank.toJson());
      expect(back.presets, bank.presets, reason: 'v2 file reopens the same');
      expect(back.eq, bank.eq);

      final List<String> amp = await s.readNames(amp: true);
      final List<String> cab = await s.readNames(amp: false);
      print('AMP names: $amp');
      print('CAB names: $cab');

      final Uint8List live = await s.readLive();
      final List<int> same = <int>[
        for (int id = 0; id < presetCount; id++)
          if (_same(bank.preset(id), live)) id + 1,
      ];
      print('live preset matches stored slot(s): $same');
      expect(refused, isEmpty);
    } finally {
      await s.close();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

bool _same(List<int> a, List<int> b) {
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
