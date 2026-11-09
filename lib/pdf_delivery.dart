// Platform PDF delivery: a real file download in the browser,
// the system share sheet everywhere else.
export 'pdf_delivery_stub.dart'
    if (dart.library.html) 'pdf_delivery_web.dart';
