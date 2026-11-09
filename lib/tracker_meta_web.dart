import 'dart:html' as html;
import 'dart:js_interop';

@JS('navigator.getBattery')
external JSPromise<JSObject> _batteryPromise();

extension type _Battery(JSObject _) implements JSObject {
  external double get level;
  external bool get charging;
}

/// Browser metadata for one analytics event: user agent, screen size,
/// language, timezone — plus battery level where the browser provides it
/// (Chrome/Android; Safari and Firefox do not, the fields stay absent).
Future<Map<String, dynamic>?> webMeta() async {
  final nav = html.window.navigator;
  final m = <String, dynamic>{
    'ua': nav.userAgent,
    'language': nav.language,
  };
  try {
    final scr = html.window.screen;
    if (scr != null) m['screen'] = '${scr.width}x${scr.height}';
  } catch (_) {}
  try {
    m['timezone'] = DateTime.now().timeZoneName;
  } catch (_) {}
  try {
    final b = _Battery(await _batteryPromise().toDart);
    m['battery_level'] = (b.level * 100).round();
    m['battery_charging'] = b.charging;
  } catch (_) {}
  return m;
}

/// The tracker is never silenced in a real browser.
bool get isTestEnv => false;
