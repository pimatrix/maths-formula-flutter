// Feature layer: auth (Supabase Auth REST, same as the website), API client,
// and the screens for login/signup, profile, adding content, My Formulas and
// the Admin Dashboard. Talks to the SAME backend as the website, so data and
// accounts are shared between the site and the app.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'main.dart';
import 'tracker.dart';

const String kApiBase = 'https://yashx.xyz/MathMitra';
const String kSbUrl = 'https://olekfyhjyymzglnwsaln.supabase.co';
const String kSbAnon =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9sZWtmeWhqeXltemdsbndzYWxuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQwOTMwMjUsImV4cCI6MjEwOTY2OTAyNX0.NTuobtB6Kfgo_XQ2PQHjCfuoxVMXafKQpwMmkUCMwF8';

const List<String> kStudyLevels = [
  'Class 6', 'Class 7', 'Class 8', 'Class 9', 'Class 10', 'Class 11',
  'Class 12', 'College Year 1', 'College Year 2', 'College Year 3',
  'College Year 4', 'College Year 5', 'Other',
];

// ---------------------------------------------------------------- auth

class AuthService extends ChangeNotifier {
  Map<String, dynamic>? _session;
  String role = 'user';
  String institution = '';
  String studyLevel = '';
  bool analyticsOptOut = false;
  String termsAcceptedAt = '';
  bool loaded = false;

  void setAnalyticsOptOut(bool value) {
    analyticsOptOut = value;
    notifyListeners();
  }

  bool get isLoggedIn => _session != null;
  bool get isAdmin => role == 'admin';
  String get email => (_session?['user']?['email'] as String?) ?? '';
  String get userId => (_session?['user']?['id'] as String?) ?? '';
  String get name => (_session?['user']?['name'] as String?) ?? '';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('fs_session_v1');
      if (raw != null) {
        _session = jsonDecode(raw) as Map<String, dynamic>;
      }
    } catch (_) {}
    loaded = true;
    notifyListeners();
    if (_session != null) await fetchMe();
    if (_session != null) library.refresh();
  }

  Future<void> _save(Map<String, dynamic> d) async {
    _session = {
      'access_token': d['access_token'],
      'refresh_token': d['refresh_token'],
      'expires_at':
          DateTime.now().millisecondsSinceEpoch + ((d['expires_in'] as num?)?.toInt() ?? 3600) * 1000,
      'user': {
        'id': d['user']['id'],
        'email': d['user']['email'],
        'name': (d['user']['user_metadata']?['name'] as String?) ?? '',
      },
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fs_session_v1', jsonEncode(_session));
    notifyListeners();
  }

  Future<void> _clear() async {
    _session = null;
    role = 'user';
    institution = '';
    studyLevel = '';
    analyticsOptOut = false;
    termsAcceptedAt = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('fs_session_v1');
    notifyListeners();
  }

  Future<String?> login(String email, String password) async {
    try {
      final r = await http.post(
        Uri.parse('$kSbUrl/auth/v1/token?grant_type=password'),
        headers: {'apikey': kSbAnon, 'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode != 200) {
        return (d['error_description'] ?? d['error'] ?? 'Login failed. Check email and password.').toString();
      }
      await _save(d);
      await fetchMe();
      library.refresh();
      return null;
    } catch (_) {
      return 'Network error. Please try again.';
    }
  }

  Future<String?> signup({
    required String name,
    required String email,
    required String password,
    required String institution,
    required String studyLevel,
  }) async {
    try {
      final r = await http.post(
        Uri.parse('$kSbUrl/auth/v1/signup'),
        headers: {'apikey': kSbAnon, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'data': {
            'name': name,
            'institution': institution,
            'study_level': studyLevel,
            'terms_accepted_at': DateTime.now().toUtc().toIso8601String(),
            'terms_version': '2026-11-09',
          },
        }),
      );
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode != 200 && r.statusCode != 201) {
        return (d['error_description'] ?? d['msg'] ?? d['error'] ?? 'Signup failed.').toString();
      }
      if (d['access_token'] != null) {
        await _save(d);
        await fetchMe();
        library.refresh();
      }
      return null;
    } catch (_) {
      return 'Network error. Please try again.';
    }
  }

  Future<void> logout() async {
    final token = _session?['access_token'];
    if (token != null) {
      try {
        await http.post(
          Uri.parse('$kSbUrl/auth/v1/logout'),
          headers: {'apikey': kSbAnon, 'Authorization': 'Bearer $token'},
        );
      } catch (_) {}
    }
    await _clear();
    await library.onSignedOut();
  }

  Future<String?> _validToken() async {
    if (_session == null) return null;
    final exp = (_session!['expires_at'] as num?)?.toInt() ?? 0;
    if (exp - DateTime.now().millisecondsSinceEpoch > 60000) {
      return _session!['access_token'] as String;
    }
    final rt = _session!['refresh_token'];
    if (rt == null) return _session!['access_token'] as String?;
    try {
      final r = await http.post(
        Uri.parse('$kSbUrl/auth/v1/token?grant_type=refresh_token'),
        headers: {'apikey': kSbAnon, 'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': rt}),
      );
      if (r.statusCode != 200) {
        await _clear();
        return null;
      }
      await _save(jsonDecode(r.body) as Map<String, dynamic>);
      return _session!['access_token'] as String;
    } catch (_) {
      return _session?['access_token'] as String?;
    }
  }

  Future<void> fetchMe() async {
    final token = await _validToken();
    if (token == null) return;
    try {
      final r = await http.get(
        Uri.parse('$kApiBase/api/me'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (r.statusCode != 200) return;
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      role = (d['role'] as String?) ?? 'user';
      analyticsOptOut = d['analytics_opt_out'] == true;
      termsAcceptedAt = (d['terms_accepted_at'] as String?) ?? '';
      final p = d['profile'] as Map<String, dynamic>?;
      institution = (p?['institution'] as String?) ?? '';
      studyLevel = (p?['study_level'] as String?) ?? '';
      notifyListeners();
    } catch (_) {}
  }

  /// Authenticated call to the site's API. Returns the response.
  Future<http.Response> api(String path,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    final token = await _validToken();
    final headers = {'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    final uri = Uri.parse('$kApiBase$path');
    final payload = body == null ? null : jsonEncode(body);
    switch (method) {
      case 'POST':
        return http.post(uri, headers: headers, body: payload);
      case 'PUT':
        return http.put(uri, headers: headers, body: payload);
      case 'DELETE':
        return http.delete(uri, headers: headers, body: payload);
      default:
        return http.get(uri, headers: headers);
    }
  }
}

final AuthService auth = AuthService();

String apiError(http.Response r) {
  try {
    final d = jsonDecode(r.body) as Map<String, dynamic>;
    return (d['error'] ?? 'Something went wrong (${r.statusCode}).').toString();
  } catch (_) {
    return 'Something went wrong (${r.statusCode}).';
  }
}

void showMsg(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

/// Opens a web page (Terms, Privacy Policy, the portfolio) in the browser.
Future<void> openLink(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

InputDecoration fieldDeco(String label, {String? hint, IconData? icon}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: icon == null ? null : Icon(icon),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );
}

AppBar featureBar(String title) {
  return AppBar(
    backgroundColor: kPrimaryDark,
    flexibleSpace: Container(decoration: kBarDecoration),
    foregroundColor: Colors.white,
    title: Text(title, style: const TextStyle(fontSize: 17)),
  );
}

// ---------------------------------------------------------------- auth page

class AuthPage extends StatefulWidget {
  final String note;
  const AuthPage({super.key, this.note = ''});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool _signup = false;
  bool _busy = false;
  String _error = '';
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _institution = TextEditingController();
  String _level = 'College Year 1';
  bool _termsOk = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _institution.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter both email and password.');
      return;
    }
    if (_signup) {
      if (_name.text.trim().isEmpty) {
        setState(() => _error = 'Please enter your name.');
        return;
      }
      if (password.length < 6) {
        setState(() => _error = 'Password must be at least 6 characters.');
        return;
      }
      if (password != _confirm.text) {
        setState(() => _error = 'Password and Confirm Password do not match.');
        return;
      }
      if (!_termsOk) {
        setState(() => _error =
            'Please accept the Terms & Conditions and Privacy Policy to create your account.');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    final err = _signup
        ? await auth.signup(
            name: _name.text.trim(),
            email: email,
            password: password,
            institution: _institution.text.trim(),
            studyLevel: _level,
          )
        : await auth.login(email, password);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      setState(() => _error = err);
    } else if (!auth.isLoggedIn) {
      showMsg(context, 'Account created. Please log in from the Login tab.');
      setState(() => _signup = false);
    } else {
      showMsg(context, _signup ? 'Account created — welcome!' : 'Logged in — welcome back!');
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: featureBar(_signup ? 'Create Account' : 'Login'),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          if (widget.note.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF2E2308)
                    : const Color(0xFFFFF7E6),
                border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF6B5518)
                        : const Color(0xFFF0D9A8)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(widget.note,
                  style: const TextStyle(fontSize: 13.5, height: 1.45)),
            ),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text('Login'),
                  selected: !_signup,
                  onSelected: (_) => setState(() => _signup = false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: const Text('Sign Up'),
                  selected: _signup,
                  onSelected: (_) => setState(() => _signup = true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_signup) ...[
            TextField(
              controller: _name,
              decoration: fieldDeco('Full Name', icon: Icons.person_outline),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: fieldDeco('Email', icon: Icons.mail_outline),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: fieldDeco('Password', icon: Icons.lock_outline),
          ),
          if (_signup) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              obscureText: true,
              decoration:
                  fieldDeco('Confirm Password', icon: Icons.lock_outline),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _institution,
              decoration: fieldDeco('School / College name',
                  hint: 'Medicaps University', icon: Icons.school_outlined),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _level,
              decoration: fieldDeco('Class / Year'),
              items: kStudyLevels
                  .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                  .toList(),
              onChanged: (v) => setState(() => _level = v ?? _level),
            ),
          ],
          if (_signup) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Checkbox(
                  value: _termsOk,
                  onChanged: (v) => setState(() => _termsOk = v ?? false),
                ),
                const Expanded(
                  child: Text(
                    'I agree to the Terms & Conditions and the Privacy Policy.',
                    style: TextStyle(fontSize: 13.5),
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 2,
              children: [
                TextButton(
                  onPressed: () => openLink('https://yashx.xyz/terms'),
                  child: const Text('Read Terms & Conditions'),
                ),
                TextButton(
                  onPressed: () => openLink('https://yashx.xyz/privacy'),
                  child: const Text('Read Privacy Policy'),
                ),
              ],
            ),
          ],
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_error,
                style: const TextStyle(color: Colors.red, fontSize: 13.5)),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: kPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(_signup ? 'Create Account' : 'Login'),
          ),
          const SizedBox(height: 10),
          Text(
            'One account for the app and the website — sign in anywhere with the same email.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: subtleColor(context)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- profile page

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _institution = TextEditingController(text: auth.institution);
  String _level = auth.studyLevel.isNotEmpty ? auth.studyLevel : 'College Year 1';
  bool _busy = false;

  @override
  void dispose() {
    _institution.dispose();
    super.dispose();
  }

  Future<void> _toggleAnalytics(bool analyticsOn) async {
    setState(() => _busy = true);
    final r = await auth.api('/api/me',
        method: 'PUT', body: {'analytics_opt_out': !analyticsOn});
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.statusCode == 200) {
      auth.setAnalyticsOptOut(!analyticsOn);
      await Tracker.instance.setLocalOptOut(!analyticsOn);
      showMsg(
          context,
          analyticsOn
              ? 'Analytics is on. Thank you for helping improve MathMitra.'
              : 'Analytics is off — collection for your account has stopped.');
    } else {
      showMsg(context, apiError(r));
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
            'This permanently deletes your MathMitra account, the formulas you added and your analytics data. You will be logged out. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final r = await auth.api('/api/me', method: 'DELETE');
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.statusCode == 200) {
      showMsg(context, 'Your account has been deleted.');
      await auth.logout();
      if (mounted) Navigator.of(context).pop();
    } else {
      showMsg(context, apiError(r));
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final r = await auth.api('/api/me', method: 'PUT', body: {
      'institution': _institution.text.trim(),
      'study_level': _level,
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.statusCode == 200) {
      auth.institution = _institution.text.trim();
      auth.studyLevel = _level;
      showMsg(context, 'Details saved.');
    } else {
      showMsg(context, apiError(r));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: featureBar('My Profile'),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: kPrimary,
              child: Text(
                (auth.name.isNotEmpty ? auth.name : auth.email)
                    .substring(0, 1)
                    .toUpperCase(),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(auth.name.isEmpty ? 'Student' : auth.name,
                      style: const TextStyle(
                          fontSize: 16.5, fontWeight: FontWeight.w700)),
                  Text(auth.email,
                      style: TextStyle(
                          fontSize: 13, color: subtleColor(context))),
                  Text(auth.isAdmin ? 'Role: Admin' : 'Role: Student',
                      style: TextStyle(
                          fontSize: 13,
                          color: auth.isAdmin ? kPrimary : subtleColor(context),
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 20),
          TextField(
            controller: _institution,
            decoration: fieldDeco('School / College name',
                icon: Icons.school_outlined),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: kStudyLevels.contains(_level) ? _level : 'Other',
            decoration: fieldDeco('Class / Year'),
            items: kStudyLevels
                .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                .toList(),
            onChanged: (v) => setState(() => _level = v ?? _level),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(backgroundColor: kPrimary),
            child: const Text('Save Details'),
          ),
          const Divider(height: 38),
          const Text('Privacy & Account',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Usage analytics'),
            subtitle: const Text(
                'Helps improve MathMitra. What is collected is listed in the Privacy Policy — turn this off and collection for your account stops.'),
            value: !auth.analyticsOptOut,
            onChanged: _busy ? null : _toggleAnalytics,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terms & Conditions'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => openLink('https://yashx.xyz/terms'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => openLink('https://yashx.xyz/privacy'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _deleteAccount,
            icon: const Icon(Icons.delete_forever_outlined, size: 18),
            label: const Text('Delete My Account'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Deleting your account permanently removes your account, the formulas you added and your analytics data. This cannot be undone.',
            style: TextStyle(fontSize: 12, color: subtleColor(context)),
          ),
          const SizedBox(height: 26),
          OutlinedButton.icon(
            onPressed: () async {
              await auth.logout();
              if (context.mounted) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Logout'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- formula form (+ AI scan)

class FormulaFormPage extends StatefulWidget {
  final List<CategoryItem> categories;
  final EntryItem? existing;
  const FormulaFormPage({super.key, required this.categories, this.existing});

  @override
  State<FormulaFormPage> createState() => _FormulaFormPageState();
}

class _FormulaFormPageState extends State<FormulaFormPage> {
  late String _category;
  String _kind = 'formula';
  bool _busy = false;
  bool _scanning = false;
  String _error = '';
  final _name = TextEditingController();
  final _section = TextEditingController();
  final _formula = TextEditingController();
  final _about = TextEditingController();
  final _symbols = TextEditingController();
  final _example = TextEditingController();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _category = e?.category ??
        (widget.categories.isNotEmpty ? widget.categories.first.slug : '');
    if (e != null) {
      _kind = e.kind;
      _name.text = e.name;
      _section.text = e.section;
      _formula.text = e.body; // user entries store raw FormulaText — editable as-is
      _about.text = e.about;
      _symbols.text = e.symbols;
      _example.text = e.example;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _section.dispose();
    _formula.dispose();
    _about.dispose();
    _symbols.dispose();
    _example.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final picker = ImagePicker();
    final XFile? img = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (img == null) return;
    setState(() {
      _scanning = true;
      _error = '';
    });
    try {
      final bytes = await img.readAsBytes();
      var mime = img.mimeType ?? 'image/jpeg';
      if (!mime.startsWith('image/')) mime = 'image/jpeg';
      final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
      final r = await auth.api('/api/scan', method: 'POST', body: {'image': dataUrl});
      if (!mounted) return;
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        setState(() {
          if ((d['name'] as String? ?? '').isNotEmpty) _name.text = d['name'];
          if ((d['formula'] as String? ?? '').isNotEmpty) _formula.text = d['formula'];
          if ((d['section'] as String? ?? '').isNotEmpty) _section.text = d['section'];
          if ((d['about'] as String? ?? '').isNotEmpty) _about.text = d['about'];
          if ((d['symbols'] as String? ?? '').isNotEmpty) _symbols.text = d['symbols'];
          if ((d['example'] as String? ?? '').isNotEmpty) _example.text = d['example'];
        });
        showMsg(context, 'AI read the photo and filled the form. Please check everything, then Save.');
      } else {
        setState(() => _error = apiError(r));
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Photo scan failed. Please try again.');
    }
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _formula.text.trim().isEmpty) {
      setState(() => _error = 'Both Name and Formula are required.');
      return;
    }
    if (_category.isEmpty) {
      setState(() => _error = 'Please choose a category.');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    final payload = <String, dynamic>{
      'name': _name.text.trim(),
      'formula': _formula.text.trim(),
      'section': _section.text.trim(),
      'category': _category,
      'kind': _kind,
      'about': _about.text.trim(),
      'symbols': _symbols.text.trim(),
      'example': _example.text.trim(),
    };
    final isEdit = widget.existing != null;
    if (isEdit) payload['id'] = widget.existing!.id;
    final r = await auth.api('/api/formulas',
        method: isEdit ? 'PUT' : 'POST', body: payload);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.statusCode == 200) {
      showMsg(context, isEdit ? 'Formula updated.' : 'Formula added. Thank you!');
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = apiError(r));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: featureBar(isEdit ? 'Edit Formula' : 'Add Formula'),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          if (!isEdit)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF4338CA), Color(0xFF7C3AED)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Add a formula from a photo (AI)',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text(
                    'The easiest way: attach a photo of the formula from a book or notebook — AI fills in the name, formula, meaning, symbols and example for you.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _scanning ? null : _scan,
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: kPrimary),
                    icon: _scanning
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.photo_camera_outlined, size: 19),
                    label: Text(_scanning ? 'AI is reading…' : 'Choose Photo'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: widget.categories.any((c) => c.slug == _category)
                ? _category
                : null,
            decoration: fieldDeco('Class / Category'),
            items: widget.categories
                .map((c) => DropdownMenuItem(
                    value: c.slug,
                    child: Text(c.title, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _section,
            decoration: fieldDeco('Section / Topic',
                hint: 'Quadratic Equations'),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'formula', label: Text('Formula')),
              ButtonSegment(
                  value: 'theory', label: Text('Theory / Properties')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: fieldDeco('Name *', hint: 'Quadratic Formula'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _formula,
            maxLines: 3,
            decoration: fieldDeco('Formula * (FormulaText)',
                hint: r'x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _about,
            maxLines: 2,
            decoration: fieldDeco('What is this formula used for? (optional)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _symbols,
            maxLines: 3,
            decoration: fieldDeco('Meaning of symbols (optional)',
                hint: 'x = unknown value'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _example,
            maxLines: 3,
            decoration: fieldDeco('Example / use case (optional)'),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_error,
                style: const TextStyle(color: Colors.red, fontSize: 13.5)),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: kPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(isEdit ? 'Save Changes' : 'Add Formula'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- add category / class

class CategoryFormPage extends StatefulWidget {
  const CategoryFormPage({super.key});

  @override
  State<CategoryFormPage> createState() => _CategoryFormPageState();
}

class _CategoryFormPageState extends State<CategoryFormPage> {
  final _title = TextEditingController();
  final _group = TextEditingController();
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _title.dispose();
    _group.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a category name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    final r = await auth.api('/api/categories', method: 'POST', body: {
      'title': _title.text.trim(),
      'grp': _group.text.trim(),
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.statusCode == 200) {
      showMsg(context, 'New category / class created.');
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = apiError(r));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: featureBar('Add Class / Category'),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            'Create a new class or category — like "M2 — Engineering Mathematics" or "Class 10". Then you can add formulas to it.',
            style: TextStyle(fontSize: 13.5, color: subtleColor(context), height: 1.5),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            decoration: fieldDeco('Category / Class name *',
                hint: 'M2 — Engineering Mathematics'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _group,
            decoration: fieldDeco('Group (optional)',
                hint: 'Units, Basics, School'),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_error,
                style: const TextStyle(color: Colors.red, fontSize: 13.5)),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(
                backgroundColor: kPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Create'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- add syllabus

class SyllabusFormPage extends StatefulWidget {
  final List<CategoryItem> categories;
  const SyllabusFormPage({super.key, required this.categories});

  @override
  State<SyllabusFormPage> createState() => _SyllabusFormPageState();
}

class _SyllabusFormPageState extends State<SyllabusFormPage> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  String _category = '';
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'A title is required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final token = await auth._validToken();
      final req =
          http.MultipartRequest('POST', Uri.parse('$kApiBase/api/syllabus'));
      if (token != null) req.headers['Authorization'] = 'Bearer $token';
      req.fields['title'] = _title.text.trim();
      req.fields['category'] = _category;
      req.fields['content'] = _content.text.trim();
      final streamed = await req.send();
      final r = await http.Response.fromStream(streamed);
      if (!mounted) return;
      setState(() => _busy = false);
      if (r.statusCode == 200) {
        showMsg(context, 'Syllabus material added.');
        Navigator.of(context).pop(true);
      } else {
        setState(() => _error = apiError(r));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Network error. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: featureBar('Add Syllabus'),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: fieldDeco('Which class is this for?'),
            items: [
              const DropdownMenuItem(
                  value: '', child: Text('All Classes (Global)')),
              for (final c in widget.categories)
                DropdownMenuItem(
                    value: c.slug,
                    child: Text(c.title, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _category = v ?? ''),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            decoration: fieldDeco('Title *', hint: 'M1 Full Syllabus'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _content,
            maxLines: 10,
            decoration: fieldDeco('Syllabus text',
                hint: 'Write the units and topics…'),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_error,
                style: const TextStyle(color: Colors.red, fontSize: 13.5)),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(
                backgroundColor: kPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Add Syllabus'),
          ),
          const SizedBox(height: 8),
          Text(
            'Note: File uploads (PDF/photo) are done on the website; here you can add the syllabus as text.',
            style: TextStyle(fontSize: 12.5, color: subtleColor(context)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- my formulas

class MyFormulasPage extends StatefulWidget {
  final List<CategoryItem> categories;
  const MyFormulasPage({super.key, required this.categories});

  @override
  State<MyFormulasPage> createState() => _MyFormulasPageState();
}

class _MyFormulasPageState extends State<MyFormulasPage> {
  List<EntryItem> _mine = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await http
          .get(Uri.parse(kApiUrl))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        final data = SheetData.fromJson(
            jsonDecode(r.body) as Map<String, dynamic>);
        _mine = data.entries
            .where((e) =>
                e.userAdded && (auth.isAdmin || e.userId == auth.userId))
            .toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _delete(EntryItem e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this?'),
        content: Text('"${e.name}" will be deleted permanently.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    final r = await auth.api('/api/formulas',
        method: 'DELETE', body: {'id': e.id});
    if (!mounted) return;
    if (r.statusCode == 200) {
      showMsg(context, 'Deleted.');
      _load();
    } else {
      showMsg(context, apiError(r));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: featureBar(auth.isAdmin ? 'All Added Formulas' : 'My Formulas'),
      body: _loading
          ? const MathLoader()
          : _mine.isEmpty
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No formulas added yet. "Add Formula" to add the first one!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: subtleColor(context)),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _mine.length,
                  itemBuilder: (context, i) {
                    final e = _mine[i];
                    return Card(
                      elevation: 0.6,
                      margin: const EdgeInsets.only(bottom: 9),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        title: Text(e.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          [
                            if (e.section.isNotEmpty) e.section,
                            if (auth.isAdmin && e.authorEmail.isNotEmpty)
                              'by ${e.authorEmail}',
                          ].join(' · '),
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  color: kPrimary),
                              onPressed: () async {
                                final changed = await Navigator.of(context)
                                    .push<bool>(MaterialPageRoute(
                                  builder: (_) => FormulaFormPage(
                                      categories: widget.categories,
                                      existing: e),
                                ));
                                if (changed == true) _load();
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red),
                              onPressed: () => _delete(e),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// ---------------------------------------------------------------- admin dashboard

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  Map<String, dynamic>? _overview;
  List<dynamic> _users = [];
  bool _loading = true;
  String _error = '';
  final _limitCtrl = TextEditingController();
  bool _limitBusy = false;

  @override
  void dispose() {
    _limitCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final r1 = await auth.api('/api/admin/overview');
      final r2 = await auth.api('/api/admin/users');
      if (r1.statusCode != 200) {
        setState(() => _error = apiError(r1));
      } else {
        _overview = jsonDecode(r1.body) as Map<String, dynamic>;
      }
      if (r2.statusCode == 200) {
        _users = (jsonDecode(r2.body) as Map<String, dynamic>)['users']
                as List<dynamic>? ??
            [];
      }
      // The AI-limit value loads on its own afterwards (see _loadLimit):
      // it must never hold up or fail the dashboard itself.
    } catch (_) {
      setState(() => _error = 'Network error.');
    }
    if (mounted) setState(() => _loading = false);
    _loadLimit();
  }

  Future<void> _loadLimit() async {
    try {
      final r3 = await auth.api('/api/admin/ai-limit');
      if (!mounted || r3.statusCode != 200) return;
      final d3 = jsonDecode(r3.body) as Map<String, dynamic>;
      if (d3['limit'] is num) {
        setState(
            () => _limitCtrl.text = (d3['limit'] as num).toInt().toString());
      }
    } catch (_) {
      // The limit field simply stays at its default — the dashboard
      // itself is unaffected.
    }
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String sub,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: kPrimary),
        title: Text(title,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
        subtitle: Text(sub, style: const TextStyle(fontSize: 12.5)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Widget _graphCard() {
    final days = (_overview!['days'] as List<dynamic>?) ?? const [];
    if (days.isEmpty) return const SizedBox.shrink();
    var maxV = 1;
    for (final d in days) {
      final m = d as Map<String, dynamic>;
      final pv = (m['pageviews'] as num?)?.toInt() ?? 0;
      final vw = (m['views'] as num?)?.toInt() ?? 0;
      if (pv > maxV) maxV = pv;
      if (vw > maxV) maxV = vw;
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    String label(Object? iso) {
      final str = (iso ?? '').toString();
      if (str.length < 10) return '';
      final mo = int.tryParse(str.substring(5, 7)) ?? 1;
      final dy = int.tryParse(str.substring(8, 10)) ?? 1;
      return '$dy ${months[(mo - 1).clamp(0, 11)]}';
    }

    Widget bar(int v, Color color) {
      final h = v <= 0 ? 0.0 : (92.0 * v / maxV).clamp(2.0, 92.0);
      return Container(
        width: 7,
        height: h,
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(3)),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Analytics — last 14 days',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                        color: kPrimary, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                const Text('Pageviews', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 16),
                Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                        color: Color(0xFF8B5CF6), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                const Text('Formula views', style: TextStyle(fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 96,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final d in days)
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          bar((d as Map)['pageviews'] as int? ?? 0, kPrimary),
                          const SizedBox(width: 2),
                          bar(d['views'] as int? ?? 0,
                              const Color(0xFF8B5CF6)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final e in days.asMap().entries)
                  Expanded(
                    child: Text(
                      e.key % 2 == 0 ? label(e.value['date']) : '',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 9.5, color: subtleColor(context)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveLimit() async {
    final n = int.tryParse(_limitCtrl.text.trim());
    if (n == null || n < 1 || n > 1000) {
      showMsg(context, 'Enter a whole number between 1 and 1000.');
      return;
    }
    setState(() => _limitBusy = true);
    try {
      final r = await auth.api('/api/admin/ai-limit',
          method: 'POST', body: {'limit': n});
      if (!mounted) return;
      if (r.statusCode == 200) {
        showMsg(context,
            'AI Tutor limit set to $n questions per user per day. It applies to everyone within about a minute.');
      } else {
        showMsg(context, apiError(r));
      }
    } catch (_) {
      if (mounted) showMsg(context, 'Network error.');
    }
    if (mounted) setState(() => _limitBusy = false);
  }

  Widget _aiLimitCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome_outlined, size: 19, color: kPrimary),
                SizedBox(width: 8),
                Text('AI Tutor — daily free limit',
                    style:
                        TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'How many questions a user can ask the AI Tutor each day on the app\'s own key. Users with their own Gemini key are not limited. Changes apply within about a minute.',
              style: TextStyle(
                  fontSize: 12.5, height: 1.45, color: subtleColor(context)),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _limitCtrl,
                    keyboardType: TextInputType.number,
                    decoration: fieldDeco('Per day'),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: kPrimary),
                  onPressed: _limitBusy ? null : _saveLimit,
                  child: Text(_limitBusy ? 'Saving…' : 'Save limit'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setRole(Map<String, dynamic> u, String role) async {
    final r = await auth.api('/api/admin/users',
        method: 'POST', body: {'userId': u['id'], 'role': role});
    if (!mounted) return;
    if (r.statusCode == 200) {
      showMsg(context, role == 'admin'
          ? '${u['email']} is now an admin.'
          : '${u['email']} is now a normal user.');
      _load();
    } else {
      showMsg(context, apiError(r));
    }
  }

  Widget _stat(String label, Object? value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        border: Border.all(color: const Color(0xFFD9D2F5)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text('${value ?? 0}',
              style: const TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w800, color: kPrimary)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
        ],
      ),
    );
  }

  Widget _topList(String title, List<dynamic>? items) {
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final it in items.take(8))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                      child: Text('${(it as Map)['name'] ?? ''}',
                          style: const TextStyle(fontSize: 13.5))),
                  Text('${it['count'] ?? ''}',
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _when(Object? iso) {
    final t = (iso ?? '').toString();
    return t.length >= 16 ? t.substring(0, 16).replaceAll('T', ' ') : t;
  }

  String _who(Map<String, dynamic> e) =>
      (e['user_email'] as String?) ?? 'Visitor';

  String _dev(Map<String, dynamic> e) => [e['device'], e['model'], e['os'], e['browser']]
      .where((x) => x != null && '$x'.isNotEmpty)
      .join(' · ');

  Widget _eventList(
    String title,
    List<dynamic>? items,
    String Function(Map<String, dynamic>) titleOf,
    String Function(Map<String, dynamic>) subOf, {
    int take = 15,
  }) {
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final it in items.take(take))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titleOf(it as Map<String, dynamic>),
                      style: const TextStyle(fontSize: 13.5)),
                  Text(subOf(it),
                      style: TextStyle(
                          fontSize: 12, color: subtleColor(context))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _activeTile(Map<String, dynamic> u) {
    final who = (u['user_email'] as String?) ?? 'Visitor';
    final mins = (u['minutes_ago'] as num?)?.toInt() ?? 0;
    final when = mins <= 0 ? 'active now' : '$mins min ago';
    final place = [u['city'], u['country']]
        .where((x) => x != null && '$x'.isNotEmpty)
        .join(', ');
    final battery = u['battery_level'] != null
        ? 'Battery ${u['battery_level']}%${u['battery_charging'] == true ? ' (charging)' : ''}'
        : null;
    final meta = [
      if (_dev(u).isNotEmpty) _dev(u),
      if (u['ip'] != null) '${u['ip']}',
      if (place.isNotEmpty) place,
      if (battery != null) battery,
      if (u['network'] != null) '${u['network']}',
    ].join(' · ');
    final current =
        (u['current_formula'] as String?) ?? (u['current_path'] as String?) ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD9D2F5)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(who,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700))),
              Text(when,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.green,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          if (meta.isNotEmpty)
            Text(meta,
                style: TextStyle(fontSize: 12, color: subtleColor(context))),
          if (current.isNotEmpty)
            Text('Viewing: $current',
                style: TextStyle(fontSize: 12, color: subtleColor(context))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
          appBar: featureBar('Admin Dashboard'), body: const MathLoader());
    }
    if (_error.isNotEmpty || _overview == null) {
      return Scaffold(
        appBar: featureBar('Admin Dashboard'),
        body: Center(
            child: Text(_error.isEmpty ? 'Could not load data.' : _error)),
      );
    }
    final t = (_overview!['totals'] as Map<String, dynamic>?) ?? {};
    final recent =
        (_overview!['recentActivity'] as List<dynamic>?) ?? const [];
    final activeUsers =
        (_overview!['activeUsers'] as List<dynamic>?) ?? const [];
    return Scaffold(
      appBar: featureBar('Admin Dashboard'),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.25,
              children: [
                _stat('Users', t['users']),
                _stat('Pageviews', t['pageviews']),
                _stat("Today's pageviews", t['pageviewsToday']),
                _stat('Visitors', t['visitors']),
                _stat('Formula views', t['formulaViews']),
                _stat('Shares', t['shares']),
                _stat('Built-in formulas', t['seedFormulas']),
                _stat('Added by users', t['addedFormulas']),
                _stat('Categories', t['categories']),
              ],
            ),
            const SizedBox(height: 14),
            _aiLimitCard(),
            const SizedBox(height: 18),
            _graphCard(),
            const SizedBox(height: 18),
            const Text('Sections',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _tile(
              icon: Icons.people_alt_outlined,
              title: 'Visitors',
              sub:
                  '${t['visitors'] ?? 0} people in total · ${activeUsers.length} active now',
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const VisitorsPage())),
            ),
            _tile(
              icon: Icons.manage_accounts_outlined,
              title: 'Users — manage admins',
              sub: '${_users.length} accounts',
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const UsersPage())),
            ),
            _tile(
              icon: Icons.functions,
              title: 'Formula views',
              sub: '${t['formulaViews'] ?? 0} views in total',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => EventListPage(
                        title: 'Formula views',
                        rows: [
                          for (final e
                              in (_overview!['recentViews'] as List<dynamic>? ??
                                  const []))
                            {
                              'title':
                                  ((e as Map)['formula_name'] as String?) ??
                                      'Formula',
                              'sub': [
                                _who(e as Map<String, dynamic>),
                                _dev(e as Map<String, dynamic>),
                                _when((e as Map<String, dynamic>)['created_at'])
                              ].where((x) => x.isNotEmpty).join(' · '),
                            },
                        ],
                      ))),
            ),
            _tile(
              icon: Icons.share_outlined,
              title: 'Shares',
              sub: '${t['shares'] ?? 0} shares in total',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => EventListPage(
                        title: 'Shares',
                        rows: [
                          for (final e
                              in (_overview!['recentShares'] as List<dynamic>? ??
                                  const []))
                            {
                              'title':
                                  ((e as Map)['formula_name'] as String?) ??
                                      'Formula',
                              'sub': [
                                _who(e as Map<String, dynamic>),
                                [(e as Map<String, dynamic>)['city'], (e as Map<String, dynamic>)['country']]
                                    .where((x) => x != null && '$x'.isNotEmpty)
                                    .join(', '),
                                _when((e as Map<String, dynamic>)['created_at'])
                              ].where((x) => x.isNotEmpty).join(' · '),
                            },
                        ],
                      ))),
            ),
            _tile(
              icon: Icons.insights_outlined,
              title: 'Insights',
              sub: 'Top formulas, places, devices & recent additions',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => InsightsPage(overview: _overview!))),
            ),
            _tile(
              icon: Icons.campaign_outlined,
              title: 'Broadcast & Updates',
              sub: 'Send a notice or an app-update message to all users',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const AdminNoticesPage())),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= Admin sub-pages (structured dashboard) =================

String vWho(Map<String, dynamic> e) =>
    (e['user_name'] as String?) ?? (e['user_email'] as String?) ?? 'Visitor';

String vDev(Map<String, dynamic> e) => [e['device'], e['model'], e['os'], e['browser']]
    .where((x) => x != null && '$x'.isNotEmpty)
    .join(' · ');

String vPlace(Map<String, dynamic> e) => [e['city'], e['country']]
    .where((x) => x != null && '$x'.isNotEmpty)
    .join(', ');

String vWhen(Object? iso) {
  final s = (iso ?? '').toString();
  if (s.length < 16) return s;
  return s.replaceFirst('T', ' ').substring(0, 16);
}

String vAgo(Map<String, dynamic> v) {
  if (v['active_now'] == true) return 'Active now';
  final m = (v['minutes_ago'] as num?)?.toInt() ?? 0;
  if (m < 1) return 'Last active just now';
  if (m < 60) return 'Last active $m min ago';
  if (m < 1440) return 'Last active ${(m / 60).floor()} h ago';
  return 'Last active ${(m / 1440).floor()} d ago';
}

/// Visitors: one row per person. Green dot = active in the last
/// 15 minutes; amber dot = last active earlier. Tap a row for the
/// visitor's full timeline.
class VisitorsPage extends StatefulWidget {
  const VisitorsPage({super.key});

  @override
  State<VisitorsPage> createState() => _VisitorsPageState();
}

class _VisitorsPageState extends State<VisitorsPage> {
  List<dynamic> _visitors = [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await auth.api('/api/admin/visitors');
      if (r.statusCode == 200) {
        _visitors =
            (jsonDecode(r.body) as Map<String, dynamic>)['visitors'] as List<dynamic>? ??
                [];
      } else {
        _error = apiError(r);
      }
    } catch (_) {
      _error = 'Network error.';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: featureBar('Visitors'),
      body: _loading
          ? const MathLoader()
          : _error.isNotEmpty
              ? Center(child: Text(_error))
              : _visitors.isEmpty
                  ? const Center(child: Text('No visitors yet.'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _visitors.length,
                        itemBuilder: (context, i) {
                          final v = _visitors[i] as Map<String, dynamic>;
                          final active = v['active_now'] == true;
                          final counts = [
                            if ((v['pageviews'] as num? ?? 0) > 0)
                              '${v['pageviews']} pageviews',
                            if ((v['formula_views'] as num? ?? 0) > 0)
                              '${v['formula_views']} formulas',
                            if ((v['shares'] as num? ?? 0) > 0)
                              '${v['shares']} shares',
                            if ((v['questions'] as num? ?? 0) > 0)
                              '${v['questions']} AI questions',
                          ].join(' · ');
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Container(
                                width: 13,
                                height: 13,
                                decoration: BoxDecoration(
                                  color: active
                                      ? const Color(0xFF22C55E)
                                      : const Color(0xFFF59E0B),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              title: Text(vWho(v),
                                  style: const TextStyle(
                                      fontSize: 14, fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                [
                                  if (vDev(v).isNotEmpty) vDev(v),
                                  if (vPlace(v).isNotEmpty) vPlace(v),
                                  vAgo(v),
                                  if (counts.isNotEmpty) counts,
                                ].join('\n'),
                                style: const TextStyle(fontSize: 12, height: 1.45),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => VisitorDetailPage(visitor: v)),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

/// One visitor's story: who/where/device + everything they did.
class VisitorDetailPage extends StatefulWidget {
  final Map<String, dynamic> visitor;
  const VisitorDetailPage({super.key, required this.visitor});

  @override
  State<VisitorDetailPage> createState() => _VisitorDetailPageState();
}

class _VisitorDetailPageState extends State<VisitorDetailPage> {
  Map<String, dynamic>? _info;
  List<dynamic> _events = [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = widget.visitor;
    final email = v['user_email'] as String?;
    final vid = v['visitor_id'] as String?;
    final ip = v['ip'] as String?;
    final q = email != null
        ? 'email=${Uri.encodeQueryComponent(email)}'
        : vid != null
            ? 'visitor_id=${Uri.encodeQueryComponent(vid)}'
            : 'ip=${Uri.encodeQueryComponent(ip ?? '')}';
    try {
      final r = await auth.api('/api/admin/visitor?$q');
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        _info = d['info'] as Map<String, dynamic>?;
        _events = d['events'] as List<dynamic>? ?? [];
      } else {
        _error = apiError(r);
      }
    } catch (_) {
      _error = 'Network error.';
    }
    if (mounted) setState(() => _loading = false);
  }

  IconData _icon(String? type) {
    switch (type) {
      case 'formula_view':
        return Icons.functions;
      case 'share':
        return Icons.share_outlined;
      case 'favorite_add':
        return Icons.favorite;
      case 'favorite_remove':
        return Icons.favorite_border;
      case 'folder_create':
        return Icons.create_new_folder_outlined;
      case 'folder_add':
        return Icons.folder_open_outlined;
      case 'ai_question':
        return Icons.auto_awesome_outlined;
      case 'pageview':
        return Icons.visibility_outlined;
      default:
        return Icons.bolt_outlined;
    }
  }

  String _title(Map<String, dynamic> e) {
    switch (e['type']) {
      case 'formula_view':
        return 'Saw formula: ${(e['formula_name'] as String?) ?? ''}';
      case 'share':
        return 'Shared: ${(e['formula_name'] as String?) ?? ''}';
      case 'favorite_add':
        return 'Favourited: ${(e['formula_name'] as String?) ?? ''}';
      case 'favorite_remove':
        return 'Removed favourite: ${(e['formula_name'] as String?) ?? ''}';
      case 'folder_create':
        return 'Created a folder';
      case 'folder_add':
        return 'Added to a folder: ${(e['formula_name'] as String?) ?? ''}';
      case 'ai_question':
        return 'Asked the AI Tutor';
      case 'pageview':
        return 'Opened ${(e['path'] as String?) ?? 'the app'}';
      default:
        return (e['type'] as String?) ?? 'Activity';
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.visitor;
    return Scaffold(
      appBar: featureBar(vWho(v)),
      body: _loading
          ? const MathLoader()
          : _error.isNotEmpty
              ? Center(child: Text(_error))
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: _info?['active_now'] == true
                                        ? const Color(0xFF22C55E)
                                        : const Color(0xFFF59E0B),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _info?['active_now'] == true
                                      ? 'Active now'
                                      : vAgo(_info ?? v),
                                  style: const TextStyle(
                                      fontSize: 13.5, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              [
                                if (vDev(_info ?? v).isNotEmpty) vDev(_info ?? v),
                                if (vPlace(_info ?? v).isNotEmpty) vPlace(_info ?? v),
                                if ((_info ?? v)['ip'] != null) 'IP ${(_info ?? v)['ip']}',
                                if ((_info ?? v)['network'] != null) '${(_info ?? v)['network']}',
                                if ((_info ?? v)['battery_level'] != null)
                                  'Battery ${(_info ?? v)['battery_level']}%',
                                'First seen ${vWhen((_info ?? v)['first_seen'])}',
                                'Last seen ${vWhen((_info ?? v)['last_seen'])}',
                                '${(_info ?? v)['total'] ?? _events.length} actions in total',
                                if (((_info ?? v)['presence_signals'] as num? ?? 0) >
                                    0)
                                  'Stayed active ≈ ${(_info ?? v)['presence_signals']} min (presence signals)',
                              ].join('\n'),
                              style: TextStyle(
                                  fontSize: 13,
                                  height: 1.55,
                                  color: subtleColor(context)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('What they did',
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    for (final e in _events)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(_icon((e as Map)['type'] as String?),
                            size: 19, color: kPrimary),
                        title: Text(_title(e as Map<String, dynamic>),
                            style: const TextStyle(fontSize: 13.5)),
                        subtitle: Text(
                          [
                            if (e['category'] != null) '${e['category']}',
                            vWhen(e['created_at']),
                          ].where((x) => x.isNotEmpty).join(' · '),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
    );
  }
}

/// All accounts + admin role management (moved off the dashboard).
class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  List<dynamic> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await auth.api('/api/admin/users');
      if (r.statusCode == 200) {
        _users = (jsonDecode(r.body) as Map<String, dynamic>)['users'] as List<dynamic>? ??
            [];
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setRole(Map<String, dynamic> u, String role) async {
    final r = await auth.api('/api/admin/users',
        method: 'POST', body: {'userId': u['id'], 'role': role});
    if (!mounted) return;
    if (r.statusCode == 200) {
      showMsg(context, 'Role updated.');
      _load();
    } else {
      showMsg(context, apiError(r));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: featureBar('Users — manage admins'),
      body: _loading
          ? const MathLoader()
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final u in _users)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${(u as Map)['email'] ?? ''}',
                        style: const TextStyle(fontSize: 13.5)),
                    subtitle: Text(
                        '${u['role'] ?? 'user'}${u['study_level'] != null && u['study_level'] != '' ? ' · ${u['study_level']}' : ''}${u['institution'] != null && u['institution'] != '' ? ' · ${u['institution']}' : ''}',
                        style: const TextStyle(fontSize: 12)),
                    trailing: (u['lockedAdmin'] == true)
                        ? const Chip(
                            label: Text('Admin (fixed)',
                                style: TextStyle(fontSize: 11)))
                        : (u['role'] == 'admin'
                            ? TextButton(
                                onPressed: () =>
                                    _setRole(u as Map<String, dynamic>, 'user'),
                                child: const Text('Remove Admin',
                                    style: TextStyle(color: Colors.red)))
                            : TextButton(
                                onPressed: () =>
                                    _setRole(u as Map<String, dynamic>, 'admin'),
                                child: const Text('Make Admin'))),
                  ),
              ],
            ),
    );
  }
}

/// A simple titled list (formula views, shares) behind a dashboard tile.
class EventListPage extends StatelessWidget {
  final String title;
  final List<Map<String, String>> rows;
  const EventListPage({super.key, required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: featureBar(title),
      body: rows.isEmpty
          ? const Center(child: Text('Nothing yet.'))
          : ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: rows.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rows[i]['title'] ?? '',
                        style: const TextStyle(fontSize: 13.5)),
                    Text(rows[i]['sub'] ?? '',
                        style: TextStyle(
                            fontSize: 12, color: subtleColor(context))),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Top lists + recent additions, behind the Insights tile.
class InsightsPage extends StatelessWidget {
  final Map<String, dynamic> overview;
  const InsightsPage({super.key, required this.overview});

  Widget _top(String title, List<dynamic>? items, BuildContext context) {
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final it in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                      child: Text('${(it as Map)['name'] ?? ''}',
                          style: const TextStyle(fontSize: 13.5))),
                  Text('${it['count'] ?? ''}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recent = (overview['recentActivity'] as List<dynamic>?) ?? const [];
    return Scaffold(
      appBar: featureBar('Insights'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _top('Most viewed formulas',
              overview['topFormulas'] as List<dynamic>?, context),
          _top('Most favourited formulas',
              overview['topFavorited'] as List<dynamic>?, context),
          _top('Top categories', overview['topCategories'] as List<dynamic>?,
              context),
          _top('Top countries', overview['topCountries'] as List<dynamic>?,
              context),
          _top('Top devices', overview['topDevices'] as List<dynamic>?, context),
          _top('Top operating systems', overview['topOS'] as List<dynamic>?,
              context),
          _top('Top browsers', overview['topBrowsers'] as List<dynamic>?,
              context),
          _top('Top referrers', overview['topReferrers'] as List<dynamic>?,
              context),
          const Text('Recent additions',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (recent.isEmpty)
            Text('No additions yet.',
                style: TextStyle(color: subtleColor(context), fontSize: 13.5)),
          for (final a in recent.take(15))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${(a as Map)['name'] ?? ''}',
                  style: const TextStyle(fontSize: 13.5)),
              subtitle: Text(
                  '${a['author_email'] ?? ''} · ${(a['created_at'] ?? '').toString().substring(0, 10)}',
                  style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- library
// Favourites + personal folders. For a signed-in user the library is
// saved in the account (server: /api/library) and follows them to any
// device. A local cache makes it instant and keeps it usable while
// logged out — a guest's library lives on this device only.

class LibFolder {
  String id;
  String name;
  List<String> items;
  LibFolder({required this.id, required this.name, List<String>? items})
      : items = items ?? [];

  factory LibFolder.fromJson(Map<String, dynamic> j) => LibFolder(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        items: ((j['items'] as List?) ?? []).map((e) => e.toString()).toList(),
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'items': items};
}

class SavedSolution {
  final String id, q, a, at;
  const SavedSolution(
      {required this.id, required this.q, required this.a, required this.at});

  factory SavedSolution.fromJson(Map<String, dynamic> j) => SavedSolution(
        id: (j['id'] ?? '').toString(),
        q: (j['q'] ?? '').toString(),
        a: (j['a'] ?? '').toString(),
        at: (j['at'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {'id': id, 'q': q, 'a': a, 'at': at};
}

class LibraryService extends ChangeNotifier {
  List<String> favorites = [];
  List<LibFolder> folders = [];
  List<SavedSolution> solutions = [];
  bool loaded = false;
  static const String _cacheKey = 'mm_library_v1';

  Map<String, dynamic> toJson() => {
        'favorites': favorites,
        'folders': folders.map((f) => f.toJson()).toList(),
        'solutions': solutions.map((e) => e.toJson()).toList(),
      };

  void applyJson(Map<String, dynamic> j) {
    favorites =
        ((j['favorites'] as List?) ?? []).map((e) => e.toString()).toList();
    folders = ((j['folders'] as List?) ?? [])
        .whereType<Map>()
        .map((m) => LibFolder.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    solutions = ((j['solutions'] as List?) ?? [])
        .whereType<Map>()
        .map((m) => SavedSolution.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  void saveSolution(String q, String a) {
    solutions.insert(
        0,
        SavedSolution(
            id: 's${DateTime.now().millisecondsSinceEpoch}',
            q: q.trim(),
            a: a.trim(),
            at: DateTime.now().toUtc().toIso8601String()));
    if (solutions.length > 50) solutions = solutions.sublist(0, 50);
    _save();
  }

  void removeSolution(String id) {
    solutions.removeWhere((e) => e.id == id);
    _save();
  }

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw != null) applyJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
    loaded = true;
    notifyListeners();
    if (auth.isLoggedIn) await refresh();
  }

  Future<void> refresh() async {
    if (!auth.isLoggedIn) return;
    try {
      final r = await auth.api('/api/library');
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        final lib = d['library'];
        if (lib is Map) {
          applyJson(Map<String, dynamic>.from(lib));
          await _cache();
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  Future<void> _cache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(toJson()));
    } catch (_) {}
  }

  Future<void> _save() async {
    await _cache();
    notifyListeners();
    if (!auth.isLoggedIn) return;
    try {
      await auth.api('/api/library',
          method: 'PUT', body: {'library': toJson()});
    } catch (_) {}
  }

  bool isFavorite(String key) => favorites.contains(key);

  void toggleFavorite(EntryItem e) {
    if (favorites.contains(e.id)) {
      favorites.remove(e.id);
      Tracker.instance.favoriteRemove(displayText(e.name), e.category);
    } else {
      favorites.add(e.id);
      Tracker.instance.favoriteAdd(displayText(e.name), e.category);
    }
    _save();
  }

  LibFolder createFolder(String name) {
    final f = LibFolder(
        id: 'f${DateTime.now().millisecondsSinceEpoch}',
        name: name.trim());
    folders.add(f);
    Tracker.instance.folderCreate();
    _save();
    return f;
  }

  void renameFolder(LibFolder f, String name) {
    f.name = name.trim();
    _save();
  }

  void deleteFolder(LibFolder f) {
    folders.remove(f);
    _save();
  }

  bool inFolder(LibFolder f, String key) => f.items.contains(key);

  void toggleInFolder(LibFolder f, EntryItem e) {
    if (f.items.contains(e.id)) {
      f.items.remove(e.id);
    } else {
      f.items.add(e.id);
      Tracker.instance.folderAdd(displayText(e.name), e.category);
    }
    _save();
  }

  Future<void> onSignedOut() async {
    favorites = [];
    folders = [];
    solutions = [];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
    } catch (_) {}
    notifyListeners();
  }
}

final LibraryService library = LibraryService();

Future<String?> askFolderName(BuildContext context, {String initial = ''}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(initial.isEmpty ? 'New folder' : 'Rename folder'),
      content: TextField(
        controller: ctl,
        autofocus: true,
        maxLength: 60,
        decoration: const InputDecoration(
            hintText: 'e.g. Exam ke liye', labelText: 'Folder name'),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text),
            child: const Text('Save')),
      ],
    ),
  );
}

Future<void> showFolderPicker(BuildContext context, EntryItem entry) async {
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => ListenableBuilder(
      listenable: library,
      builder: (context, _) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('Add to folder',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle:
                    Text('Tick the folders this formula should live in'),
              ),
              if (library.folders.isEmpty)
                const ListTile(
                    subtitle: Text('No folders yet — create one below.')),
              for (final f in library.folders)
                CheckboxListTile(
                  value: library.inFolder(f, entry.id),
                  title: Text(f.name),
                  subtitle: Text('${f.items.length} formulas'),
                  onChanged: (_) => library.toggleInFolder(f, entry),
                ),
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('New folder'),
                onTap: () async {
                  final name = await askFolderName(ctx);
                  if (name != null && name.trim().isNotEmpty) {
                    final f = library.createFolder(name);
                    library.toggleInFolder(f, entry);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  @override
  void initState() {
    super.initState();
    library.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: featureBar('My Library'),
      body: ListenableBuilder(
        listenable: library,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            if (!auth.isLoggedIn)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Guest mode — favourites and folders are saved on this '
                  'device only. Log in to keep them in your account and '
                  'open them on any device.',
                  style: TextStyle(fontSize: 13, height: 1.45),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.favorite, color: Color(0xFFE0245E)),
              title: const Text('Favourites'),
              subtitle: Text('${library.favorites.length} formulas'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => FolderEntriesPage(
                      title: 'Favourites',
                      keys: library.favorites,
                      isFavorites: true))),
            ),
            ListTile(
              leading:
                  const Icon(Icons.bookmark_outlined, color: kPrimary),
              title: const Text('Saved Solutions'),
              subtitle: Text('${library.solutions.length} saved answers'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const SavedSolutionsPage())),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Your folders',
                        style: TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w700)),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final name = await askFolderName(context);
                      if (name != null && name.trim().isNotEmpty) {
                        library.createFolder(name);
                      }
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New folder'),
                  ),
                ],
              ),
            ),
            if (library.folders.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                    'No folders yet. Create one — for example "Exam ke liye" — and add formulas to it from any formula page.',
                    style:
                        TextStyle(color: subtleColor(context), fontSize: 13)),
              ),
            for (final f in library.folders)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(f.name),
                subtitle: Text('${f.items.length} formulas'),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'rename') {
                      final name =
                          await askFolderName(context, initial: f.name);
                      if (name != null && name.trim().isNotEmpty) {
                        library.renameFolder(f, name);
                      }
                    } else if (v == 'delete') {
                      library.deleteFolder(f);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => FolderEntriesPage(
                        title: f.name, keys: f.items, folder: f))),
              ),
          ],
        ),
      ),
    );
  }
}

class FolderEntriesPage extends StatefulWidget {
  final String title;
  final List<String> keys;
  final LibFolder? folder;
  final bool isFavorites;
  const FolderEntriesPage(
      {super.key,
      required this.title,
      required this.keys,
      this.folder,
      this.isFavorites = false});
  @override
  State<FolderEntriesPage> createState() => _FolderEntriesPageState();
}

class _FolderEntriesPageState extends State<FolderEntriesPage> {
  List<EntryItem> _entries = [];
  Map<String, dynamic> _details = {};
  List<CategoryItem> _cats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ds = DataService();
    var sheet = await ds.loadBundled();
    final cache = await ds.loadCache();
    if (cache != null) sheet = cache;
    final net = await ds.fetchNetwork();
    if (net != null) sheet = net;
    _details = await ds.details();
    _cats = sheet.categories;
    final byId = {for (final e in sheet.entries) e.id: e};
    _entries = widget.keys
        .map((k) => byId[k])
        .whereType<EntryItem>()
        .toList();
    if (mounted) setState(() => _loading = false);
  }

  String _catTitle(String slug) {
    for (final c in _cats) {
      if (c.slug == slug) return c.title;
    }
    return slug;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: featureBar(widget.title),
      body: ListenableBuilder(
        listenable: library,
        builder: (context, _) {
          if (_loading) return const MathLoader();
          final visible = _entries
              .where((e) => widget.isFavorites
                  ? library.isFavorite(e.id)
                  : widget.folder == null ||
                      widget.folder!.items.contains(e.id))
              .toList();
          if (visible.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  widget.isFavorites
                      ? 'Nothing here yet — tap the heart on any formula to add it here.'
                      : 'This folder is empty — open any formula and use "Add to Folder".',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: subtleColor(context), fontSize: 14),
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: visible.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final e = visible[i];
              return ListTile(
                title: Text(displayName(e, _details)),
                subtitle: Text(_catTitle(e.category)),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 19),
                  tooltip: 'Remove',
                  onPressed: () {
                    if (widget.isFavorites) {
                      library.toggleFavorite(e);
                    } else if (widget.folder != null) {
                      library.toggleInFolder(widget.folder!, e);
                    }
                  },
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => DetailPage(
                        entry: e,
                        categoryTitle: _catTitle(e.category),
                        details: _details))),
              );
            },
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------- notices
// Admin broadcasts + app-update announcements. The server keeps them
// as notice rows; the app fetches them on start, pops up anything new
// (update notices only when their version is newer than this build),
// and keeps the full list under More -> Notices.

bool isNewerVersion(String a, String b) {
  List<int> parts(String v) => v
      .split('.')
      .map((x) => int.tryParse(x.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

class AppNotice {
  final String id, title, body, kind, version, createdAt;
  const AppNotice(
      {required this.id,
      required this.title,
      required this.body,
      required this.kind,
      required this.version,
      required this.createdAt});

  factory AppNotice.fromJson(Map<String, dynamic> j) => AppNotice(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        body: (j['body'] ?? '').toString(),
        kind: (j['kind'] ?? 'broadcast').toString(),
        version: (j['version'] ?? '').toString(),
        createdAt: (j['created_at'] ?? '').toString(),
      );

  bool get isUpdate => kind == 'update';
}

class NoticesService extends ChangeNotifier {
  List<AppNotice> notices = [];
  Set<String> seen = {};
  static const String _seenKey = 'mm_seen_notices_v1';

  int get unread => notices.where((n) => !seen.contains(n.id)).length;

  List<AppNotice> get popupWorthy => notices
      .where((n) =>
          !seen.contains(n.id) &&
          (!n.isUpdate || isNewerVersion(n.version, kAppVersion)))
      .toList();

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      seen = (prefs.getStringList(_seenKey) ?? []).toSet();
    } catch (_) {}
    await fetch();
  }

  Future<void> fetch() async {
    try {
      final r = await http.get(Uri.parse('$kApiBase/api/notices'));
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        notices = ((d['notices'] as List?) ?? [])
            .map((e) =>
                AppNotice.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> markSeen(Iterable<String> ids) async {
    seen.addAll(ids);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_seenKey, seen.toList());
    } catch (_) {}
    notifyListeners();
  }
}

final NoticesService noticesSvc = NoticesService();

Future<void> maybeShowNoticePopups(BuildContext context) async {
  for (final n in noticesSvc.popupWorthy) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(n.isUpdate
            ? Icons.system_update_outlined
            : Icons.campaign_outlined),
        title: Text(n.isUpdate ? 'Update available — v${n.version}' : n.title),
        content: Text(n.isUpdate ? '${n.title}\n\n${n.body}' : n.body),
        actions: [
          if (n.isUpdate)
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Later')),
          if (n.isUpdate)
            FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  launchUrl(Uri.parse('https://yashx.xyz/MathMitra-app'),
                      mode: LaunchMode.externalApplication);
                },
                child: const Text('Update now')),
          if (!n.isUpdate)
            FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK')),
        ],
      ),
    );
    await noticesSvc.markSeen([n.id]);
  }
}

class NoticesPage extends StatefulWidget {
  const NoticesPage({super.key});
  @override
  State<NoticesPage> createState() => _NoticesPageState();
}

class _NoticesPageState extends State<NoticesPage> {
  @override
  void initState() {
    super.initState();
    noticesSvc.fetch().then((_) {
      if (mounted) {
        noticesSvc.markSeen(noticesSvc.notices.map((n) => n.id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: featureBar('Notices'),
      body: ListenableBuilder(
        listenable: noticesSvc,
        builder: (context, _) {
          if (noticesSvc.notices.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text('No notices yet.',
                    style:
                        TextStyle(color: subtleColor(context), fontSize: 14)),
              ),
            );
          }
          return ListView.separated(
            itemCount: noticesSvc.notices.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final n = noticesSvc.notices[i];
              return ListTile(
                leading: Icon(
                    n.isUpdate
                        ? Icons.system_update_outlined
                        : Icons.campaign_outlined,
                    color: kPrimary),
                title: Text(n.title),
                subtitle: Text(
                    '${n.isUpdate ? 'App update · v${n.version}' : 'Announcement'} · ${fmtIst(n.createdAt)}\n${n.body}'),
                isThreeLine: true,
              );
            },
          );
        },
      ),
    );
  }
}

class AdminNoticesPage extends StatefulWidget {
  const AdminNoticesPage({super.key});
  @override
  State<AdminNoticesPage> createState() => _AdminNoticesPageState();
}

class _AdminNoticesPageState extends State<AdminNoticesPage> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _version = TextEditingController();
  String _kind = 'broadcast';
  bool _busy = false;
  String _msg = '';
  List<AppNotice> _posted = [];

  @override
  void initState() {
    super.initState();
    _loadPosted();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _version.dispose();
    super.dispose();
  }

  Future<void> _loadPosted() async {
    try {
      final r = await http.get(Uri.parse('$kApiBase/api/notices'));
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        _posted = ((d['notices'] as List?) ?? [])
            .map((e) =>
                AppNotice.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _post() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
      setState(() => _msg = 'Title and message are both required.');
      return;
    }
    if (_kind == 'update' && _version.text.trim().isEmpty) {
      setState(() => _msg = 'An update notice needs the new version number.');
      return;
    }
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      final r = await auth.api('/api/admin/notices',
          method: 'POST',
          body: {
            'title': _title.text.trim(),
            'body': _body.text.trim(),
            'kind': _kind,
            'version': _version.text.trim(),
          });
      if (r.statusCode == 200) {
        _title.clear();
        _body.clear();
        _version.clear();
        setState(() => _msg = 'Posted — users will see it when they open the app.');
        await _loadPosted();
        await noticesSvc.fetch();
      } else {
        setState(() => _msg = apiError(r));
      }
    } catch (_) {
      setState(() => _msg = 'Network error.');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _delete(AppNotice n) async {
    try {
      final r = await auth.api('/api/admin/notices?id=${n.id}',
          method: 'DELETE');
      if (r.statusCode == 200) {
        setState(() => _posted = _posted.where((x) => x.id != n.id).toList());
        await noticesSvc.fetch();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: featureBar('Broadcast & Updates'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
              'Send a message to everyone who uses MathMitra. Broadcasts '
              'pop up once when a user opens the app; an app-update notice '
              'pops up only for users on an older version.',
              style: TextStyle(fontSize: 13, height: 1.45)),
          const SizedBox(height: 14),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: 'broadcast',
                  icon: Icon(Icons.campaign_outlined, size: 17),
                  label: Text('Broadcast')),
              ButtonSegment(
                  value: 'update',
                  icon: Icon(Icons.system_update_outlined, size: 17),
                  label: Text('App update')),
            ],
            selected: {_kind},
            onSelectionChanged: (v) => setState(() => _kind = v.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            maxLength: 120,
            decoration: const InputDecoration(
                labelText: 'Title', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _body,
            maxLength: 1000,
            maxLines: 4,
            decoration: const InputDecoration(
                labelText: 'Message', border: OutlineInputBorder()),
          ),
          if (_kind == 'update') ...[
            const SizedBox(height: 10),
            TextField(
              controller: _version,
              decoration: const InputDecoration(
                  labelText: 'New version (e.g. 1.2.1)',
                  border: OutlineInputBorder()),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _post,
            icon: const Icon(Icons.send_outlined, size: 18),
            label: Text(_busy ? 'Posting…' : 'Post notice'),
          ),
          if (_msg.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(_msg, style: const TextStyle(fontSize: 13)),
          ],
          const Divider(height: 28),
          const Text('Posted notices',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (_posted.isEmpty)
            Text('None yet.',
                style: TextStyle(color: subtleColor(context), fontSize: 13)),
          for (final n in _posted)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                  n.isUpdate
                      ? Icons.system_update_outlined
                      : Icons.campaign_outlined,
                  color: kPrimary),
              title: Text(n.title),
              subtitle: Text(
                  '${n.isUpdate ? 'Update · v${n.version}' : 'Broadcast'} · ${fmtIst(n.createdAt)}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete',
                onPressed: () => _delete(n),
              ),
            ),
        ],
      ),
    );
  }
}


class SavedSolutionsPage extends StatelessWidget {
  const SavedSolutionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: featureBar('Saved Solutions'),
      body: ListenableBuilder(
        listenable: library,
        builder: (context, _) {
          if (library.solutions.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  'No saved solutions yet — in the AI Tutor, tap Save under '
                  'any answer to keep it here together with its question.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: subtleColor(context), fontSize: 14),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: library.solutions.length,
            itemBuilder: (context, i) {
              final sol = library.solutions[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(sol.q,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 19),
                            tooltip: 'Delete',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => library.removeSolution(sol.id),
                          ),
                        ],
                      ),
                      if (sol.at.isNotEmpty)
                        Text(fmtIst(sol.at),
                            style: TextStyle(
                                fontSize: 11.5,
                                color: subtleColor(context))),
                      const SizedBox(height: 8),
                      StructuredText(
                          text: displayText(sol.a),
                          style: TextStyle(
                              fontSize: 14,
                              height: 1.55,
                              color:
                                  Theme.of(context).colorScheme.onSurface)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
