// Basic smoke tests for the Maths Formula Sheet app.

import 'package:flutter_test/flutter_test.dart';

import 'package:maths_formula_sheet/main.dart';

void main() {
  testWidgets('App builds and shows its title', (WidgetTester tester) async {
    await tester.pumpWidget(const FormulaApp());
    // The slim bar (with the app name) appears once the bundled data loads;
    // asset IO needs real async time inside a widget test.
    await tester
        .runAsync(() => Future.delayed(const Duration(milliseconds: 900)));
    await tester.pump();

    expect(find.text('MathMitra'), findsWidgets);
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

  test('displayText handles AI text that mixes < signs and caret powers', () {
    final out = displayText(r'D = b^{2} - 4ac, and D < 0 means no real roots');
    expect(out, contains('b²'));
    expect(out, contains('D < 0'));
    expect(out, isNot(contains('^{')));
  });

  test('displayText renders the standard-values table as text lines', () {
    final out = displayText(
        '<table class="vals">\n<tr><th>θ</th><th>0° (0)</th><th>30° (π/6)</th></tr>\n<tr><th>sin θ</th><td>0</td><td>1/2</td></tr></table>');
    expect(out, isNot(contains('<')));
    expect(out, contains('sin θ'));
    expect(out, contains('1/2'));
    expect(out.split('\n').length, greaterThanOrEqualTo(2));
  });


  test('structuredLines splits numbered rule points onto separate lines', () {
    final lines = structuredLines(
        '(1) Factor the denominator and find the singular points. (2) Points outside contribute 0. (3) For each inside point, apply the formula (n = 0). (4) Add the contributions.');
    expect(lines.length, 4);
    expect(lines.map((l) => l.marker).toList(), ['1', '2', '3', '4']);
    expect(lines[1].text, 'Points outside contribute 0.');
  });

  test('structuredLines bullets a newline-separated properties list', () {
    final lines = structuredLines(
        'Interchanging two rows changes the sign.\nTwo identical rows give value = 0.\nMultiplying one row by k multiplies the determinant by k.\nAdding a multiple of one row to another does not change the value.');
    expect(lines.length, 4);
    expect(lines.every((l) => l.marker == '•'), isTrue);
  });

  test('structuredLines splits the pipe-separated determinant cluster', () {
    final lines =
        structuredLines('|Aᵀ| = |A| | |AB| = |A|·|B| | Determinant of a triangular matrix = product of its diagonal entries.');
    expect(lines.length, 3);
    expect(lines[1].text, '|AB| = |A|·|B|');
  });

  test('structuredLines splits long prose into sentence bullets', () {
    final lines = structuredLines(
        'A logarithm is the inverse of a power: if a^x = m, then x = log_a m. The natural log uses the base e. Logarithms turn multiplication into addition and powers into multiplication. That is why they simplify heavy calculations in exams.');
    expect(lines.length, greaterThanOrEqualTo(3));
  });

  test('stripTitlePrefix removes a repeated title but never a formula start',
      () {
    expect(
        stripTitlePrefix('PROPERTIES — Determinants (frequently asked):\nInterchanging two rows changes the sign.',
            ['PROPERTIES — Determinants (frequently asked)']),
        startsWith('Interchanging'));
    expect(stripTitlePrefix('log(m/n) = log m − log n', ['log']),
        'log(m/n) = log m − log n');
    expect(stripTitlePrefix('AP: aₙ = a + (n−1)d', ['AP']),
        'aₙ = a + (n−1)d');
  });

  test('skeleton flattens typed and rendered formulas to the same string',
      () {
    expect(skeleton('(a+b)²'), '(a+b)2');
    expect(skeleton('(a+b)^2'), '(a+b)2');
    expect(skeleton('(a + b)² = a² + 2ab'), contains('(a+b)2'));
  });

  test('cleanBody keeps an HTML table readable as rows', () {
    const html = '<table class="vals">\n'
        '<tr><th>θ</th><th>0° (0)</th><th>30° (π/6)</th></tr>\n'
        '<tr><th>sin θ</th><td>0</td><td>1/2</td></tr>\n'
        '</table>';
    final out = cleanBody(html);
    expect(out.split('\n').length, 2);
    expect(out.split('\n')[0], 'θ · 0° (0) · 30° (π/6)');
    expect(out.split('\n')[1], 'sin θ · 0 · 1/2');
  });

  test('parseTable extracts rows and cells', () {
    const html = '<table><tr><th>θ</th><th>0° (0)</th></tr>'
        '<tr><th>sin θ</th><td>0</td></tr></table>';
    final rows = parseTable(html);
    expect(rows.length, 2);
    expect(rows[0], ['θ', '0° (0)']);
    expect(rows[1], ['sin θ', '0']);
    expect(parseTable('plain text, no table'), isEmpty);
  });
}
