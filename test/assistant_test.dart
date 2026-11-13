import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocket_amp_tools/src/assistant/assistant.dart';
import 'package:pocket_amp_tools/src/presets/mefcs.dart';
import 'package:pocket_amp_tools/src/presets/preset_backup.dart';

import 'support/fake_pedal.dart';

PresetBackup _bank() {
  final Uint8List a = demoBank();
  return PresetBackup(
    identity: 'Pocket AMP_105',
    created: DateTime.utc(2026),
    presets: Uint8List.sublistView(a, 0, eqTableAddress),
    eq: Uint8List.sublistView(a, eqTableAddress),
  );
}

const AssistantSettings _settings = AssistantSettings(
  baseUrl: 'https://ai.example/v1/',
  model: 'some-model',
  apiKey: 'k',
);

void main() {
  test('finds the JSON object in a chatty answer', () {
    expect(
      firstJsonObject('Sure! ```json\n{"volume": 70, "x": "a } b"}\n``` Enjoy'),
      <String, Object>{'volume': 70, 'x': 'a } b'},
    );
    expect(firstJsonObject('no preset here'), isNull);
  });

  test('a partial answer becomes a whole preset the pedal can take', () {
    final PresetBackup b = _bank();
    final Map<String, Object> current = b.presetFields(4);
    final Map<String, Object?> merged = mergeSuggestion(
      current,
      <String, Object?>{
        'volume': 70,
        'blocks': <String, Object?>{
          // A new model with only some knobs, no "knobN".
          'DLY': <String, Object?>{
            'on': true,
            'model': 'Duck',
            'knobs': <String, int>{'Time': 30, 'Mix': 25},
          },
          // Same model, one knob changed, by position as in the file.
          'AMP': <String, Object?>{
            'knobs': <Object?>[
              <String, Object?>{'label': 'Gain', 'value': 20},
            ],
          },
        },
      },
    );
    b.setPresetFields(4, merged);
    expect(b.volume(4), 70);
    expect(b.model(4, 3), 1); // Duck
    expect(b.isOn(4, 3), isTrue);
    expect(b.knob(4, 3, 0), 30);
    expect(b.knob(4, 3, 1), 0); // Fb, not given
    expect(b.knob(4, 1, 0), 20);
    expect(b.knob(4, 1, 1), _bank().knob(4, 1, 1), reason: 'kept');
    expect(b.chain(4), _bank().chain(4));
  });

  test('asks the configured service and reads its answer', () async {
    late http.Request sent;
    final Map<String, Object?> preset = await http.runWithClient(
      () => askAssistant(_settings, 'less gain', _bank().presetFields(0)),
      () => MockClient((http.Request r) async {
        sent = r;
        return http.Response(
          jsonEncode(<String, Object>{
            'choices': <Object>[
              <String, Object>{
                'message': <String, Object>{'content': '{"volume": 55}'},
              },
            ],
          }),
          200,
        );
      }),
    );
    expect(preset, <String, Object>{'volume': 55});
    expect(sent.url.toString(), 'https://ai.example/v1/chat/completions');
    expect(sent.headers['authorization'], 'Bearer k');
    final Map<String, Object?> body =
        jsonDecode(sent.body) as Map<String, Object?>;
    expect(body['model'], 'some-model');
    expect(jsonEncode(body['messages']), contains('less gain'));
    expect(jsonEncode(body['messages']), contains('MW-808'));
  });

  test('a refused key is reported plainly', () async {
    await expectLater(
      http.runWithClient(
        () => askAssistant(_settings, 'x', _bank().presetFields(0)),
        () => MockClient((_) async => http.Response('', 401)),
      ),
      throwsA(
        isA<AssistantException>().having(
          (AssistantException e) => e.message,
          'message',
          contains('API key'),
        ),
      ),
    );
  });

  Future<String> failure(http.Response answer) async {
    try {
      await http.runWithClient(
        () => askAssistant(_settings, 'x', _bank().presetFields(0)),
        () => MockClient((_) async => answer),
      );
    } on AssistantException catch (e) {
      return e.message;
    }
    fail('no error');
  }

  test("each service's own error words are passed on", () async {
    // OpenAI and most others, Gemini (in a list), and a bare string.
    expect(
      await failure(
        http.Response('{"error":{"message":"model x not found"}}', 404),
      ),
      allOf(contains('does not know'), contains('model x not found')),
    );
    expect(
      await failure(http.Response('[{"error":{"message":"quota"}}]', 429)),
      allOf(contains('rate-limiting'), contains('quota')),
    );
    expect(
      await failure(http.Response('{"error":"bad model"}', 400)),
      allOf(contains('HTTP 400'), contains('bad model')),
    );
    expect(await failure(http.Response('<html>', 500)), endsWith('HTTP 500.'));
    expect(
      serviceError(utf8.encode('{"message":"${'a' * 400}"}')),
      hasLength(301),
    );
  });

  test('an answer cut off by the token limit says so', () async {
    expect(
      await failure(
        http.Response(
          jsonEncode(<String, Object>{
            'choices': <Object>[
              <String, Object>{
                'message': <String, Object>{'content': '{"volume": 5'},
                'finish_reason': 'length',
              },
            ],
          }),
          200,
        ),
      ),
      contains('cut off'),
    );
  });

  test('a hostile answer neither hangs nor fills memory', () async {
    final Stopwatch clock = Stopwatch()..start();
    expect(firstJsonObject('{' * 200000), isNull);
    expect(clock.elapsed, lessThan(const Duration(seconds: 2)));

    await expectLater(
      http.runWithClient(
        () => askAssistant(_settings, 'x', _bank().presetFields(0)),
        () => MockClient((_) async => http.Response('x' * (2 << 20), 200)),
      ),
      throwsA(
        isA<AssistantException>().having(
          (AssistantException e) => e.message,
          'message',
          contains('too much'),
        ),
      ),
    );
  });
}
