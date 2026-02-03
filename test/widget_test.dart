import 'package:flutter_test/flutter_test.dart';

import 'package:leggio/main.dart';

void main() {
  testWidgets('Leggio app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const LeggioApp());

    // Verify initial state shows "Aucun PDF sélectionné"
    expect(find.text('Aucun PDF sélectionné'), findsOneWidget);

    // Verify "Ouvrir PDF" button exists
    expect(find.text('Ouvrir PDF'), findsOneWidget);
  });
}
