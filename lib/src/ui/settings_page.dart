// SPDX-License-Identifier: GPL-3.0-only

import 'package:flutter/material.dart';

import '../assistant/assistant.dart';

/// The app's settings, one card per subject.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: const AssistantSettingsCard(),
          ),
        ),
      ],
    ),
  );
}

/// Where the assistant's requests go: an OpenAI-compatible service.
class AssistantSettingsCard extends StatefulWidget {
  const AssistantSettingsCard({super.key});

  @override
  State<AssistantSettingsCard> createState() => _AssistantSettingsCardState();
}

class _AssistantSettingsCardState extends State<AssistantSettingsCard> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _model = TextEditingController();
  final TextEditingController _key = TextEditingController();
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    AssistantSettings.load().then((AssistantSettings s) {
      if (!mounted) {
        return;
      }
      setState(() {
        _url.text = s.baseUrl;
        _model.text = s.model;
        _key.text = s.apiKey;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  AssistantSettings get _settings => AssistantSettings(
    baseUrl: _url.text,
    model: _model.text,
    apiKey: _key.text,
  );

  Future<void> _save() async {
    setState(() => _saving = true);
    String done;
    try {
      await _settings.save();
      done = 'Assistant settings saved.';
    } catch (e) {
      done = 'Could not save the assistant settings: $e';
    }
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: !_loaded
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(Icons.auto_awesome),
                      const SizedBox(width: 12),
                      Text('Assistant', style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The assistant sends your request and the preset to this '
                    'service and puts its answer in the editor.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _url,
                    decoration: const InputDecoration(
                      labelText: 'Address (OpenAI-compatible)',
                      hintText: 'https://…/v1',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _model,
                    decoration: const InputDecoration(
                      labelText: 'Model',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _key,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'API key (if the service needs one)',
                      helperText: 'Kept on this computer, in plain text.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
