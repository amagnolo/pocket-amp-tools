// SPDX-License-Identifier: GPL-3.0-only

import 'package:flutter/material.dart';

import 'src/midi/midi_backend.dart';
import 'src/ui/home_page.dart';

void main() => runApp(const PocketAmpApp());

class PocketAmpApp extends StatelessWidget {
  const PocketAmpApp({super.key, this.backend});

  /// Injected in tests and screenshots; the platform backend otherwise.
  final MidiBackend? backend;

  static const Color _seed = Color(0xFFB4531F);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pocket AMP Tools',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: _seed)),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
        ),
      ),
      home: HomePage(backend: backend),
    );
  }
}
