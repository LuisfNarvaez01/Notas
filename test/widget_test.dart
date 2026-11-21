import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hilva/ui/theme.dart';

void main() {
  testWidgets('Hilva identity renders in both themes', (tester) async {
    for (final dark in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: hilvaTheme(dark),
          home: const Scaffold(body: HilvaMark()),
        ),
      );
      expect(find.byType(HilvaMark), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
