import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
  '7': '⁷', '8': '⁸', '9': '⁹', '+': '⁺', '-': '⁻', '−': '⁻', 'n': 'ⁿ',
  'x': 'ˣ', 'i': 'ⁱ', '(': '⁽', ')': '⁾', '=': '⁼',
};
const Map<String, String> _subMap = {
  '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄', '5': '₅', '6': '₆',
  '7': '₇', '8': '₈', '9': '₉', '+': '₊', '-': '₋', '−': '₋', 'n': 'ₙ',
  'x': 'ₓ', 'i': 'ᵢ', '(': '₍', ')': '₎', '=': '₌',
};

String _script(String s, Map<String, String> map, String fallbackPrefix) {
  final buf = StringBuffer();
  for (final ch in s.split('')) {
    buf.write(map[ch] ?? ch);
  }
  final out = buf.toString();
  // If any character could not be converted, fall back to ^x / _x notation.
  return out == s && fallbackPrefix.isNotEmpty && s.length > 1
      ? '$fallbackPrefix$s'
      : out;
}

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
      home: const HomePage(),
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
  bool _online = false;

  @override
  void initState() {
    super.initState();
    _load();
    auth.addListener(_onAuth);
    auth.load();
  }

  @override
  void dispose() {
    auth.removeListener(_onAuth);
    super.dispose();
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
          '${e.name} ${e.section} ${catTitle[e.category] ?? ''} ${cleanBody(e.body)}'
              .toLowerCase();
      final tokens = raw
          .split(RegExp(r'\s+'))
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
              'Formula add karne ke liye pehle login karo. Account website wala hi chalega.',
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
                const SizedBox(height: 6),
                Expanded(
                  child: visible.isEmpty
                      ? const Center(
                          child: Text(
                              'No formula matched. Try a shorter search word.'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 2, 12, 16),
                          itemCount: visible.length +
                              ((!searching && data.syllabus.isNotEmpty) ? 1 : 0),
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
                      : 'Padho, samjho, aur apne formule jodo',
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
                'Formula add karne ke liye pehle login karo. Account website wala hi chalega.',
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
                'Class / category banane ke liye pehle login karo.',
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
                'Syllabus add karne ke liye pehle login karo.',
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
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }

  Widget _entryCard(EntryItem e, SheetData data) {
    final catTitle = data.categories
        .where((c) => c.slug == e.category)
        .map((c) => c.title)
        .firstOrNull;
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
          padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.name,
                        style: const TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w600)),
                    if (e.section.isNotEmpty)
                      Text(e.section,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black45)),
                    const SizedBox(height: 5),
                    Text(cleanBody(e.body),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14.5, height: 1.35)),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Row(children: [
                  Text('View',
                      style: TextStyle(
                          color: kPrimary, fontWeight: FontWeight.w600)),
                  Icon(Icons.chevron_right, color: kPrimary, size: 20),
                ]),
              ),
            ],
          ),
        ),
      ),
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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kPrimaryDark,
        foregroundColor: Colors.white,
        title: Text(entry.name, style: const TextStyle(fontSize: 17)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            entry.section.isEmpty
                ? categoryTitle
                : '$categoryTitle · ${entry.section}',
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF7C6AA8)),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              border: Border.all(color: const Color(0xFFD9D2F5)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              cleanBody(entry.body),
              textAlign:
                  entry.kind == 'theory' ? TextAlign.left : TextAlign.center,
              style: TextStyle(
                  fontSize: entry.kind == 'theory' ? 15.5 : 21, height: 1.5),
            ),
          ),
          const SizedBox(height: 16),
          if (about.isNotEmpty) _block('What is this formula for?', about),
          if (symbols.isNotEmpty) _symbolsBlock(symbols),
          if (example.isNotEmpty)
            _block('Example — how to use it', example, green: true),
          if (!hasDetail)
            const Text(
              'Is formula ki detail (matlab, symbols aur example) abhi jodi ja rahi hai — jald milegi.',
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
              child: Text(line,
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
