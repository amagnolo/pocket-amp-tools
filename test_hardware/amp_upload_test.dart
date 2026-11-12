// ignore_for_file: avoid_print
// Sends an amp capture (AM3 with LMT, or a pedal NAM model) to one AMP slot of
// a real pedal on Linux and checks the name the pedal reads back. This
// OVERWRITES the slot, and the pedal cannot give the old capture back, so it
// only runs when both are set:
//   AMP_SLOT=20 AMP_FILE=/path/model.bin flutter test test_hardware/amp_upload_test.dart
// AMP_SLOT counts from 1, like the app. AMP_NAME sets the name (default: the
// name inside the file).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_amp_tools/src/midi/alsa_backend.dart';
import 'package:pocket_amp_tools/src/pedal_updater.dart';
import 'package:pocket_amp_tools/src/presets/amp_upload.dart';
import 'package:pocket_amp_tools/src/presets/preset_service.dart';

void main() {
  final String? slot = Platform.environment['AMP_SLOT'];
  final String? file = Platform.environment['AMP_FILE'];

  test('a capture sent to an AMP slot reads back under its name', () async {
    final int s = int.parse(slot!) - 1;
    final Uint8List image = parseAmpFile(File(file!).readAsBytesSync());
    final String name =
        Platform.environment['AMP_NAME'] ??
        String.fromCharCodes(image.sublist(4, 18).takeWhile((int c) => c != 0));
    final AlsaBackend backend = AlsaBackend();
    final DetectedPedal pedal = (await PedalUpdater(backend).detect())!;
    print('pedal: ${pedal.identity}');
    final PresetService presets = PresetService(backend);
    final (List<String> before, List<String> cabs) = await presets.readNames(
      pedal,
    );
    print('AMP slot ${s + 1} before: ${before[s]}');

    final List<String> after = await presets.uploadAmp(
      pedal,
      s,
      name,
      image,
      onProgress: (double p) => print('sent ${(p * 100).round()}%'),
    );
    print('AMP slot ${s + 1} after: ${after[s]}');
    for (int i = 0; i < after.length; i++) {
      if (i != s) {
        expect(after[i], before[i], reason: 'AMP slot ${i + 1} changed');
      }
    }
    final (_, List<String> cabsAfter) = await presets.readNames(pedal);
    expect(cabsAfter, cabs, reason: 'CAB slots untouched');
  }, skip: slot == null || file == null ? 'set AMP_SLOT and AMP_FILE' : false);
}
