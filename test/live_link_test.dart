import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_amp_tools/src/presets/live_link.dart';
import 'package:pocket_amp_tools/src/presets/mefcs.dart';
import 'package:pocket_amp_tools/src/presets/preset_session.dart';

import 'support/fake_pedal.dart';

Future<(FakePedal, LiveLink, List<Object>)> _open() async {
  final FakePedal pedal = FakePedal(image: Uint8List(1024), bank: demoBank());
  final List<Object> errors = <Object>[];
  final LiveLink link = LiveLink(
    PresetSession(await pedal.open(pedal.port)),
    onError: errors.add,
  );
  return (pedal, link, errors);
}

Uint8List _body(FakePedal p, int id) =>
    Uint8List.fromList(p.bank!.sublist(id * presetSize, (id + 1) * presetSize));

void main() {
  test('showing a preset loads it and applies the unsaved edits', () async {
    final (FakePedal pedal, LiveLink link, List<Object> errors) = await _open();
    final Uint8List edited = _body(pedal, 4)
      ..[8 + 3] =
          1 // DLY on
      ..[14 + 2] =
          3 // MOD model 3
      ..[20 + 2 * 12] =
          77 // MOD first knob, after the model change
      ..setAll(2, <int>[1, 0, 5, 4, 3, 2]);
    await link.show(4, edited);
    await link.flush();

    expect(errors, isEmpty);
    expect(pedal.active, 4);
    expect(pedal.live.sublist(2, 20), edited.sublist(2, 20));
    expect(pedal.live[20 + 2 * 12], 77);
    expect(pedal.liveWrites.first, 'load 4');

    // Closing loads the preset again: the edits played live, not stored,
    // leave the pedal.
    await link.close();
    expect(pedal.liveWrites.last, 'load 4');
    expect(pedal.live, _body(pedal, 4));
  });

  test('a knob moved many times is sent once, with the last value', () async {
    final (FakePedal pedal, LiveLink link, List<Object> errors) = await _open();
    link.toggle(0, true); // keeps the queue busy while the knob moves
    for (int v = 0; v <= 60; v += 10) {
      link.knob(1, 2, v);
    }
    await link.flush();
    await link.close();

    expect(errors, isEmpty);
    expect(pedal.liveWrites, <String>['8=1', '36=60,0']);
  });

  test('a model change returns the knobs the pedal reset', () async {
    final (FakePedal pedal, LiveLink link, _) = await _open();
    final Uint8List? live = await link.model(4, 2);
    await link.close();
    expect(live![14 + 4], 2);
    expect(live[20 + 4 * 12], 50); // the fake pedal's default
  });

  test('a refused command is reported and the queue goes on', () async {
    final (FakePedal pedal, LiveLink link, List<Object> errors) = await _open();
    link.chain(<int>[0, 0, 1, 2, 3, 4]); // not an order: never sent
    final Uint8List? none = await link.model(0, 99); // FX has 10 models
    link.toggle(1, false);
    await link.flush();
    await link.close();

    expect(none, isNull);
    expect(errors, hasLength(1));
    expect(pedal.liveWrites, <String>['9=0']);
  });
}
