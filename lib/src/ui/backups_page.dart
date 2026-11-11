// SPDX-License-Identifier: GPL-3.0-only

import 'dart:io';

import 'package:flutter/material.dart';

import '../presets/preset_backup.dart';

/// The backups the app keeps on its own (one before every update), with a
/// way to open one in the editor or restore it.
class BackupsPage extends StatefulWidget {
  const BackupsPage({
    super.key,
    required this.list,
    required this.canRestore,
    required this.onEdit,
    required this.onRestore,
    required this.onRestoreRaw,
    required this.onSaveNew,
    this.task,
    this.fraction,
    this.message,
    this.messageIsError = false,
  });

  /// The running pedal task and the last result, shown above the list.
  final String? task;
  final double? fraction;
  final String? message;
  final bool messageIsError;

  final Future<List<(File, PresetBackup?, String?)>> Function() list;
  final bool canRestore;
  final void Function(PresetBackup b, String name) onEdit;
  final void Function(PresetBackup b, String name) onRestore;
  final void Function(File raw) onRestoreRaw;
  final Future<void> Function() onSaveNew;

  @override
  State<BackupsPage> createState() => _BackupsPageState();
}

class _BackupsPageState extends State<BackupsPage> {
  late Future<List<(File, PresetBackup?, String?)>> _files = widget.list();

  void _reload() => setState(() => _files = widget.list());

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Backups', style: theme.textTheme.titleLarge),
                  Text(
                    'Kept in Documents/Pocket AMP Tools. The app adds one '
                    'before every firmware update.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: widget.canRestore
                  ? () async {
                      await widget.onSaveNew();
                      if (mounted) {
                        _reload();
                      }
                    }
                  : null,
              icon: const Icon(Icons.add),
              label: const Text('Back up the pedal now'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (widget.task != null) ...<Widget>[
          Text(widget.task!),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: widget.fraction),
          const SizedBox(height: 16),
        ] else if (widget.message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              widget.message!,
              style: widget.messageIsError
                  ? TextStyle(color: theme.colorScheme.error)
                  : null,
            ),
          ),
        FutureBuilder<List<(File, PresetBackup?, String?)>>(
          future: _files,
          builder:
              (
                BuildContext context,
                AsyncSnapshot<List<(File, PresetBackup?, String?)>> snap,
              ) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError) {
                  return Text(
                    'Could not list the backups: ${snap.error}',
                    style: TextStyle(color: theme.colorScheme.error),
                  );
                }
                final List<(File, PresetBackup?, String?)> files = snap.data!;
                if (files.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text('No backups yet.', textAlign: TextAlign.center),
                  );
                }
                return Card.outlined(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: <Widget>[
                      for (final (int i, (File f, PresetBackup? b, String? e))
                          in files.indexed) ...<Widget>[
                        if (i > 0) const Divider(height: 1),
                        _BackupTile(
                          file: f,
                          backup: b,
                          error: e,
                          canRestore: widget.canRestore,
                          onEdit: widget.onEdit,
                          onRestore: widget.onRestore,
                          onRestoreRaw: widget.onRestoreRaw,
                        ),
                      ],
                    ],
                  ),
                );
              },
        ),
      ],
    );
  }
}

class _BackupTile extends StatelessWidget {
  const _BackupTile({
    required this.file,
    required this.backup,
    required this.error,
    required this.canRestore,
    required this.onEdit,
    required this.onRestore,
    required this.onRestoreRaw,
  });
  final File file;
  final PresetBackup? backup;
  final String? error;
  final bool canRestore;
  final void Function(PresetBackup b, String name) onEdit;
  final void Function(PresetBackup b, String name) onRestore;
  final void Function(File raw) onRestoreRaw;

  @override
  Widget build(BuildContext context) {
    final String name = file.uri.pathSegments.last;
    final PresetBackup? b = backup;
    if (b == null && error == null) {
      return ListTile(
        leading: const Icon(Icons.inventory_2_outlined),
        title: Text(name),
        subtitle: const Text(
          'Raw copy from older firmware: P01–P79 can be restored; P80 and '
          'the EQ stay as they are on the pedal.',
        ),
        trailing: OutlinedButton.icon(
          onPressed: canRestore ? () => onRestoreRaw(file) : null,
          icon: const Icon(Icons.history),
          label: const Text('Restore…'),
        ),
      );
    }
    if (b == null) {
      return ListTile(
        leading: const Icon(Icons.error_outline),
        title: Text(name),
        subtitle: Text('Not readable: $error'),
      );
    }
    return ListTile(
      leading: const Icon(Icons.inventory_2_outlined),
      title: Text(b.created.toLocal().toString().substring(0, 16)),
      subtitle: Text('${b.identity} · $name'),
      trailing: Wrap(
        spacing: 8,
        children: <Widget>[
          TextButton.icon(
            onPressed: () => onEdit(b, name),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Open in editor'),
          ),
          OutlinedButton.icon(
            onPressed: canRestore ? () => onRestore(b, name) : null,
            icon: const Icon(Icons.history),
            label: const Text('Restore…'),
          ),
        ],
      ),
    );
  }
}
