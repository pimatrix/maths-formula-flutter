// Basic smoke tests for the Maths Formula Sheet app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maths_formula_sheet/main.dart';

void main() {
  testWidgets('App builds and shows its title', (WidgetTester tester) async {
    await tester.pumpWidget(const FormulaApp());
    await tester.pump();

    expect(find.text('Maths Formula Sheet'), findsOneWidget);
  });

  testWidgets('Drawer shows the feature menu', (WidgetTester tester) async {
    await tester.pumpWidget(const FormulaApp());
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Add Formula'), findsWidgets);
    expect(find.text('Add Class / Category'), findsOneWidget);
    expect(find.text('Login / Sign Up'), findsOneWidget);
  });

  test('cleanBody converts formula HTML to readable text', () {
    final out = cleanBody(
        '<span class="lbl">Roots:</span> &nbsp; x = <span class="frac"><span class="t">−b ± √(b<sup>2</sup> − 4ac)</span><span class="b">2a</span></span>');
    expect(out, contains('Roots:'));
    expect(out, contains('(2a)'));
    expect(out, contains('b²'));
  });
}
