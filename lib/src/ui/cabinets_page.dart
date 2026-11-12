// SPDX-License-Identifier: GPL-3.0-only

import 'package:flutter/material.dart';

import '../presets/ir_upload.dart';

/// The 20 CAB slots, with a way to put a user IR in one of them; with the
/// AMP texts, the 20 AMP slots and a way to put a .nam capture in one.
class CabinetsPage extends StatelessWidget {
  const CabinetsPage({
    this.block = 'CAB',
    this.title = 'Cabinets',
    this.intro =
        'Put your own IRs in the 20 CAB slots: WAV, 44.1 kHz, '
        'mono, 24-bit, $irSampleCount samples.',
    this.what = 'IRs',
    this.replaceLabel = 'Replace with a WAV…',
    super.key,
    required this.names,
    required this.canUsePedal,
    required this.irNeedsUsb,
    required this.busy,
    required this.task,
    required this.fraction,
    required this.message,
    required this.messageIsError,
    required this.onReadNames,
    required this.onReplace,
  });

  /// As stored on the pedal; null until read.
  final List<String>? names;
  final bool canUsePedal;

  /// Connected over Bluetooth: names can be read, IRs are sent over USB only.
  final bool irNeedsUsb;
  final bool busy;
  final String? task;
  final double? fraction;
  final String? message;
  final bool messageIsError;
  final VoidCallback onReadNames;
  final void Function(int slot) onReplace;
  final String block, title, intro, what, replaceLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String>? n = names;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: theme.textTheme.titleLarge),
                  Text(
                    intro,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: canUsePedal && !busy ? onReadNames : null,
              icon: const Icon(Icons.refresh),
              label: Text(n == null ? 'Read from pedal' : 'Read again'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (irNeedsUsb)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'The pedal is connected over Bluetooth. Connect the USB cable '
              'to upload $what.',
              style: TextStyle(color: theme.colorScheme.tertiary),
            ),
          ),
        if (task != null) ...<Widget>[
          Text(task!),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: fraction),
          const SizedBox(height: 12),
        ] else if (message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              message!,
              style: messageIsError
                  ? TextStyle(color: theme.colorScheme.error)
                  : null,
            ),
          ),
        if (n == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              canUsePedal
                  ? 'Read the slot names from the pedal to start.'
                  : 'Connect the pedal to see its $block slots.',
              textAlign: TextAlign.center,
            ),
          )
        else
          Card.outlined(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                for (int i = 0; i < n.length; i++) ...<Widget>[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    leading: SizedBox(
                      width: 28,
                      child: Text(
                        '${i + 1}',
                        style: theme.textTheme.labelLarge,
                        textAlign: TextAlign.end,
                      ),
                    ),
                    title: Text(
                      // The pedal overwrites the first character of the
                      // first name with the request's checksum.
                      i == 0 && n[0].isNotEmpty
                          ? '?${n[0].substring(1)}'
                          : n[i],
                    ),
                    trailing: TextButton.icon(
                      onPressed: canUsePedal && !irNeedsUsb && !busy
                          ? () => onReplace(i)
                          : null,
                      icon: const Icon(Icons.upload_file),
                      label: Text(replaceLabel),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Asks for the name and confirms; null when cancelled.
Future<String?> confirmIrUpload(
  BuildContext context,
  int slot,
  String current,
  String suggested, {
  String block = 'CAB',
  String what = 'IRs',
  String plays = 'IR',
}) {
  final TextEditingController name = TextEditingController(
    text: sanitizeIrName(suggested),
  );
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded),
      title: Text('Replace $block slot ${slot + 1}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '"$current" is replaced for good: the app cannot read $what back '
            'from the pedal, so it cannot keep a copy. Presets that use this '
            'slot will play the new $plays.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: name,
            maxLength: irNameMaxLength,
            decoration: const InputDecoration(
              labelText: 'Name on the pedal',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: name,
          builder: (BuildContext context, TextEditingValue v, _) =>
              FilledButton(
                onPressed: sanitizeIrName(v.text).trim().isEmpty
                    ? null
                    : () => Navigator.pop(context, sanitizeIrName(v.text)),
                child: const Text('Replace'),
              ),
        ),
      ],
    ),
  );
}
