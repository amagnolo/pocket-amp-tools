// SPDX-License-Identifier: GPL-3.0-only

import 'package:flutter/material.dart';

import '../presets/preset_meta.dart';

/// Name, rating, description and labels of one preset, at a glance; shows
/// nothing for a preset that has none.
class MetaSummary extends StatelessWidget {
  const MetaSummary({super.key, required this.meta});
  final PresetMeta meta;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PresetMeta m = meta;
    if (m.isEmpty) {
      return const SizedBox.shrink();
    }
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final String labels = <String>[
      for (final MetaCategory c in MetaCategory.values)
        if (m.labels[c]!.isNotEmpty) m.labels[c]!.join(', '),
    ].join('  ·  ');
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Flexible(
                child: Text(
                  m.name.isEmpty ? 'No name' : m.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: m.name.isEmpty ? muted : null,
                  ),
                ),
              ),
              if (m.rating > 0) ...<Widget>[
                const SizedBox(width: 12),
                Semantics(
                  label: '${m.rating} of 5 stars',
                  child: ExcludeSemantics(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        for (int s = 1; s <= 5; s++)
                          Icon(
                            s <= m.rating ? Icons.star : Icons.star_border,
                            size: 16,
                            color: s <= m.rating
                                ? theme.colorScheme.primary
                                : muted,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (m.description.isNotEmpty)
            Text(
              m.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
          if (labels.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                labels,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
        ],
      ),
    );
  }
}

/// Edits the name, rating, description and labels of preset [id].
Future<void> showMetaEditor(
  BuildContext context,
  PresetLibrary library,
  int id,
  String title,
) => showDialog<void>(
  context: context,
  builder: (BuildContext context) => AlertDialog(
    title: Text(title),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: ListenableBuilder(
          listenable: library,
          builder: (BuildContext context, _) =>
              MetaCard(library: library, id: id, enabled: true),
        ),
      ),
    ),
    actions: <Widget>[
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  ),
);

/// The fields of [showMetaEditor].
class MetaCard extends StatefulWidget {
  const MetaCard({
    super.key,
    required this.library,
    required this.id,
    required this.enabled,
  });
  final PresetLibrary library;
  final int id;
  final bool enabled;

  @override
  State<MetaCard> createState() => _MetaCardState();
}

class _MetaCardState extends State<MetaCard> {
  late final TextEditingController _name = TextEditingController(
    text: _meta.name,
  );
  late final TextEditingController _description = TextEditingController(
    text: _meta.description,
  );

  PresetMeta get _meta => widget.library.metas[widget.id];

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _edit(void Function(PresetMeta m) change) {
    change(_meta);
    widget.library.changed();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PresetMeta m = _meta;
    final bool on = widget.enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            final Widget name = TextField(
              controller: _name,
              enabled: on,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'A short name for this sound',
              ),
              onChanged: (String v) => _edit((PresetMeta m) => m.name = v),
            );
            final Widget stars = StarRating(
              rating: m.rating,
              onChanged: on
                  ? (int r) => _edit((PresetMeta m) => m.rating = r)
                  : null,
            );
            // Stars go under the name where both would not fit.
            return box.maxWidth < 520
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[name, stars],
                  )
                : Row(
                    children: <Widget>[
                      Expanded(child: name),
                      const SizedBox(width: 16),
                      stars,
                    ],
                  );
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _description,
          enabled: on,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Description',
            hintText: 'How it sounds and how it is built',
          ),
          onChanged: (String v) => _edit((PresetMeta m) => m.description = v),
        ),
        for (final MetaCategory c in MetaCategory.values)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 72,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(c.title, style: theme.textTheme.labelLarge),
                  ),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final String l in m.labels[c]!)
                        Chip(
                          label: Text(l),
                          visualDensity: VisualDensity.compact,
                        ),
                      ActionChip(
                        avatar: Icon(
                          m.labels[c]!.isEmpty
                              ? Icons.add
                              : Icons.edit_outlined,
                          size: 18,
                        ),
                        label: Text(
                          m.labels[c]!.isEmpty
                              ? 'Add ${c.singular.toLowerCase()}'
                              : 'Change',
                        ),
                        tooltip: 'Pick ${c.title.toLowerCase()}',
                        visualDensity: VisualDensity.compact,
                        onPressed: on
                            ? () => showLabelEditor(
                                context,
                                widget.library,
                                c,
                                meta: m,
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Five stars; tapping the current rating clears it.
class StarRating extends StatelessWidget {
  const StarRating({super.key, required this.rating, this.onChanged});
  final int rating;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final Color c = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int s = 1; s <= 5; s++)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: s == rating ? 'Clear the rating' : '$s of 5',
            onPressed: onChanged == null
                ? null
                : () => onChanged!(s == rating ? 0 : s),
            icon: Icon(
              s <= rating ? Icons.star : Icons.star_border,
              color: s <= rating ? c : null,
            ),
          ),
      ],
    );
  }
}

/// Adds and removes the labels offered for [c]; with [meta], also picks
/// which of them that preset has.
Future<void> showLabelEditor(
  BuildContext context,
  PresetLibrary library,
  MetaCategory c, {
  PresetMeta? meta,
}) => showDialog<void>(
  context: context,
  builder: (BuildContext context) {
    final TextEditingController add = TextEditingController();
    void submit() {
      final String l = add.text.trim();
      if (library.addLabel(c, l)) {
        meta?.labels[c]!.add(l);
        library.changed();
        add.clear();
      }
    }

    return AlertDialog(
      title: Text(c.title),
      content: SizedBox(
        width: 420,
        child: ListenableBuilder(
          listenable: library,
          builder: (BuildContext context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: add,
                      autofocus: meta == null,
                      decoration: InputDecoration(
                        labelText: 'New ${c.singular.toLowerCase()}',
                      ),
                      onSubmitted: (_) => submit(),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add',
                    onPressed: submit,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final String l in library.offered(c))
                        InputChip(
                          label: Text(l),
                          selected: meta?.labels[c]!.contains(l) ?? false,
                          onSelected: meta == null
                              ? null
                              : (bool v) {
                                  v
                                      ? meta.labels[c]!.add(l)
                                      : meta.labels[c]!.remove(l);
                                  library.changed();
                                },
                          deleteButtonTooltipMessage: 'Remove "$l"',
                          onDeleted: () => _remove(context, library, c, l),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  },
);

Future<void> _remove(
  BuildContext context,
  PresetLibrary library,
  MetaCategory c,
  String label,
) async {
  final int used = library.metas
      .where((PresetMeta m) => m.labels[c]!.contains(label))
      .length;
  if (used > 0) {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Remove "$label"?'),
        content: Text(
          used == 1
              ? '1 preset has it; it loses the ${c.singular.toLowerCase()}.'
              : '$used presets have it; they lose the '
                    '${c.singular.toLowerCase()}.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
  }
  library.removeLabel(c, label);
}

/// Faceted filter on the preset list; applies as it is changed.
Future<void> showMetaFilter(BuildContext context, PresetLibrary library) =>
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Filter presets'),
        content: SizedBox(
          width: 480,
          child: ListenableBuilder(
            listenable: library,
            builder: (BuildContext context, _) {
              final ThemeData theme = Theme.of(context);
              final int shown = <int>[
                for (int i = 0; i < library.metas.length; i++)
                  if (library.matches(i)) i,
              ].length;
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Any value within a group, every group at once. '
                      '$shown of ${library.metas.length} presets match.',
                      style: theme.textTheme.bodySmall,
                    ),
                    for (final MetaCategory c in MetaCategory.values)
                      if (library.offered(c).isNotEmpty) ...<Widget>[
                        const SizedBox(height: 16),
                        Text(c.title, style: theme.textTheme.labelLarge),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: <Widget>[
                            for (final String l in library.offered(c))
                              FilterChip(
                                label: Text(l),
                                selected: library.filter[c]!.contains(l),
                                onSelected: (bool v) =>
                                    library.setFilter(c, l, v),
                              ),
                          ],
                        ),
                      ],
                    const SizedBox(height: 16),
                    Text('Rating', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        for (int r = 0; r <= 5; r++)
                          ChoiceChip(
                            label: Text(
                              r == 0
                                  ? 'Any'
                                  : r == 5
                                  ? '5 stars'
                                  : '$r+ stars',
                            ),
                            selected: library.minRating == r,
                            onSelected: (_) => library.setMinRating(r),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: library.clearFilter,
            child: const Text('Clear'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
