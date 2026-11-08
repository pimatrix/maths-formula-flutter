// Basic smoke tests for the Maths Formula Sheet app.

import 'package:flutter_test/flutter_test.dart';

import 'package:maths_formula_sheet/main.dart';

void main() {
  testWidgets('App builds and shows its title', (WidgetTester tester) async {
    await tester.pumpWidget(const FormulaApp());
    await tester.pump();

    expect(find.text('Maths Formula Sheet'), findsWidgets);
  });

  testWidgets('Bottom navigation shows all five tabs',
      (WidgetTester tester) async {
    await tester.pumpWidget(const FormulaApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Browse'), findsOneWidget);
    expect(find.text('AI Tutor'), findsWidgets);
    expect(find.text('More'), findsOneWidget);
  });

  test('cleanBody converts formula HTML to readable text', () {
    final out = cleanBody(
        '<span class="lbl">Roots:</span> &nbsp; x = <span class="frac"><span class="t">−b ± √(b<sup>2</sup> − 4ac)</span><span class="b">2a</span></span>');
    expect(out, contains('Roots:'));
    expect(out, contains('(2a)'));
    expect(out, contains('b²'));
  });

  test('cleanBody keeps every superscript letter (the a^m bug)', () {
    final out = cleanBody('a<sup>m</sup> · a<sup>n</sup> = a<sup>m+n</sup>');
    expect(out, 'aᵐ · aⁿ = aᵐ⁺ⁿ');
  });

  test('formulaTextToPlain renders fractions, roots and powers', () {
    final out = formulaTextToPlain(r'\frac{-b \pm \sqrt{b^{2} - 4ac}}{2a}');
    expect(out, '(-b ± √(b² - 4ac))/(2a)');
  });

  test('formulaTextToPlain renders example-style caret powers', () {
    final out = formulaTextToPlain('2^2 x 2^3 = 2^(2+3) = 2^5 = 32');
    expect(out, '2² x 2³ = 2²⁺³ = 2⁵ = 32');
  });
}
