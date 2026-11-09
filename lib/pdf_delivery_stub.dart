import 'dart:typed_data';

import 'package:printing/printing.dart';

/// Non-web platforms: hand the PDF to the system share sheet.
Future<void> deliverPdf(Uint8List bytes, String filename) =>
    Printing.sharePdf(bytes: bytes, filename: filename);
