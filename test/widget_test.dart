import 'package:flutter_test/flutter_test.dart';

import 'package:pdf_rotate/main.dart';

void main() {
  testWidgets('PDF Rotate app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PdfRotateApp());

    // Verify initial state shows "Aucun PDF sélectionné"
    expect(find.text('Aucun PDF sélectionné'), findsOneWidget);

    // Verify "Ouvrir PDF" button exists
    expect(find.text('Ouvrir PDF'), findsOneWidget);
  });
}
