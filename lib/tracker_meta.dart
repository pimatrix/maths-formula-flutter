// Platform metadata for analytics events: the real implementation runs
// only in the browser; native builds return null and the tracker fills
// the fields from device_info_plus / battery_plus instead.
export 'tracker_meta_stub.dart'
    if (dart.library.html) 'tracker_meta_web.dart';
