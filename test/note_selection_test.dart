import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hilva/data/store.dart';
import 'package:hilva/ui/note_selection.dart';
import 'package:hilva/ui/theme.dart';

Entry note(String id, String body) => Entry(
  id: id,
  kind: 'note',
  revision: 1,
  baseRevision: 0,
  updatedAt: 'date',
  payload: {
    'title': 'Title $id',
    'body': body,
    'tags': ['private-tag'],
    'attachments': ['private-path'],
    'prompt': 'private-prompt',
  },
);

void main() {
  test(
    'copies body only with blank line separators and title for empty notes',
    () {
      expect(
        notesPlainText([
          note('a', ' Uno\nDos '),
          note('b', ''),
          note('c', 'Tres'),
        ]),
        'Uno\nDos\n\nTitle b\n\nTres',
      );
    },
  );
  testWidgets(
    'copy all and multi-selection use only visible notes in display order',
    (tester) async {
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      final font = FontLoader('Manrope')
        ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
      await font.load();
      final notes = [note('a', 'Uno'), note('b', 'Dos')];
      final selected = <String>{'hidden'};
      var selecting = false;
      var copied = <Entry>[];
      tester.view.physicalSize = const Size(390, 500);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: hilvaTheme(false),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => NoteSelectionBar(
                notes: notes,
                selected: selected,
                selecting: selecting,
                onToggleMode: () => setState(() => selecting = !selecting),
                onSelectAll: () => setState(() {
                  if (notes.every((n) => selected.contains(n.id))) {
                    selected.clear();
                  } else {
                    selected.addAll(notes.map((n) => n.id));
                  }
                }),
                onCopy: (value) => copied = value,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Copiar todas'));
      expect(copied.map((n) => n.id), ['a', 'b']);
      await tester.tap(find.text('Seleccionar'));
      await tester.pump();
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      await tester.tap(find.text('Seleccionar todas'));
      await tester.pump();
      await tester.tap(find.text('Copiar (2)'));
      expect(copied.map((n) => n.id), ['a', 'b']);
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/note-selection-390.png'),
      );
      await tester.tap(find.text('Desmarcar todas'));
      await tester.pump();
      expect(find.text('Copiar (0)'), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
