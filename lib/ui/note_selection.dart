import 'package:flutter/material.dart';

import '../data/store.dart';

/// Plain note text only. No IDs, dates, tags, JSON or attachment paths.
String notesPlainText(Iterable<Entry> notes) => notes
    .map(
      (note) => note.body.trim().isEmpty ? note.title.trim() : note.body.trim(),
    )
    .where((text) => text.isNotEmpty)
    .join('\n\n');

class NoteSelectionBar extends StatelessWidget {
  final List<Entry> notes;
  final Set<String> selected;
  final bool selecting;
  final VoidCallback onToggleMode, onSelectAll;
  final ValueChanged<List<Entry>> onCopy;
  const NoteSelectionBar({
    super.key,
    required this.notes,
    required this.selected,
    required this.selecting,
    required this.onToggleMode,
    required this.onSelectAll,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final chosen = notes.where((n) => selected.contains(n.id)).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton.icon(
            onPressed: onToggleMode,
            icon: Icon(selecting ? Icons.close : Icons.checklist),
            label: Text(selecting ? 'Cancelar' : 'Seleccionar'),
          ),
          if (selecting)
            TextButton(
              onPressed: notes.isEmpty ? null : onSelectAll,
              child: Text(
                chosen.length == notes.length
                    ? 'Desmarcar todas'
                    : 'Seleccionar todas',
              ),
            ),
          OutlinedButton.icon(
            onPressed: (selecting ? chosen : notes).isEmpty
                ? null
                : () => onCopy(selecting ? chosen : notes),
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: Text(
              selecting ? 'Copiar (${chosen.length})' : 'Copiar todas',
            ),
          ),
          if (!selecting)
            Text(
              'Notas visibles · solo texto',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}
