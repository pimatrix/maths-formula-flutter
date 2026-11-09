import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'main.dart';
import 'pdf_delivery.dart';

const List<String> _pdfMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

/// Builds a well-structured PDF of every formula — grouped by class and
/// section, each entry with its meaning, symbols and solved example — and
/// opens the share / download sheet. Fonts: Inter for text, Space Grotesk
/// for names, DejaVu Sans as fallback for maths glyphs Inter lacks
/// (∮, ∈, ⊂, ∠…), so no symbol turns into a blank box.
Future<void> exportAllFormulasPdf(
    SheetData data, Map<String, dynamic> details) async {
  final inter =
      pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-400.ttf'));
  final interBold =
      pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-700.ttf'));
  final grotesk = pw.Font.ttf(
      await rootBundle.load('assets/fonts/SpaceGrotesk-700.ttf'));
  final dejavu =
      pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
  final theme = pw.ThemeData.withFont(
      base: inter, bold: interBold, fontFallback: [dejavu]);

  final dark = PdfColor.fromHex('#1E1B4B');
  final indigo = PdfColor.fromHex('#4338CA');
  final grey = PdfColor.fromHex('#6B7280');
  final boxBg = PdfColor.fromHex('#EEF2FF');
  final greenBg = PdfColor.fromHex('#F4FBF4');
  final greenDark = PdfColor.fromHex('#22702C');

  String detailsOf(EntryItem e, String key) {
    if (!e.userAdded) {
      final d = details[e.id];
      if (d is Map) return (d[key] as String?) ?? '';
    }
    return key == 'about'
        ? e.about
        : key == 'symbols'
            ? e.symbols
            : e.example;
  }

  final widgets = <pw.Widget>[];
  final now = DateTime.now();
  widgets.add(pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text('MathMitra',
          style: pw.TextStyle(font: grotesk, fontSize: 30, color: indigo)),
      pw.SizedBox(height: 4),
      pw.Text('Complete Maths Formula Book',
          style: pw.TextStyle(font: interBold, fontSize: 15, color: dark)),
      pw.SizedBox(height: 4),
      pw.Text(
          '${data.entries.length} formulas with meaning, symbols and solved examples · ${now.day} ${_pdfMonths[now.month - 1]} ${now.year}',
          style: pw.TextStyle(font: inter, fontSize: 10.5, color: grey)),
      pw.SizedBox(height: 10),
      pw.Divider(color: indigo, thickness: 1.4),
      pw.SizedBox(height: 6),
    ],
  ));

  final groups = <String>[];
  for (final c in data.categories) {
    if (!groups.contains(c.group)) groups.add(c.group);
  }
  for (final g in groups) {
    widgets.add(pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14, bottom: 2),
      child: pw.Text(g.toUpperCase(),
          style: pw.TextStyle(font: grotesk, fontSize: 17, color: dark)),
    ));
    for (final cat in data.categories.where((c) => c.group == g)) {
      final catEntries =
          data.entries.where((e) => e.category == cat.slug).toList();
      if (catEntries.isEmpty) continue;
      widgets.add(pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
        child: pw.Text(cat.title,
            style: pw.TextStyle(font: interBold, fontSize: 13.5, color: indigo)),
      ));
      final sections = <String>[];
      for (final e in catEntries) {
        if (!sections.contains(e.section)) sections.add(e.section);
      }
      for (final sec in sections) {
        if (sec.isNotEmpty) {
          widgets.add(pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6, bottom: 3),
            child: pw.Text(sec,
                style: pw.TextStyle(font: interBold, fontSize: 11, color: grey)),
          ));
        }
        for (final e in catEntries.where((x) => x.section == sec)) {
          final name = displayName(e, details);
          final body =
              stripTitlePrefix(displayText(e.body), [displayText(e.name), name]);
          final about = detailsOf(e, 'about');
          final symbols = detailsOf(e, 'symbols');
          final example = detailsOf(e, 'example');
          widgets.add(pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 9),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(name,
                    style: pw.TextStyle(font: grotesk, fontSize: 12, color: dark)),
                pw.SizedBox(height: 3),
                if (e.kind == 'formula')
                  pw.Container(
                    width: double.infinity,
                    color: boxBg,
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    child: pw.Text(body,
                        style: pw.TextStyle(
                            font: interBold, fontSize: 11, color: dark)),
                  )
                else
                  pw.Text(structuredPlain(body),
                      style: pw.TextStyle(
                          font: inter, fontSize: 10.5, height: 1.45)),
                if (about.isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.RichText(
                      text: pw.TextSpan(children: [
                    pw.TextSpan(
                        text: 'Meaning: ',
                        style: pw.TextStyle(
                            font: interBold, fontSize: 10, color: indigo)),
                    pw.TextSpan(
                        text: structuredPlain(displayText(about)),
                        style: pw.TextStyle(
                            font: inter, fontSize: 10, height: 1.4)),
                  ])),
                ],
                if (symbols.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.RichText(
                      text: pw.TextSpan(children: [
                    pw.TextSpan(
                        text: 'Symbols: ',
                        style: pw.TextStyle(
                            font: interBold, fontSize: 10, color: indigo)),
                    pw.TextSpan(
                        text: displayText(symbols).replaceAll('\n', ' · '),
                        style: pw.TextStyle(
                            font: inter, fontSize: 10, height: 1.4)),
                  ])),
                ],
                if (example.isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.Container(
                    width: double.infinity,
                    color: greenBg,
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    child: pw.RichText(
                        text: pw.TextSpan(children: [
                      pw.TextSpan(
                          text: 'Example: ',
                          style: pw.TextStyle(
                              font: interBold, fontSize: 10, color: greenDark)),
                      pw.TextSpan(
                          text: structuredPlain(displayText(example)),
                          style: pw.TextStyle(
                              font: inter, fontSize: 10, height: 1.4)),
                    ])),
                  ),
                ],
              ],
            ),
          ));
        }
      }
    }
  }

  final doc = pw.Document(
      title: 'MathMitra — Complete Formula Book', author: 'MathMitra');
  doc.addPage(pw.MultiPage(
    theme: theme,
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 38, 36, 46),
    footer: (ctx) => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('MathMitra · yashx.xyz/MathMitra',
            style: pw.TextStyle(font: inter, fontSize: 8, color: grey)),
        pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: pw.TextStyle(font: inter, fontSize: 8, color: grey)),
      ],
    ),
    build: (ctx) => widgets,
  ));
  final bytes = await doc.save();
  await deliverPdf(bytes, 'MathMitra-Formulas.pdf');
}
