// SPDX-License-Identifier: GPL-3.0-only

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Crash and update reports sent to Sentry, only when the user agreed.
///
/// Builds without `--dart-define=SENTRY_DSN=...` (forks, local builds) have
/// no reporting at all and never ask.
class Telemetry {
  Telemetry._();

  static const String _dsn = String.fromEnvironment('SENTRY_DSN');
  static bool get available => _dsn.isNotEmpty;

  static bool _on = false;
  static bool get on => _on;

  /// The user's answer, or null when never asked.
  static Future<bool?> choice() async {
    try {
      final String s = (await _file()).readAsStringSync().trim();
      return s == 'on' ? true : (s == 'off' ? false : null);
    } on FileSystemException {
      return null;
    }
  }

  /// Stores the answer and starts or stops reporting to match it.
  static Future<void> choose(bool yes) async {
    final File f = await _file();
    await f.parent.create(recursive: true);
    await f.writeAsString(yes ? 'on' : 'off');
    if (yes) {
      await start();
    } else if (_on) {
      _on = false;
      await Sentry.close();
    }
  }

  /// Starts reporting when the user already agreed. Never throws: reporting
  /// must not keep the app from opening.
  static Future<void> startIfAllowed() async {
    try {
      if (available && await choice() == true) {
        await start();
      }
    } catch (_) {}
  }

  static Future<void> start() async {
    if (!available || _on) {
      return;
    }
    // The native SDK keeps its crash database in the working folder unless
    // told otherwise: keep it with the app's own files.
    final String support = (await getApplicationSupportDirectory()).path;
    await SentryFlutter.init((SentryFlutterOptions o) {
      o
        ..dsn = _dsn
        ..nativeDatabasePath = '$support${Platform.pathSeparator}sentry-native'
        ..environment = kReleaseMode ? 'production' : 'development'
        ..sendDefaultPii = false
        ..beforeBreadcrumb = (Breadcrumb? b, Hint _) {
          b?.message = scrub(b.message);
          return b;
        }
        ..beforeSend = (SentryEvent e, Hint _) {
          e
            ..serverName = null
            ..user = null;
          final SentryMessage? m = e.message;
          if (m != null) {
            m.formatted = scrub(m.formatted)!;
          }
          for (final SentryException x in e.exceptions ?? <SentryException>[]) {
            x.value = scrub(x.value);
            // Debug and profile builds report source paths, which start in
            // the user's home folder.
            for (final SentryStackFrame f
                in x.stackTrace?.frames ?? <SentryStackFrame>[]) {
              f
                ..absPath = scrub(f.absPath)
                ..fileName = scrub(f.fileName);
            }
          }
          return e;
        };
    });
    _on = true;
  }

  /// A log line, kept to explain the next report.
  static void log(String line) {
    if (_on) {
      unawaited(Sentry.addBreadcrumb(Breadcrumb(message: line)));
    }
  }

  /// How a firmware update ended, so the pedals that work are known.
  static void update({
    required String from,
    required String to,
    String? after,
    Object? error,
  }) {
    if (!_on) {
      return;
    }
    unawaited(
      Sentry.captureMessage(
        error == null ? 'Update finished' : 'Update failed',
        level: error == null ? SentryLevel.info : SentryLevel.warning,
        withScope: (Scope s) async {
          await s.setTag('pedal_from', from);
          await s.setTag('package', to);
          await s.setTag('pedal_after', after ?? '-');
          if (error != null) {
            await s.setContexts('error', <String, String>{
              'message': scrub('$error')!,
            });
          }
        },
      ),
    );
  }

  /// [text] without the user's home folder, which carries their name.
  ///
  /// Matches the folder as written in `HOME` or `USERPROFILE` and, on
  /// Windows, with either kind of slash and any letter case. A home that is
  /// only a root (`/`, `C:\`), as in a container, is left alone: replacing it
  /// would garble every path in the text. [home] and [windows] are for tests.
  static String? scrub(String? text, {Iterable<String?>? home, bool? windows}) {
    if (text == null) {
      return null;
    }
    final bool win = windows ?? Platform.isWindows;
    final Set<String> folders = <String>{};
    for (final String? h in home ?? _homes()) {
      String f = (h ?? '').trim();
      while (f.length > 1 && (f.endsWith('/') || f.endsWith(_bs))) {
        f = f.substring(0, f.length - 1);
      }
      // Root only: "/", "C:", "C:\" (already trimmed to "C:").
      if (f.length < 2 || RegExp(r'^[A-Za-z]:$').hasMatch(f)) {
        continue;
      }
      folders.add(f);
      if (win) {
        folders
          ..add(f.replaceAll(_bs, '/'))
          ..add(f.replaceAll('/', _bs));
      }
    }
    // Longest first, so a home inside another home is replaced whole.
    final List<String> order = folders.toList()
      ..sort((String a, String b) => b.length.compareTo(a.length));
    String out = text;
    for (final String f in order) {
      out = out.replaceAll(RegExp(RegExp.escape(f), caseSensitive: !win), '~');
    }
    return out;
  }

  static const String _bs = '\\';

  static List<String?> _homes() => <String?>[
    Platform.environment['HOME'],
    Platform.environment['USERPROFILE'],
  ];

  static Future<File> _file() async => File(
    '${(await getApplicationSupportDirectory()).path}'
    '${Platform.pathSeparator}telemetry',
  );
}
