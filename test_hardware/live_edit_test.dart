// ignore_for_file: avoid_print
// LIVE RAM ONLY. Edits the active preset in the pedal's live RAM through the
// app's LiveLink, checks each change, then loads the preset again, which
// brings back what is stored. Nothing is saved or committed.
//   CONFIRM_LIVE=yes flutter test test_hardware/live_edit_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_amp_tools/src/midi/alsa_backend.dart';
import 'package:pocket_amp_tools/src/pedal_updater.dart';
import 'package:pocket_amp_tools/src/presets/live_link.dart';
import 'package:pocket_amp_tools/src/presets/mefcs.dart';
import 'package:pocket_amp_tools/src/presets/preset_backup.dart';
import 'package:pocket_amp_tools/src/presets/preset_session.dart';

void main() {
  test(
    'live edits reach the pedal and a reload undoes them',
    () async {
      final AlsaBackend backend = AlsaBackend();
      final DetectedPedal pedal = (await PedalUpdater(backend).detect())!;
      final PresetSession s = PresetSession(await backend.open(pedal.port));
      final List<Object> errors = <Object>[];
      final LiveLink link = LiveLink(s, onError: errors.add);
      const int id = 79; // P80
      try {
        final PresetBackup bank = await readPresetBank(s, pedal.identity);
        final Uint8List stored = Uint8List.fromList(bank.preset(id));

        // Show P80 as stored: a Load Preset and nothing else to sync.
        await link.show(id, stored);
        await link.flush();
        expect(await s.readLive(), stored, reason: 'P80 loaded as stored');

        // DLY on/off, then the first DLY knob, then the chain reversed.
        final bool dlyOn = stored[8 + 3] == 1;
        link.toggle(3, !dlyOn);
        final int knob = stored[20 + 3 * 12];
        final int other = knob >= 50 ? knob - 30 : knob + 30;
        link.knob(3, 0, other);
        // FX and AMP swapped, the other four reversed: an order the pedal
        // takes (it ignores any with FX or AMP past the first two places).
        final List<int> chain = <int>[
          stored[3],
          stored[2],
          ...stored.sublist(4, 8).reversed,
        ];
        link.chain(chain);
        await link.flush();
        final Uint8List edited = await s.readLive();
        print('errors so far: $errors');
        print(
          'DLY on: ${edited[8 + 3]}  knob: ${edited[20 + 36]}  '
          'chain: ${edited.sublist(2, 8)}',
        );
        expect(edited[8 + 3], dlyOn ? 0 : 1);
        expect(edited[20 + 3 * 12], other);
        expect(edited.sublist(2, 8), chain);
        final List<int> changed = <int>[
          for (int i = 0; i < presetSize; i++)
            if (edited[i] != stored[i]) i,
        ];
        print('bytes changed: $changed');

        // Loading the preset again brings back what is stored.
        await link.show(id, stored);
        await link.flush();
        expect(await s.readLive(), stored, reason: 'reload restores P80');
        final PresetBackup after = await readPresetBank(s, pedal.identity);
        expect(after.presets, bank.presets, reason: 'nothing was stored');
        expect(errors, isEmpty);
      } finally {
        // Whatever happened, load P80 again so the pedal plays what is stored.
        await link.close();
        final PresetSession r = PresetSession(await backend.open(pedal.port));
        await r.write(loadPresetPacket(id), 'reloading P80');
        await r.close();
      }
    },
    skip: Platform.environment['CONFIRM_LIVE'] != 'yes'
        ? 'set CONFIRM_LIVE=yes'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
