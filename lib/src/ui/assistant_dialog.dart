// SPDX-License-Identifier: GPL-3.0-only

import 'package:flutter/material.dart';

import '../assistant/assistant.dart';
import '../presets/preset_backup.dart';
import 'presets_page.dart';

/// Asks the assistant to change the selected preset. The answer goes into
/// the editor (and is heard live when live editing is on); nothing is
/// written to the pedal until the user writes.
Future<String?> showAssistant(BuildContext context, PresetWorkspace w) =>
    showDialog<String>(
      context: context,
      // Closed only by its buttons: an answer must not land unseen.
      barrierDismissible: false,
      builder: (BuildContext context) => _AssistantDialog(workspace: w),
    );

class _AssistantDialog extends StatefulWidget {
  const _AssistantDialog({required this.workspace});
  final PresetWorkspace workspace;

  @override
  State<_AssistantDialog> createState() => _AssistantDialogState();
}

class _AssistantDialogState extends State<_AssistantDialog> {
  final TextEditingController _request = TextEditingController();
  final TextEditingController _url = TextEditingController();
  final TextEditingController _model = TextEditingController();
  final TextEditingController _key = TextEditingController();
  bool _loaded = false;
  bool _showSettings = false;
  bool _asking = false;
  String? _error;

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
        _showSettings = !s.ready;
        _loaded = true;
      });
    });
  }

  AssistantSettings get _settings => AssistantSettings(
    baseUrl: _url.text,
    model: _model.text,
    apiKey: _key.text,
  );

  Future<void> _ask() async {
    final PresetWorkspace w = widget.workspace;
    final int id = w.selected;
    final PresetBackup draft = w.draft!;
    setState(() {
      _asking = true;
      _error = null;
    });
    try {
      await _settings.save();
      final Map<String, Object> current = draft.presetFields(id);
      final Map<String, Object?> answer = await askAssistant(
        _settings,
        _request.text.trim(),
        current,
      );
      if (!mounted || !identical(w.draft, draft) || w.selected != id) {
        return; // the editor moved on meanwhile
      }
      draft.setPresetFields(id, mergeSuggestion(current, answer));
      w.edited();
      w.showOnPedal();
      if (mounted) {
        Navigator.pop(
          context,
          'The assistant changed ${slotName(id)}. Listen, adjust, and write '
          'it when you like it.',
        );
      }
    } on AssistantException catch (e) {
      _show(e.message);
    } on FormatException catch (e) {
      _show('The suggestion is not a preset the pedal can take: ${e.message}');
    } catch (e) {
      _show('$e');
    } finally {
      if (mounted) {
        setState(() => _asking = false);
      }
    }
  }

  void _show(String error) {
    if (mounted) {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return PopScope(canPop: !_asking, child: _dialog(theme));
  }

  Widget _dialog(ThemeData theme) {
    return AlertDialog(
      scrollable: true,
      icon: const Icon(Icons.auto_awesome),
      title: Text(
        'Ask the assistant about ${slotName(widget.workspace.selected)}',
      ),
      content: SizedBox(
        width: 480,
        child: !_loaded
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextField(
                    controller: _request,
                    autofocus: true,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'What should it sound like?',
                      hintText:
                          'e.g. less gain, a short slapback delay, '
                          'brighter for a single-coil guitar',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The request and this preset are sent to the service set '
                    'below. The answer replaces the preset in the editor; '
                    'nothing is stored on the pedal until you write.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                    ),
                    onPressed: () =>
                        setState(() => _showSettings = !_showSettings),
                    icon: Icon(
                      _showSettings ? Icons.expand_less : Icons.expand_more,
                    ),
                    label: const Text('Assistant settings'),
                  ),
                  if (_showSettings) ...<Widget>[
                    TextField(
                      controller: _url,
                      decoration: const InputDecoration(
                        labelText: 'Address (OpenAI-compatible)',
                        hintText: 'https://…/v1',
                      ),
                    ),
                    TextField(
                      controller: _model,
                      decoration: const InputDecoration(labelText: 'Model'),
                    ),
                    TextField(
                      controller: _key,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'API key (if the service needs one)',
                        helperText: 'Kept on this computer, in plain text.',
                      ),
                    ),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                ],
              ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _asking ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _asking || !_loaded ? null : _ask,
          icon: _asking
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome),
          label: const Text('Suggest'),
        ),
      ],
    );
  }
}
