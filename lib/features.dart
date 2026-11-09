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
          ? const Center(child: CircularProgressIndicator())
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
    } catch (_) {
      setState(() => _error = 'Network error.');
    }
    if (mounted) setState(() => _loading = false);
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
          appBar: featureBar('Admin Dashboard'),
          body: const Center(child: CircularProgressIndicator()));
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
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                      color: Colors.green, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                const Text('Active users — last 15 minutes',
                    style:
                        TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            if (activeUsers.isEmpty)
              Text('Nobody is active right now.',
                  style: TextStyle(color: subtleColor(context), fontSize: 13.5)),
            for (final u in activeUsers)
              _activeTile(u as Map<String, dynamic>),
            _topList('Most viewed formulas',
                _overview!['topFormulas'] as List<dynamic>?),
            _topList('Top categories',
                _overview!['topCategories'] as List<dynamic>?),
            _topList('Top countries',
                _overview!['topCountries'] as List<dynamic>?),
            _topList('Top devices',
                _overview!['topDevices'] as List<dynamic>?),
            _topList('Top operating systems',
                _overview!['topOS'] as List<dynamic>?),
            _topList('Top browsers',
                _overview!['topBrowsers'] as List<dynamic>?),
            _topList('Top referrers',
                _overview!['topReferrers'] as List<dynamic>?),
            _eventList(
              'Recent formula views',
              _overview!['recentViews'] as List<dynamic>?,
              (e) => (e['formula_name'] as String?) ?? 'Formula',
              (e) => [_who(e), _dev(e), _when(e['created_at'])]
                  .where((x) => x.isNotEmpty)
                  .join(' · '),
            ),
            _eventList(
              'Recent visitors',
              _overview!['recentVisitors'] as List<dynamic>?,
              (e) => (e['path'] as String?) ?? '/',
              (e) => [
                _who(e),
                _dev(e),
                if (e['ip'] != null) '${e['ip']}',
                [e['city'], e['country']]
                    .where((x) => x != null && '$x'.isNotEmpty)
                    .join(', '),
                if (e['battery_level'] != null)
                  'Battery ${e['battery_level']}%',
                _when(e['created_at']),
              ].where((x) => x.isNotEmpty).join(' · '),
              take: 20,
            ),
            _eventList(
              'Recent shares',
              _overview!['recentShares'] as List<dynamic>?,
              (e) => (e['formula_name'] as String?) ?? 'Formula',
              (e) => [
                _who(e),
                [e['city'], e['country']]
                    .where((x) => x != null && '$x'.isNotEmpty)
                    .join(', '),
                _when(e['created_at']),
              ].where((x) => x.isNotEmpty).join(' · '),
            ),
            const SizedBox(height: 18),
            const Text('Recent additions',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (recent.isEmpty)
              Text('No additions yet.',
                  style: TextStyle(color: subtleColor(context), fontSize: 13.5)),
            for (final a in recent.take(10))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${(a as Map)['name'] ?? ''}',
                    style: const TextStyle(fontSize: 13.5)),
                subtitle: Text(
                    '${a['author_email'] ?? ''} · ${(a['created_at'] ?? '').toString().substring(0, 10)}',
                    style: const TextStyle(fontSize: 12)),
              ),
            const SizedBox(height: 18),
            const Text('Users — manage admins',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
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
      ),
    );
  }
}
