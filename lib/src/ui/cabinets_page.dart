// SPDX-License-Identifier: GPL-3.0-only

import 'package:flutter/material.dart';

import '../presets/ir_upload.dart';
import 'visuals.dart';

/// The 20 CAB slots, with a way to put a user IR in one of them.
class CabinetsPage extends StatelessWidget {
  const CabinetsPage({
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
    this.copies = const <int, String>{},
    this.onRestoreCopy,
    this.amp = false,
    this.onKind,
  });

  /// Shows the 20 AMP slots (amp captures) instead of the 20 CAB slots.
  final bool amp;
  final void Function(bool amp)? onKind;

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

  /// Slots with a copy of the IR this app sent there: the name it was sent as.
  /// The pedal cannot give an IR back, so these are the only copies.
  final Map<int, String> copies;
  final void Function(int slot)? onRestoreCopy;

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
                  Text(
                    amp ? 'Amp captures' : 'Cabinets',
                    style: theme.textTheme.titleLarge,
                  ),
                  Text(
                    amp
                        ? 'Put your own captures in the 20 AMP slots: AM3 '
                              'with its LMT block (from M-EFCS) or a pedal NAM '
                              'model (from the Tone3000 converter).'
                        : 'Put your own IRs in the 20 CAB slots: WAV, 44.1 '
                              'kHz, mono, 24-bit, $irSampleCount samples.',
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
        if (onKind != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(
                  value: false,
                  label: Text('CAB'),
                  icon: BlockIcon('CAB', size: 18),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text('AMP'),
                  icon: BlockIcon('AMP', size: 18),
                ),
              ],
              selected: <bool>{amp},
              onSelectionChanged: (Set<bool> s) => onKind!(s.first),
            ),
          ),
        if (irNeedsUsb)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'The pedal is connected over Bluetooth. Connect the USB cable '
              'to upload IRs.',
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
          EmptyState(
            icon: Icons.speaker_group_outlined,
            title: amp ? 'Your own amps' : 'Your own cabinets',
            message: canUsePedal
                ? 'Read the slot names from the pedal to start.'
                : 'Connect the pedal to see its ${amp ? 'AMP' : 'CAB'} slots.',
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
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: theme.colorScheme.secondaryContainer,
                      foregroundColor: theme.colorScheme.onSecondaryContainer,
                      child: Text(
                        '${i + 1}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                    title: Text(
                      // The pedal overwrites the first character of the
                      // first name with the request's checksum.
                      i == 0 && n[0].isNotEmpty
                          ? '?${n[0].substring(1)}'
                          : n[i],
                    ),
                    subtitle: copies.containsKey(i)
                        ? Text(
                            'Copy kept: "${copies[i]}"',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          )
                        : null,
                    trailing: Wrap(
                      spacing: 4,
                      children: <Widget>[
                        if (copies.containsKey(i) && onRestoreCopy != null)
                          TextButton.icon(
                            onPressed: canUsePedal && !irNeedsUsb && !busy
                                ? () => onRestoreCopy!(i)
                                : null,
                            icon: const Icon(Icons.history),
                            label: const Text('Restore copy…'),
                          ),
                        TextButton.icon(
                          onPressed: canUsePedal && !irNeedsUsb && !busy
                              ? () => onReplace(i)
                              : null,
                          icon: const Icon(Icons.upload_file),
                          label: Text(
                            amp
                                ? 'Replace with a capture…'
                                : 'Replace with a WAV…',
                          ),
                        ),
                      ],
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
  bool amp = false,
}) {
  final TextEditingController name = TextEditingController(
    text: sanitizeIrName(suggested),
  );
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded),
      title: Text('Replace ${amp ? 'AMP' : 'CAB'} slot ${slot + 1}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '"$current" is replaced for good: the pedal cannot give it back. '
            'The app keeps a copy of the new one, to restore it later. '
            'Presets that use this slot will play the new '
            '${amp ? 'capture' : 'IR'}.',
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
