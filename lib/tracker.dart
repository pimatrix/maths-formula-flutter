// Analytics tracker — sends pageview, formula_view, share and presence
// events to the backend's /api/track endpoint (stored in fs_events).
//
// What is collected is exactly what the Privacy Policy lists
// (yashx.xyz/privacy): pages and formulas viewed, time, device, browser,
// IP (added by the server), and battery level where the browser/device
// provides it. Admins are excluded on the server. A user who opts out —
// in Profile settings, or anonymously on this device — is never recorded:
// this client simply stops sending, and the server independently drops
// events from opted-out signed-in accounts.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'features.dart';
import 'tracker_meta.dart';

class Tracker {
  Tracker._();
  static final Tracker instance = Tracker._();

  String _visitorId = '';
  bool _started = false;
  bool _localOptOut = false;
  Timer? _heartbeat;
  Map<String, dynamic> _meta = {};

  bool get optedOut => _localOptOut || auth.analyticsOptOut;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    if (isTestEnv) return; // silent under flutter_test
    try {
      final prefs = await SharedPreferences.getInstance();
      _visitorId = prefs.getString('mm_visitor_id') ?? '';
      if (_visitorId.isEmpty) {
        _visitorId =
            'v-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1 << 32).toRadixString(16)}';
        await prefs.setString('mm_visitor_id', _visitorId);
      }
      _localOptOut = prefs.getBool('mm_analytics_optout') ?? false;
      _meta = await _collectMeta();
    } catch (_) {}
    await send('pageview', path: '/');
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 60), (_) async {
      _meta = await _collectMeta();
      send('presence', path: '/');
    });
  }

  /// Anonymous (signed-out) opt-out stored on this device. The Profile
  /// settings switch uses the account-level flag on the server; this one
  /// covers the not-logged-in case and takes effect immediately.
  Future<void> setLocalOptOut(bool value) async {
    _localOptOut = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('mm_analytics_optout', value);
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _collectMeta() async {
    final m = <String, dynamic>{};
    if (kIsWeb) {
      try {
        final web = await webMeta();
        if (web != null) m.addAll(web);
      } catch (_) {}
      return m;
    }
    // Native: build a UA-shaped string so the server's parser extracts
    // the same browser / OS / device / model fields as for web visits.
    try {
      final info = DeviceInfoPlugin();
      if (defaultTargetPlatform == TargetPlatform.android) {
        final a = await info.androidInfo;
        m['ua'] =
            'Mozilla/5.0 (Linux; Android ${a.version.release}; ${a.model}) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36 MathMitraApp';
        m['model'] = a.model;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final i = await info.iosInfo;
        m['ua'] =
            'Mozilla/5.0 (iPhone; CPU iPhone OS ${i.systemVersion.replaceAll('.', '_')} like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 MathMitraApp';
        m['model'] = i.model;
      }
    } catch (_) {}
    try {
      final battery = Battery();
      m['battery_level'] = await battery.batteryLevel;
      final state = await battery.batteryState;
      m['battery_charging'] =
          state == BatteryState.charging || state == BatteryState.full;
    } catch (_) {}
    try {
      m['language'] = PlatformDispatcher.instance.locale.toLanguageTag();
      m['timezone'] = DateTime.now().timeZoneName;
    } catch (_) {}
    return m;
  }

  Future<void> send(String type,
      {String? path, String? formulaName, String? category}) async {
    if (optedOut) return;
    try {
      final body = <String, dynamic>{
        'visitor_id': _visitorId,
        'type': type,
        if (path != null) 'path': path,
        if (formulaName != null) 'formula_name': formulaName,
        if (category != null) 'category': category,
        ..._meta,
      };
      if (auth.isLoggedIn) {
        body['user_id'] = auth.userId;
        body['user_email'] = auth.email;
      }
      await http
          .post(Uri.parse('$kApiBase/api/track'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  void formulaView(String name, String category) =>
      send('formula_view', path: '/formula', formulaName: name, category: category);

  void share(String name) => send('share', formulaName: name);
}
