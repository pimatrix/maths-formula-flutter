import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, rootBundle;
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_page.dart';
import 'contact_page.dart';
import 'features.dart';

const String kApiUrl = 'https://yashx.xyz/math-formula-sheet-m1/api/formulas';
const String kCacheKey = 'fs_api_cache_v1';
const Color kPrimary = Color(0xFF4338CA);
const Color kPrimaryDark = Color(0xFF2A1A5E);

void main() {
  runApp(const FormulaApp());
}

// ---------------------------------------------------------------- models

class CategoryItem {
  final String slug;
  final String title;
  final String group;
  const CategoryItem(this.slug, this.title, this.group);
  factory CategoryItem.fromJson(Map<String, dynamic> j) => CategoryItem(
        j['slug'] as String? ?? '',
        j['title'] as String? ?? '',
        j['group'] as String? ?? '',
      );
}

class EntryItem {
  final String id;
  final String category;
  final String section;
  final String name;
  final String body;
  final String kind;
  final bool userAdded;
  final String about;
  final String symbols;
  final String example;
  final String userId;
  final String authorName;
  final String authorEmail;
  final String createdAt;
  const EntryItem({
    required this.id,
    required this.category,
    required this.section,
    required this.name,
    required this.body,
    required this.kind,
    required this.userAdded,
    required this.about,
    required this.symbols,
    required this.example,
    this.userId = '',
    this.authorName = '',
    this.authorEmail = '',
    this.createdAt = '',
  });
  factory EntryItem.fromJson(Map<String, dynamic> j) => EntryItem(
        id: j['id'] as String? ?? '',
        category: j['category'] as String? ?? '',
        section: j['section'] as String? ?? '',
        name: j['name'] as String? ?? '',
        body: j['body'] as String? ?? '',
        kind: j['kind'] as String? ?? 'formula',
        userAdded: j['userAdded'] as bool? ?? false,
        about: j['about'] as String? ?? '',
        symbols: j['symbols'] as String? ?? '',
        example: j['example'] as String? ?? '',
        userId: j['user_id'] as String? ?? '',
        authorName: j['author_name'] as String? ?? '',
        authorEmail: j['author_email'] as String? ?? '',
        createdAt: j['created_at'] as String? ?? '',
      );
}

class SyllabusItem {
  final String title;
  final String content;
  const SyllabusItem(this.title, this.content);
  factory SyllabusItem.fromJson(Map<String, dynamic> j) => SyllabusItem(
        j['title'] as String? ?? 'Syllabus',
        j['content'] as String? ?? '',
      );
}

class SheetData {
  final List<CategoryItem> categories;
  final List<EntryItem> entries;
  final List<SyllabusItem> syllabus;
  const SheetData(this.categories, this.entries, this.syllabus);

  factory SheetData.fromJson(Map<String, dynamic> j) => SheetData(
        ((j['categories'] as List?) ?? [])
            .map((e) => CategoryItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        ((j['entries'] as List?) ?? [])
            .map((e) => EntryItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        ((j['syllabus'] as List?) ?? [])
            .map((e) => SyllabusItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ---------------------------------------------------------------- text utils

const Map<String, String> _supMap = {
  '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴', '5': '⁵', '6': '⁶',
  '7': '⁷', '8': '⁸', '9': '⁹', '+': '⁺', '-': '⁻', '−': '⁻', '(': '⁽',
  ')': '⁾', '=': '⁼', '.': '·', '/': 'ᐟ',
  'a': 'ᵃ', 'b': 'ᵇ', 'c': 'ᶜ', 'd': 'ᵈ', 'e': 'ᵉ', 'f': 'ᶠ', 'g': 'ᵍ',
  'h': 'ʰ', 'i': 'ⁱ', 'j': 'ʲ', 'k': 'ᵏ', 'l': 'ˡ', 'm': 'ᵐ', 'n': 'ⁿ',
  'o': 'ᵒ', 'p': 'ᵖ', 'r': 'ʳ', 's': 'ˢ', 't': 'ᵗ', 'u': 'ᵘ', 'v': 'ᵛ',
  'w': 'ʷ', 'x': 'ˣ', 'y': 'ʸ', 'z': 'ᶻ',
  'A': 'ᴬ', 'B': 'ᴮ', 'D': 'ᴰ', 'E': 'ᴱ', 'G': 'ᴳ', 'H': 'ᴴ', 'I': 'ᴵ',
  'J': 'ᴶ', 'K': 'ᴷ', 'L': 'ᴸ', 'M': 'ᴹ', 'N': 'ᴺ', 'O': 'ᴼ', 'P': 'ᴾ',
  'R': 'ᴿ', 'T': 'ᵀ', 'U': 'ᵁ', 'V': 'ⱽ', 'W': 'ᵂ',
};
const Map<String, String> _subMap = {
  '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄', '5': '₅', '6': '₆',
  '7': '₇', '8': '₈', '9': '₉', '+': '₊', '-': '₋', '−': '₋', '(': '₍',
  ')': '₎', '=': '₌',
  'a': 'ₐ', 'e': 'ₑ', 'h': 'ₕ', 'i': 'ᵢ', 'j': 'ⱼ', 'k': 'ₖ', 'l': 'ₗ',
  'm': 'ₘ', 'n': 'ₙ', 'o': 'ₒ', 'p': 'ₚ', 'r': 'ᵣ', 's': 'ₛ', 't': 'ₜ',
  'u': 'ᵤ', 'v': 'ᵥ', 'x': 'ₓ',
};

String _script(String s, Map<String, String> map, String fallbackPrefix) {
  // Convert every character that has a script form. If nothing at all could
  // be converted, fall back to ^x / _x notation so nothing is silently lost.
  var converted = false;
  final buf = StringBuffer();
  for (final ch in s.split('')) {
    final m = map[ch];
    if (m != null) converted = true;
    buf.write(m ?? ch);
  }
  if (!converted && s.isNotEmpty) return '$fallbackPrefix$s';
  return buf.toString();
}

String toSup(String s) => _script(s, _supMap, '^');
String toSub(String s) => _script(s, _subMap, '_');

/// Converts the website's formula HTML into readable plain text.
String cleanBody(String html) {
  var s = html;
  // fractions: <span class="frac"><span class="t">NUM</span><span class="b">DEN</span></span>
  s = s.replaceAllMapped(
    RegExp(r'<span class="frac"><span class="t">(.*?)</span><span class="b">(.*?)</span></span>',
        dotAll: true),
    (m) => '(${m[1]})/(${m[2]})',
  );
  s = s.replaceAllMapped(RegExp(r'<sup>(.*?)</sup>', dotAll: true),
      (m) => _script(m[1]!, _supMap, '^'));
  s = s.replaceAllMapped(RegExp(r'<sub>(.*?)</sub>', dotAll: true),
      (m) => _script(m[1]!, _subMap, '_'));
  s = s.replaceAll(RegExp(r'<br\s*/?>'), '\n');
  s = s.replaceAll('</p>', '\n');
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&gt;', '>')
      .replaceAll('&lt;', '<')
      .replaceAll('&amp;', '&')
      .replaceAll('&minus;', '−');
  s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
  s = s.replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n');
  return s.trim();
}

const Map<String, String> _cmdMap = {
  'alpha': 'α', 'beta': 'β', 'gamma': 'γ', 'Gamma': 'Γ', 'delta': 'δ',
  'Delta': 'Δ', 'epsilon': 'ε', 'zeta': 'ζ', 'eta': 'η', 'theta': 'θ',
  'Theta': 'Θ', 'iota': 'ι', 'kappa': 'κ', 'lambda': 'λ', 'Lambda': 'Λ',
  'mu': 'μ', 'nu': 'ν', 'xi': 'ξ', 'pi': 'π', 'Pi': 'Π', 'rho': 'ρ',
  'sigma': 'σ', 'Sigma': 'Σ', 'tau': 'τ', 'phi': 'φ', 'Phi': 'Φ', 'chi': 'χ',
  'psi': 'ψ', 'omega': 'ω', 'Omega': 'Ω', 'int': '∫', 'oint': '∮',
  'sum': '∑', 'prod': '∏', 'infty': '∞', 'partial': '∂', 'pm': '±',
  'mp': '∓', 'leq': '≤', 'geq': '≥', 'neq': '≠', 'approx': '≈',
  'equiv': '≡', 'to': '→', 'rightarrow': '→', 'leftarrow': '←',
  'times': '×', 'cdot': '·', 'div': '÷', 'in': '∈', 'notin': '∉',
  'subset': '⊂', 'cup': '∪', 'cap': '∩', 'forall': '∀', 'exists': '∃',
  'angle': '∠', 'degree': '°', 'prime': '′', 'nabla': '∇',
};

/// Converts raw FormulaText markup ( \frac{a}{b}, x^{2}, \sqrt{..}, \pi … )
/// into clean, book-style plain text.
String formulaTextToPlain(String input) {
  final s = input;
  final out = StringBuffer();
  var i = 0;

  String? readGroup() {
    if (i >= s.length || s[i] != '{') return null;
    var depth = 0;
    for (var j = i; j < s.length; j++) {
      if (s[j] == '{') depth++;
      if (s[j] == '}') {
        depth--;
        if (depth == 0) {
          final g = s.substring(i + 1, j);
          i = j + 1;
          return g;
        }
      }
    }
    return null;
  }

  while (i < s.length) {
    final ch = s[i];
    if (ch == '\\') {
      final m = RegExp(r'\\([a-zA-Z]+)').matchAsPrefix(s, i);
      if (m != null) {
        final cmd = m.group(1)!;
        i += m.group(0)!.length;
        if (cmd == 'frac') {
          final a = readGroup();
          final b = a == null ? null : readGroup();
          if (a != null && b != null) {
            out.write(
                '(${formulaTextToPlain(a)})/(${formulaTextToPlain(b)})');
            continue;
          }
          continue;
        }
        if (cmd == 'sqrt') {
          final a = readGroup();
          if (a != null) {
            out.write('√(${formulaTextToPlain(a)})');
            continue;
          }
          out.write('√');
          continue;
        }
        out.write(_cmdMap[cmd] ?? cmd);
        continue;
      }
      // Escaped space/punctuation (\, \; \: \ ) — just a space.
      if (i + 1 < s.length && ',;: '.contains(s[i + 1])) {
        out.write(' ');
        i += 2;
        continue;
      }
      i++;
      continue;
    }
    if (ch == '^' || ch == '_') {
      final isSup = ch == '^';
      i++;
      String inner;
      if (i < s.length && s[i] == '{') {
        inner = readGroup() ?? '';
      } else if (i < s.length && s[i] == '(') {
        // ^(2+3) style — read the balanced bracket as the script content.
        var depth = 0;
        final start = i;
        var j = i;
        for (; j < s.length; j++) {
          if (s[j] == '(') depth++;
          if (s[j] == ')') {
            depth--;
            if (depth == 0) break;
          }
        }
        if (j < s.length) {
          inner = s.substring(start + 1, j);
          i = j + 1;
        } else {
          inner = s[i];
          i++;
        }
      } else if (i < s.length) {
        inner = s[i];
        i++;
      } else {
        inner = '';
      }
      final rendered = formulaTextToPlain(inner);
      out.write(isSup ? toSup(rendered) : toSub(rendered));
      continue;
    }
    if (ch == 'M' && s.startsWith('MAT(', i)) {
      final end = s.indexOf(')', i);
      if (end > i) {
        final inner = s.substring(i + 4, end);
        out.write('[ ${inner.split(';').map((r) => r.trim()).join('  ;  ')} ]');
        i = end + 1;
        continue;
      }
    }
    out.write(ch);
    i++;
  }
  return out.toString().replaceAll(RegExp(r'[ \t]+'), ' ').trim();
}

/// Renders any stored body/text (HTML for built-in entries, FormulaText for
/// user entries and detail fields) as clean book-style plain text.
String displayText(String s) {
  final n = s.replaceAll('\\n', '\n');
  if (n.contains('<')) return cleanBody(n);
  return formulaTextToPlain(n);
}

/// Display name for an entry: a hand-written verbal title when one exists
/// in the details data, otherwise the stored name (lightly cleaned).
String displayName(EntryItem e, Map<String, dynamic> details) {
  if (!e.userAdded) {
    final d = details[e.id];
    if (d is Map && (d['title'] as String?)?.isNotEmpty == true) {
      return d['title'] as String;
    }
  }
  return displayText(e.name);
}

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

/// ISO timestamp → "8 Nov 2026, 10:05 am IST" for display.
String fmtIst(String iso) {
  final t = DateTime.tryParse(iso);
  if (t == null) return iso;
  final ist = t.toUtc().add(const Duration(hours: 5, minutes: 30));
  var h = ist.hour;
  final ampm = h >= 12 ? 'pm' : 'am';
  h = h % 12 == 0 ? 12 : h % 12;
  final mm = ist.minute.toString().padLeft(2, '0');
  return '${ist.day} ${_months[ist.month - 1]} ${ist.year}, $h:$mm $ampm IST';
}

/// Shares an entry (system share sheet where available, clipboard fallback).
Future<void> shareEntry(
    BuildContext context, EntryItem e, Map<String, dynamic> details) async {
  final text = '${displayName(e, details)}\n'
      '${displayText(e.body)}\n\n'
      '— Maths Formula Sheet\n'
      'https://yashx.xyz/math-formula-sheet-m1';
  try {
    await Share.share(text, subject: displayName(e, details));
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Copied — paste it anywhere to share.')));
    }
  }
}

// ---------------------------------------------------------------- data layer

class DataService {
  SheetData? _bundled;
  Map<String, dynamic> _details = {};

  Future<Map<String, dynamic>> details() async {
    if (_details.isNotEmpty) return _details;
    try {
      final raw = await rootBundle.loadString('assets/formula-details.json');
      _details = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {}
    return _details;
  }

  Future<SheetData> loadBundled() async {
    if (_bundled != null) return _bundled!;
    final raw = await rootBundle.loadString('assets/formulas-seed.json');
    _bundled = SheetData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    return _bundled!;
  }

  Future<SheetData?> loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kCacheKey);
      if (raw == null) return null;
      return SheetData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<SheetData?> fetchNetwork() async {
    try {
      final res =
          await http.get(Uri.parse(kApiUrl)).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final data =
          SheetData.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kCacheKey, res.body);
      return data;
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------- shell glue

/// Carries a Browse-page selection (category filter + optional section)
/// into the Home list.
class BrowseSel extends ChangeNotifier {
  static final BrowseSel instance = BrowseSel._();
  BrowseSel._();
  String filter = 'all';
  String section = '';
  void go(String filter, String section) {
    this.filter = filter;
    this.section = section;
    notifyListeners();
  }
}

/// Pings the Home list to refetch after data changed elsewhere (Add hub).
class DataPing extends ChangeNotifier {
  static final DataPing instance = DataPing._();
  DataPing._();
  void ping() => notifyListeners();
}

// ---------------------------------------------------------------- app

class FormulaApp extends StatelessWidget {
  const FormulaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Maths Formula Sheet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: kPrimary),
        useMaterial3: true,
      ),
      home: const MainShell(),
    );
  }
}

/// Bottom-navigation shell: Home · Browse · Add · AI Tutor · More.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          const HomePage(),
          BrowsePage(onGo: () => setState(() => _tab = 0)),
          const AddHubPage(),
          const AiTutorPage(),
          MorePage(onGoHome: () => setState(() => _tab = 1)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore),
              label: 'Browse'),
          NavigationDestination(
              icon: Icon(Icons.add_circle_outline),
              selectedIcon: Icon(Icons.add_circle),
              label: 'Add'),
          NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined),
              selectedIcon: Icon(Icons.auto_awesome),
              label: 'AI Tutor'),
          NavigationDestination(
              icon: Icon(Icons.menu),
              label: 'More'),
        ],
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DataService _svc = DataService();
  SheetData? _data;
  Map<String, dynamic> _details = {};
  String _query = '';
  String _filter = 'all'; // all | basics | <category slug>
  String _sectionFilter = '';
  bool _online = false;

  @override
  void initState() {
    super.initState();
    _load();
    auth.addListener(_onAuth);
    auth.load();
    BrowseSel.instance.addListener(_onBrowse);
    DataPing.instance.addListener(_refreshData);
  }

  @override
  void dispose() {
    auth.removeListener(_onAuth);
    BrowseSel.instance.removeListener(_onBrowse);
    DataPing.instance.removeListener(_refreshData);
    super.dispose();
  }

  void _onBrowse() {
    if (!mounted) return;
    setState(() {
      _filter = BrowseSel.instance.filter;
      _sectionFilter = BrowseSel.instance.section;
    });
  }

  void _onAuth() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshData() async {
    final fresh = await _svc.fetchNetwork();
    if (fresh != null && mounted) {
      setState(() {
        _data = fresh;
        _online = true;
      });
    }
  }

  List<CategoryItem> get _cats => _data?.categories ?? const [];

  Future<void> _open(Widget page, {bool reload = false}) async {
    final changed =
        await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => page));
    if (changed == true || reload) _refreshData();
  }

  Future<void> _needLogin(String note, Widget page) async {
    if (!auth.isLoggedIn) {
      await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => AuthPage(note: note)));
      if (!auth.isLoggedIn || !mounted) return;
    }
    _open(page, reload: true);
  }

  Future<void> _load() async {
    final bundled = await _svc.loadBundled();
    if (!mounted) return;
    setState(() => _data = bundled);
    _svc.details().then((d) {
      if (mounted) setState(() => _details = d);
    });
    final cached = await _svc.loadCache();
    if (cached != null && mounted) setState(() => _data = cached);
    final fresh = await _svc.fetchNetwork();
    if (fresh != null && mounted) {
      setState(() {
        _data = fresh;
        _online = true;
      });
    }
  }

  List<EntryItem> get _visible {
    final data = _data;
    if (data == null) return [];
    var list = data.entries.where((e) {
      if (_sectionFilter.isNotEmpty && e.section != _sectionFilter) {
        return false;
      }
      if (_filter == 'all') return true;
      if (_filter == 'basics') return e.category.startsWith('basics-');
      return e.category == _filter;
    }).toList();

    final raw = _query.trim().toLowerCase();
    if (raw.isNotEmpty) {
      final catTitle = {
        for (final c in data.categories) c.slug: c.title.toLowerCase()
      };
      String indexOf(EntryItem e) =>
          '${e.name} ${e.section} ${catTitle[e.category] ?? ''} ${displayText(e.body)}'
              .toLowerCase();
      const stopwords = {'of', 'the', 'a', 'an', 'and', 'for', 'to', 'in'};
      final tokens = raw
          .split(RegExp(r'\s+'))
          .where((t) => !stopwords.contains(t))
          .map((t) =>
              (t.length > 3 && t.endsWith('s')) ? t.substring(0, t.length - 1) : t)
          .where((t) => t.length >= 2)
          .toList();
      if (tokens.isNotEmpty) {
        final scored = list.map((e) {
          final text = indexOf(e);
          final hits = tokens.where((t) => text.contains(t)).length;
          return (e, hits);
        }).toList();
        final all = scored.where((s) => s.$2 == tokens.length).toList();
        if (all.isNotEmpty) {
          list = all.map((s) => s.$1).toList();
        } else {
          final some = scored.where((s) => s.$2 > 0).toList()
            ..sort((a, b) => b.$2.compareTo(a.$2));
          list = some.map((s) => s.$1).toList();
        }
      }
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final visible = _visible;
    final searching = _query.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kPrimaryDark,
        foregroundColor: Colors.white,
        title: const Text('Maths Formula Sheet'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Add Formula',
            onPressed: () => _needLogin(
              'Please log in to add a formula. Your existing website account works here.',
              FormulaFormPage(categories: _cats),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Row(children: [
              Icon(_online ? Icons.cloud_done : Icons.cloud_off, size: 16),
              const SizedBox(width: 4),
              Text(_online ? 'Online' : 'Offline',
                  style: const TextStyle(fontSize: 11.5)),
            ]),
          ),
        ],
      ),
      drawer: _drawer(),
      body: data == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search formulas… e.g. Quadratic equations',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                SizedBox(
                  height: 46,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      _chip('all', 'All Formulas'),
                      _chip('basics', 'All Basics'),
                      for (final c in data.categories) _chip(c.slug, c.title),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      searching
                          ? 'Showing ${visible.length} of ${data.entries.length} entries for "${_query.trim()}"'
                          : 'Showing ${visible.length} of ${data.entries.length} entries',
                      style:
                          const TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                  ),
                ),
                if (_sectionFilter.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: InputChip(
                        avatar: const Icon(Icons.topic_outlined, size: 16),
                        label: Text('Section: $_sectionFilter'),
                        onDeleted: () => setState(() => _sectionFilter = ''),
                        deleteIconColor: kPrimary,
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                Expanded(
                  child: visible.isEmpty
                      ? const Center(
                          child: Text(
                              'No formula matched. Try a shorter search word.'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 2, 12, 16),
                          itemCount: visible.length +
                              ((!searching &&
                                      _filter == 'all' &&
                                      _sectionFilter.isEmpty &&
                                      data.syllabus.isNotEmpty)
                                  ? 1
                                  : 0),
                          itemBuilder: (context, i) {
                            if (i == visible.length) {
                              return _syllabusCard(data.syllabus.first);
                            }
                            return _entryCard(visible[i], data);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _drawer() {
    final loggedIn = auth.isLoggedIn;
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              gradient:
                  LinearGradient(colors: [kPrimaryDark, Color(0xFF5B21B6)]),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text('Maths Formula Sheet',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  loggedIn
                      ? '${auth.name.isEmpty ? auth.email : auth.name}${auth.isAdmin ? ' · Admin' : ''}'
                      : 'Read, understand, and add your own formulas',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: const Text('Add Formula'),
            onTap: () {
              Navigator.pop(context);
              _needLogin(
                'Please log in to add a formula. Your existing website account works here.',
                FormulaFormPage(categories: _cats),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: const Text('Add Class / Category'),
            onTap: () {
              Navigator.pop(context);
              _needLogin(
                'Please log in to add a class or category.',
                const CategoryFormPage(),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('Add Syllabus'),
            onTap: () {
              Navigator.pop(context);
              _needLogin(
                'Please log in to add syllabus notes.',
                SyllabusFormPage(categories: _cats),
              );
            },
          ),
          if (loggedIn)
            ListTile(
              leading: const Icon(Icons.list_alt_outlined),
              title: Text(auth.isAdmin ? 'All Added Formulas' : 'My Formulas'),
              onTap: () {
                Navigator.pop(context);
                _open(MyFormulasPage(categories: _cats), reload: true);
              },
            ),
          if (auth.isAdmin)
            ListTile(
              leading: const Icon(Icons.dashboard_outlined),
              title: const Text('Admin Dashboard'),
              onTap: () {
                Navigator.pop(context);
                _open(const AdminPage());
              },
            ),
          const Divider(),
          if (loggedIn)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('My Profile'),
              onTap: () {
                Navigator.pop(context);
                _open(const ProfilePage());
              },
            )
          else
            ListTile(
              leading: const Icon(Icons.login),
              title: const Text('Login / Sign Up'),
              onTap: () {
                Navigator.pop(context);
                _open(const AuthPage());
              },
            ),
        ],
      ),
    );
  }

  Widget _chip(String value, String label) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12.5)),
        selected: selected,
        onSelected: (_) => setState(() {
          _filter = value;
          _sectionFilter = '';
        }),
      ),
    );
  }

  Widget _entryCard(EntryItem e, SheetData data) {
    final catTitle = data.categories
        .where((c) => c.slug == e.category)
        .map((c) => c.title)
        .firstOrNull;
    final isTheory = e.kind == 'theory';
    return Card(
      elevation: 0.6,
      margin: const EdgeInsets.only(bottom: 9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => DetailPage(
              entry: e, categoryTitle: catTitle ?? e.category, details: _details),
        )),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 6, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(displayName(e, _details),
                            style: const TextStyle(
                                fontSize: 15.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (catTitle != null) catTitle,
                            if (e.section.isNotEmpty) e.section,
                          ].join(' · '),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black45),
                        ),
                      ],
                    ),
                  ),
                  _kindBadge(isTheory),
                ],
              ),
              const SizedBox(height: 7),
              // Theory entries show their FULL text in the list; formulas
              // get a compact preview (the full view is one tap away).
              Text(
                displayText(e.body),
                maxLines: isTheory ? null : 3,
                overflow:
                    isTheory ? TextOverflow.visible : TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: isTheory ? 14 : 15,
                    height: 1.45,
                    color: Colors.black87),
              ),
              Row(
                children: [
                  if (e.userAdded && e.authorName.isNotEmpty)
                    Expanded(
                      child: Text('by ${e.authorName}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11.5, color: Colors.black38)),
                    )
                  else
                    const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.share_outlined, size: 19),
                    color: kPrimary,
                    tooltip: 'Share',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => shareEntry(context, e, _details),
                  ),
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => DetailPage(
                          entry: e,
                          categoryTitle: catTitle ?? e.category,
                          details: _details),
                    )),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('View',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        Icon(Icons.chevron_right, size: 19),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kindBadge(bool isTheory) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isTheory
            ? const Color(0xFFFFF4D6)
            : const Color(0xFFE7E2FA),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(isTheory ? 'Theory' : 'Formula',
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: isTheory
                  ? const Color(0xFF8A6D00)
                  : const Color(0xFF4A3A9E))),
    );
  }

  Widget _syllabusCard(SyllabusItem s) {
    return Card(
      color: const Color(0xFFEFEBFB),
      elevation: 0.6,
      margin: const EdgeInsets.only(top: 4, bottom: 9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => SyllabusPage(item: s))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const Icon(Icons.menu_book, color: kPrimary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(s.title,
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w600)),
            ),
            const Icon(Icons.chevron_right, color: kPrimary, size: 20),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- detail page

class DetailPage extends StatelessWidget {
  final EntryItem entry;
  final String categoryTitle;
  final Map<String, dynamic> details;
  const DetailPage(
      {super.key,
      required this.entry,
      required this.categoryTitle,
      required this.details});

  @override
  Widget build(BuildContext context) {
    String about = entry.about;
    String symbols = entry.symbols;
    String example = entry.example;
    if (!entry.userAdded) {
      final d = details[entry.id];
      if (d is Map) {
        about = d['about'] as String? ?? '';
        symbols = d['symbols'] as String? ?? '';
        example = d['example'] as String? ?? '';
      }
    }
    final hasDetail = about.isNotEmpty || symbols.isNotEmpty || example.isNotEmpty;
    final name = displayName(entry, details);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kPrimaryDark,
        foregroundColor: Colors.white,
        title: Text(name, style: const TextStyle(fontSize: 17)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share',
            onPressed: () => shareEntry(context, entry, details),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            name,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            entry.section.isEmpty
                ? categoryTitle
                : '$categoryTitle · ${entry.section}',
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF7C6AA8)),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              border: Border.all(color: const Color(0xFFD9D2F5)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              displayText(entry.body),
              textAlign:
                  entry.kind == 'theory' ? TextAlign.left : TextAlign.center,
              style: TextStyle(
                  fontSize: entry.kind == 'theory' ? 15.5 : 21, height: 1.5),
            ),
          ),
          if (entry.userAdded && entry.authorName.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Added by ${entry.authorName}'
              '${entry.authorEmail.isNotEmpty ? ' (${entry.authorEmail})' : ''}'
              '${entry.createdAt.isNotEmpty ? ' · ${fmtIst(entry.createdAt)}' : ''}',
              style: const TextStyle(fontSize: 12, color: Colors.black45),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: kPrimary,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Ask AI about this formula'),
              onPressed: () =>
                  openFormulaAi(context, entry, details, categoryTitle),
            ),
          ),
          const SizedBox(height: 16),
          if (about.isNotEmpty)
            _block('What is this formula for?', displayText(about)),
          if (symbols.isNotEmpty) _symbolsBlock(symbols),
          if (example.isNotEmpty)
            _block('Example — how to use it', displayText(example),
                green: true),
          if (!hasDetail)
            const Text(
              'Details for this one (meaning, symbols and a solved example) are being added — check back soon.',
              style: TextStyle(color: Colors.black45, fontSize: 13.5),
            ),
        ],
      ),
    );
  }

  Widget _block(String title, String text, {bool green = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 13),
      padding:
          green ? const EdgeInsets.all(13) : EdgeInsets.zero,
      decoration: green
          ? BoxDecoration(
              color: const Color(0xFFF4FBF4),
              border: Border.all(color: const Color(0xFFCFE8CF)),
              borderRadius: BorderRadius.circular(10))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: green ? const Color(0xFF22702C) : kPrimary)),
          const SizedBox(height: 5),
          Text(text, style: const TextStyle(fontSize: 14.5, height: 1.55)),
        ],
      ),
    );
  }

  Widget _symbolsBlock(String symbols) {
    final lines = symbols.split('\n').where((l) => l.trim().isNotEmpty);
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('What the symbols mean',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: kPrimary)),
          const SizedBox(height: 5),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(displayText(line),
                  style: const TextStyle(fontSize: 14.5, height: 1.5)),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- syllabus page

class SyllabusPage extends StatelessWidget {
  final SyllabusItem item;
  const SyllabusPage({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kPrimaryDark,
        foregroundColor: Colors.white,
        title: const Text('Syllabus', style: TextStyle(fontSize: 17)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(item.title,
              style:
                  const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(item.content, style: const TextStyle(fontSize: 14.5, height: 1.6)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- browse page

/// Grouped browsing, like the old website's sidebar: groups (Basics, Units,
/// custom classes) → categories → sections. Tapping a category or section
/// jumps to the Home list with that filter applied.
class BrowsePage extends StatefulWidget {
  final VoidCallback onGo;
  const BrowsePage({super.key, required this.onGo});

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  final DataService _svc = DataService();
  SheetData? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bundled = await _svc.loadBundled();
    if (mounted) setState(() => _data = bundled);
    final cached = await _svc.loadCache();
    if (cached != null && mounted) setState(() => _data = cached);
    final fresh = await _svc.fetchNetwork();
    if (fresh != null && mounted) setState(() => _data = fresh);
  }

  void _go(String filter, String section) {
    BrowseSel.instance.go(filter, section);
    widget.onGo();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kPrimaryDark,
        foregroundColor: Colors.white,
        title: const Text('Browse by Topic'),
      ),
      body: data == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
              children: [
                Card(
                  color: const Color(0xFFEFEBFB),
                  elevation: 0,
                  child: ListTile(
                    leading: const Icon(Icons.library_books_outlined,
                        color: kPrimary),
                    title: const Text('All Formulas',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${data.entries.length} entries'),
                    trailing: const Icon(Icons.chevron_right, color: kPrimary),
                    onTap: () => _go('all', ''),
                  ),
                ),
                for (final g in _groups(data)) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 16, 6, 6),
                    child: Text(g.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: kPrimary)),
                  ),
                  for (final c in data.categories.where((c) => c.group == g))
                    _categoryTile(data, c),
                ],
              ],
            ),
    );
  }

  List<String> _groups(SheetData data) {
    final gs = <String>[];
    for (final c in data.categories) {
      if (!gs.contains(c.group)) gs.add(c.group);
    }
    return gs;
  }

  Widget _categoryTile(SheetData data, CategoryItem c) {
    final entries = data.entries.where((e) => e.category == c.slug).toList();
    final sections = <String, int>{};
    for (final e in entries) {
      if (e.section.isNotEmpty) {
        sections[e.section] = (sections[e.section] ?? 0) + 1;
      }
    }
    return Card(
      elevation: 0.5,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        shape: const Border(),
        leading: const Icon(Icons.folder_outlined, color: kPrimary),
        title: Text(c.title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: Text('${entries.length} entries'),
        children: [
          ListTile(
            dense: true,
            leading: const Icon(Icons.list, size: 19, color: kPrimary),
            title: Text('All of ${c.title}',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: kPrimary)),
            onTap: () => _go(c.slug, ''),
          ),
          for (final s in sections.entries)
            ListTile(
              dense: true,
              leading: const Icon(Icons.topic_outlined,
                  size: 19, color: Colors.black45),
              title: Text(s.key),
              trailing: Text('${s.value}',
                  style: const TextStyle(color: Colors.black45, fontSize: 12)),
              onTap: () => _go(c.slug, s.key),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- add hub

/// The "Add" tab: every add action in one place, login-gated like before.
class AddHubPage extends StatefulWidget {
  const AddHubPage({super.key});

  @override
  State<AddHubPage> createState() => _AddHubPageState();
}

class _AddHubPageState extends State<AddHubPage> {
  final DataService _svc = DataService();
  List<CategoryItem> _cats = const [];

  @override
  void initState() {
    super.initState();
    auth.addListener(_onAuth);
    _loadCats();
  }

  @override
  void dispose() {
    auth.removeListener(_onAuth);
    super.dispose();
  }

  void _onAuth() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCats() async {
    final d = await _svc.loadCache() ?? await _svc.loadBundled();
    if (mounted) setState(() => _cats = d.categories);
    final fresh = await _svc.fetchNetwork();
    if (fresh != null && mounted) setState(() => _cats = fresh.categories);
  }

  Future<void> _open(Widget page, {bool reload = false}) async {
    final changed = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => page));
    if (changed == true || reload) DataPing.instance.ping();
  }

  Future<void> _needLogin(String note, Widget page) async {
    if (!auth.isLoggedIn) {
      await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => AuthPage(note: note)));
      if (!auth.isLoggedIn || !mounted) return;
    }
    _open(page, reload: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kPrimaryDark,
        foregroundColor: Colors.white,
        title: const Text('Add'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          const Text(
            'Contribute to the sheet — add a formula, start a new class or category, or upload syllabus notes. Your name shows as the author.',
            style: TextStyle(fontSize: 13.5, color: Colors.black54, height: 1.5),
          ),
          const SizedBox(height: 14),
          _tile(
            icon: Icons.add_circle_outline,
            title: 'Add Formula',
            sub: 'A formula or a theory note — you can also scan a photo with AI',
            onTap: () => _needLogin(
              'Please log in to add a formula. Your existing website account works here.',
              FormulaFormPage(categories: _cats),
            ),
          ),
          _tile(
            icon: Icons.create_new_folder_outlined,
            title: 'Add Class / Category',
            sub: 'A new subject, class or topic group',
            onTap: () => _needLogin(
              'Please log in to add a class or category.',
              const CategoryFormPage(),
            ),
          ),
          _tile(
            icon: Icons.menu_book_outlined,
            title: 'Add Syllabus',
            sub: 'Syllabus notes for a class or category',
            onTap: () => _needLogin(
              'Please log in to add syllabus notes.',
              SyllabusFormPage(categories: _cats),
            ),
          ),
          if (!auth.isLoggedIn)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'You will be asked to log in first — adding is free for every student.',
                style: TextStyle(fontSize: 12.5, color: Colors.black45),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String sub,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0.5,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: kPrimary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(sub),
        trailing: const Icon(Icons.chevron_right, color: kPrimary),
        onTap: onTap,
      ),
    );
  }
}

// ---------------------------------------------------------------- more page

/// The "More" tab: account, your content, admin, contact.
class MorePage extends StatefulWidget {
  final VoidCallback onGoHome;
  const MorePage({super.key, required this.onGoHome});

  @override
  State<MorePage> createState() => _MorePageState();
}

class _MorePageState extends State<MorePage> {
  final DataService _svc = DataService();
  List<CategoryItem> _cats = const [];

  @override
  void initState() {
    super.initState();
    auth.addListener(_onAuth);
    _loadCats();
  }

  @override
  void dispose() {
    auth.removeListener(_onAuth);
    super.dispose();
  }

  void _onAuth() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCats() async {
    final d = await _svc.loadCache() ?? await _svc.loadBundled();
    if (mounted) setState(() => _cats = d.categories);
    final fresh = await _svc.fetchNetwork();
    if (fresh != null && mounted) setState(() => _cats = fresh.categories);
  }

  void _push(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = auth.isLoggedIn;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kPrimaryDark,
        foregroundColor: Colors.white,
        title: const Text('More'),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
            decoration: const BoxDecoration(
              gradient:
                  LinearGradient(colors: [kPrimaryDark, Color(0xFF5B21B6)]),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Maths Formula Sheet',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  loggedIn
                      ? '${auth.name.isEmpty ? auth.email : auth.name}${auth.isAdmin ? ' · Admin' : ''}'
                      : 'Read, understand, and add your own formulas',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          if (loggedIn)
            ListTile(
              leading: const Icon(Icons.list_alt_outlined),
              title:
                  Text(auth.isAdmin ? 'All Added Formulas' : 'My Formulas'),
              onTap: () async {
                final changed = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                        builder: (_) => MyFormulasPage(categories: _cats)));
                if (changed == true) DataPing.instance.ping();
              },
            ),
          if (auth.isAdmin)
            ListTile(
              leading: const Icon(Icons.dashboard_outlined),
              title: const Text('Admin Dashboard'),
              onTap: () => _push(const AdminPage()),
            ),
          if (loggedIn)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('My Profile'),
              onTap: () => _push(const ProfilePage()),
            )
          else
            ListTile(
              leading: const Icon(Icons.login),
              title: const Text('Login / Sign Up'),
              onTap: () => _push(const AuthPage()),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('Contact / Feedback / Support'),
            subtitle: const Text('Send us a message — it reaches us on email'),
            onTap: () => _push(const ContactPage()),
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('AI Tutor'),
            subtitle:
                const Text('Solve questions and understand any formula'),
            onTap: () => _push(const AiTutorPage()),
          ),
          ListTile(
            leading: const Icon(Icons.explore_outlined),
            title: const Text('Browse by Topic'),
            subtitle: const Text('Units, Basics and classes — section by section'),
            onTap: widget.onGoHome,
          ),
        ],
      ),
    );
  }
}
