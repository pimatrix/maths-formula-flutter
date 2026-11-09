// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

/// Web: trigger a normal browser download of the PDF file.
Future<void> deliverPdf(Uint8List bytes, String filename) async {
  final blob = html.Blob([bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  // Revoking too early can cancel the download in some browsers.
  Timer(const Duration(seconds: 10), () => html.Url.revokeObjectUrl(url));
}
