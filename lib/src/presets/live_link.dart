// SPDX-License-Identifier: GPL-3.0-only

import 'dart:async';
import 'dart:typed_data';

import 'block_models.dart';
import 'mefcs.dart';
import 'preset_backup.dart' show blockNames;
import 'preset_session.dart';

/// Edits the active preset in the pedal's live RAM, so changes are heard as
/// they are made. Nothing here is stored: switching presets or turning the
/// pedal off brings back what is saved. Volume and EQ have no live command
/// and are heard only after writing.
///
/// Commands run one at a time, in order. A knob moved several times before
/// its turn is sent once, with the last value. Errors go to [onError] and do
/// not stop the queue.
class LiveLink {
  LiveLink(this._session, {required this.onError});

  final PresetSession _session;
  final void Function(Object error) onError;
  Future<void> _tail = Future<void>.value();
  final Map<int, int> _knobs = <int, int>{};
  bool _closed = false;

  Future<T?> _run<T>(Future<T> Function() step) {
    final Completer<T?> done = Completer<T?>();
    _tail = _tail.then((_) async {
      if (_closed) {
        done.complete(null);
        return;
      }
      try {
        done.complete(await step());
      } catch (e) {
        if (!done.isCompleted) {
          done.complete(null);
        }
        try {
          onError(e);
        } catch (_) {
          // A failing handler must not stop the queue.
        }
      }
    });
    return done.future;
  }

  /// Plays preset [id] and makes it sound like [body], applying live what
  /// differs from what is stored on the pedal.
  /// The preset last loaded on the pedal by [show], if any.
  int? _shown;

  Future<void> show(int id, Uint8List body) => _run(() async {
    _shown = id;
    await _session.write(loadPresetPacket(id), 'selecting the preset');
    final Uint8List live = await _session.readLive();
    await _sync(live, body);
  });

  Future<void> _sync(Uint8List live, Uint8List body) async {
    final List<int> chain = body.sublist(2, 8);
    if (!_same(chain, live.sublist(2, 8)) && pedalTakesChain(chain)) {
      await _session.write(changeRoutingPacket(chain), 'the chain');
    }
    for (int b = 0; b < 6; b++) {
      final int count = blockModels[blockNames[b]]!.length;
      if (body[14 + b] != live[14 + b] && body[14 + b] < count) {
        await _session.write(
          changeModelPacket(b, body[14 + b], count),
          'the model',
        );
        live = await _session.readLive();
      }
      if (body[8 + b] != live[8 + b] && body[8 + b] <= 1) {
        await _session.write(
          toggleBlockPacket(b, body[8 + b] == 1),
          'turning a block on or off',
        );
      }
      for (int k = 0; k < 6; k++) {
        final int at = 20 + b * 12 + k * 2;
        final int v = body[at] | (body[at + 1] << 8);
        if (v != (live[at] | (live[at + 1] << 8)) && v <= 100) {
          await _session.write(changeKnobPacket(b, k, v), 'a knob');
        }
      }
    }
  }

  /// Knob [k] of block [block]; values above 100 are not sent.
  void knob(int block, int k, int value) {
    if (value > 100) {
      return;
    }
    final int key = block * 6 + k;
    final bool queued = _knobs.containsKey(key);
    _knobs[key] = value;
    if (!queued) {
      _run(
        () => _session.write(
          changeKnobPacket(block, k, _knobs.remove(key)!),
          'a knob',
        ),
      );
    }
  }

  void toggle(int block, bool on) => _run(
    () => _session.write(
      toggleBlockPacket(block, on),
      'turning a block on or off',
    ),
  );

  /// Changes the model and returns the live preset afterwards: the pedal
  /// resets the block's knobs to the new model's defaults. Null on error.
  Future<Uint8List?> model(int block, int model) => _run(() async {
    final int count = blockModels[blockNames[block]]!.length;
    await _session.write(changeModelPacket(block, model, count), 'the model');
    return _session.readLive();
  });

  void chain(List<int> order) {
    if (pedalTakesChain(order)) {
      _run(() => _session.write(changeRoutingPacket(order), 'the chain'));
    }
  }

  /// Completes when every command queued so far has run.
  Future<void> flush() => _run(() async {});

  /// Drops what is still queued (it only changes live RAM), lets the
  /// command in flight finish, then closes the port.
  Future<void> close() async {
    _closed = true;
    await _tail;
    // Load the preset again so the edits played live, which are not stored,
    // leave the pedal before anything else (a store) talks to it.
    final int? id = _shown;
    if (id != null) {
      try {
        await _session.write(loadPresetPacket(id), 'reloading the preset');
      } catch (_) {
        // The pedal may be gone; closing goes on.
      }
    }
    await _session.close();
  }
}

bool _same(List<int> a, List<int> b) {
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
