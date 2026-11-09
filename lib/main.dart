import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, rootBundle;
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_page.dart';
import 'contact_page.dart';
import 'features.dart';
import 'tracker.dart';
import 'pdf_export.dart' deferred as pdf_export;

const String kApiUrl = 'https://yashx.xyz/MathMitra/api/formulas';
const String kSiteUrl = 'https://yashx.xyz/MathMitra';
const String kAppVersion = '1.2.2';
const String kCacheKey = 'fs_api_cache_v1';
const Color kPrimary = Color(0xFF4338CA);
const Color kPrimaryDark = Color(0xFF2A1A5E);
const String kDisplayFont = 'Space Grotesk';
const LinearGradient kBrandGradient = LinearGradient(
  colors: [Color(0xFF2A1A5E), Color(0xFF4338CA), Color(0xFF7C3AED)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
const BoxDecoration kBarDecoration = BoxDecoration(gradient: kBrandGradient);
const LinearGradient kAccentGradient = LinearGradient(
  colors: [Color(0xFF4338CA), Color(0xFF8B5CF6)],
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
);
const LinearGradient kAmberGradient = LinearGradient(
  colors: [Color(0xFFF59E0B), Color(0xFFF97316)],
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
);

/// Display style for formulas and headings — Space Grotesk with Inter as
/// fallback for any glyph it lacks (some superscript letters).
TextStyle displayStyle({
  double size = 16,
  FontWeight weight = FontWeight.w600,
  Color? color,
  double height = 1.4,
}) {
  return TextStyle(
    fontFamily: kDisplayFont,
    fontFamilyFallback: const ['Inter'],
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
  );
}

/// Secondary text colour that adapts to the theme (the hardcoded
/// Colors.black54 subtitles used across the app vanish on dark surfaces).
Color subtleColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? Colors.white60
        : Colors.black54;

/// Title ink: deep navy on light surfaces, soft lavender-white on dark
/// (the hardcoded navy/indigo text colours are unreadable on dark cards).
Color inkColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFE7E3FF)
        : const Color(0xFF1E1B4B);

/// Maths-themed loading animation — bouncing symbols (∫ π √ Σ ∞ x²)
/// instead of the classic spinner, for full-screen loading states.
class MathLoader extends StatefulWidget {
  final String label;
  final bool showIcon;
  const MathLoader(
      {super.key, this.label = 'Loading MathMitra…', this.showIcon = false});

  @override
  State<MathLoader> createState() => _MathLoaderState();
}

class _MathLoaderState extends State<MathLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1300))
    ..repeat();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  static const _symbols = ['∫', 'π', '√', 'Σ', '∞', 'x²'];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showIcon) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset('assets/icon.png', width: 86, height: 86),
            ),
            const SizedBox(height: 18),
          ],
          AnimatedBuilder(
            animation: _ctl,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _symbols.length; i++)
                  _symbol(i),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(widget.label,
              style: TextStyle(fontSize: 13.5, color: subtleColor(context))),
        ],
      ),
    );
  }

  Widget _symbol(int i) {
    final local = (_ctl.value - i / _symbols.length) % 1.0;
    final bounce = local <= 0 ? 0.0 : (local >= 1 ? 0.0 : _hump(local));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Transform.translate(
        offset: Offset(0, -10 * bounce),
        child: Opacity(
          opacity: 0.35 + 0.65 * bounce,
          child: Text(
            _symbols[i],
            style: TextStyle(
              fontFamily: kDisplayFont,
              fontSize: 29,
              fontWeight: FontWeight.w700,
              color: i.isEven ? kPrimary : const Color(0xFF8B5CF6),
            ),
          ),
        ),
      ),
    );
  }

  double _hump(double t) {
    // smooth 0 -> 1 -> 0 over t in [0,1]
    return (1 - (2 * t - 1).abs());
  }
}

/// Formula ink: dark indigo on light surfaces, light lavender on dark.
Color formulaInk(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFD9D2FF)
        : const Color(0xFF26215C);

/// Brand accent for headings and markers: kPrimary on light surfaces,
/// a brighter indigo on dark (kPrimary itself is too dark to read there).
Color brandInk(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFB7AEFF)
        : kPrimary;

/// One-time entrance animation (fade + rise) for list cards — each entry
/// animates only the first time it appears in a session.
class Entrance extends StatefulWidget {
  final String id;
  final Widget child;
  const Entrance({super.key, required this.id, required this.child});

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  static final Set<String> _seen = {};
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    if (!_seen.contains(widget.id)) {
      _seen.add(widget.id);
      _ctrl = AnimationController(
          vsync: this, duration: const Duration(milliseconds: 380))
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctrl;
    if (c == null) return widget.child;
    return AnimatedBuilder(
      animation: c,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(c.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 16 * (1 - t)), child: child),
        );
      },
    );
  }
}

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
  // HTML tables: keep the grid readable as plain text (list previews,
  // PDF, share) — one row per line, cells separated by " · ". The
  // detail page renders a real grid via parseTable() instead.
  s = s.replaceAll(RegExp(r'</tr\s*>\n?', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'</t[dh]\s*>', caseSensitive: false), ' · ');
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');
  // Wide &nbsp; runs are segment separators in a few packed bodies
  // ("Sum of roots: ...   Product of roots: ...") — turn them into
  // line breaks so the parts don't run together in lists or on the
  // detail page. A single &nbsp; stays a normal space.
  s = s.replaceAll(RegExp(r'(&nbsp;\s*){2,}'), '\n');
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&gt;', '>')
      .replaceAll('&lt;', '<')
      .replaceAll('&amp;', '&')
      .replaceAll('&minus;', '−');
  s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
  s = s.replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n');
  // Drop the dangling cell separator at the end of table rows.
  s = s.split('\n').map((l) => l.replaceAll(RegExp(r'[\s·]+$'), '')).join('\n');
  return s.trim();
}

/// Parses an HTML <table> body into rows of cleaned cell text.
/// Returns an empty list when the body holds no usable table.
List<List<String>> parseTable(String html) {
  final rows = <List<String>>[];
  for (final tr in RegExp(r'<tr[^>]*>(.*?)</tr>',
          dotAll: true, caseSensitive: false)
      .allMatches(html)) {
    final cells = <String>[];
    for (final td in RegExp(r'<t[hd][^>]*>(.*?)</t[hd]>',
            dotAll: true, caseSensitive: false)
        .allMatches(tr[1]!)) {
      cells.add(cleanBody(td[1]!));
    }
    if (cells.isNotEmpty) rows.add(cells);
  }
  return rows;
}

/// A real grid for table-kind entries (e.g. the trigonometry
/// standard-values table), drawn inside the detail page's card.
/// Scrolls sideways on narrow screens instead of squeezing cells.
class FormulaTable extends StatelessWidget {
  final List<List<String>> rows;
  final bool compact;
  const FormulaTable({super.key, required this.rows, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final cols =
        rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    final cs = Theme.of(context).colorScheme;
    if (compact) {
      return Table(
        columnWidths: {
          for (var i = 0; i < cols; i++) i: const FlexColumnWidth()
        },
        border: TableBorder.all(
            color: Theme.of(context).dividerColor, width: 0.5),
        children: [
          for (var r = 0; r < rows.length; r++)
            TableRow(
              decoration: r == 0
                  ? BoxDecoration(color: kPrimary.withValues(alpha: 0.10))
                  : null,
              children: [
                for (var c = 0; c < cols; c++)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                    child: Text(
                      c < rows[r].length ? rows[r][c] : '',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.25,
                        fontWeight: (r == 0 || c == 0)
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      );
    }
    return LayoutBuilder(builder: (context, box) {
      final wanted = cols * 62.0;
      final width = wanted > box.maxWidth ? wanted : box.maxWidth;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: Table(
            columnWidths: {
              for (var i = 0; i < cols; i++) i: const FlexColumnWidth()
            },
            border: TableBorder.all(
                color: Theme.of(context).dividerColor, width: 0.7),
            children: [
              for (var r = 0; r < rows.length; r++)
                TableRow(
                  decoration: r == 0
                      ? BoxDecoration(
                          color: kPrimary.withValues(alpha: 0.10))
                      : null,
                  children: [
                    for (var c = 0; c < cols; c++)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 6),
                        child: Text(
                          c < rows[r].length ? rows[r][c] : '',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.3,
                            fontWeight: (r == 0 || c == 0)
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      );
    });
  }
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

final RegExp _htmlTagRe =
    RegExp(r'</?(span|sup|sub|p|b|i|div|br|table|thead|tbody|tr|td|th)[\s>/]');

/// Renders any stored body/text (HTML for built-in entries, FormulaText for
/// user entries and detail fields) as clean book-style plain text.
/// Note: a plain "<" (as in "D < 0") must NOT trigger the HTML path — only
/// real tags do, otherwise caret powers like x^{2} leak through raw.
String displayText(String s) {
  final n = s.replaceAll('\\n', '\n');
  if (_htmlTagRe.hasMatch(n) || n.contains('&nbsp;')) return cleanBody(n);
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


/// Removes a repeated entry title from the start of a body text. Many
/// theory bodies begin with their own name followed by ':' — the page
/// already shows the name as its heading, so the repeat is dropped. Only
/// strips when the name is followed by ':', '—' or a line break, so a
/// formula that merely starts with the same letters is never touched.
String stripTitlePrefix(String text, List<String> names) {
  var t = text.trim();
  for (final raw in names) {
    final name = raw.trim();
    if (name.isEmpty || t.length <= name.length) continue;
    if (!t.toLowerCase().startsWith(name.toLowerCase())) continue;
    final rest = t.substring(name.length);
    if (rest.startsWith(':') || rest.startsWith('—') || rest.startsWith('\n')) {
      final cleaned = rest.replaceAll(RegExp(r'^[:—\s]+'), '').trim();
      if (cleaned.isNotEmpty) return cleaned;
    }
  }
  return t;
}

/// One display line of a structured text block. [marker] is '' for a plain
/// line, '•' for a bullet, or '1', '2', … for a numbered point.
class TextLine {
  final String text;
  final String marker;
  const TextLine(this.text, this.marker);
}

List<String> _splitSentences(String p) {
  const abbrev = {'e.g', 'i.e', 'vs', 'approx', 'Fig', 'Dr', 'Mr', 'St', 'No'};
  final out = <String>[];
  var start = 0;
  var i = 0;
  while (i < p.length - 1) {
    final c = p[i];
    if ((c == '.' || c == '!' || c == '?') && p[i + 1] == ' ') {
      final before = p.substring(start, i).trimRight();
      final lastWord = before.isEmpty ? '' : before.split(RegExp(r'\s+')).last;
      final j = i + 2;
      if (!abbrev.contains(lastWord) &&
          j < p.length &&
          RegExp(r'[A-Z0-9(|]').hasMatch(p[j])) {
        out.add(p.substring(start, i + 1).trim());
        start = j;
        i = j;
        continue;
      }
    }
    i++;
  }
  final tail = p.substring(start).trim();
  if (tail.isNotEmpty) out.add(tail);
  return out;
}

final RegExp _numMarkRe = RegExp(r'\((\d{1,2})\)\s*');

/// Breaks a wall-of-text block into readable lines: numbered points
/// (1) (2) … become separate numbered lines, ' | ' clusters become
/// bullets, and long prose is split one sentence per bullet line. Lines
/// that are already separate points become bullets too.
List<TextLine> structuredLines(String text) {
  final out = <TextLine>[];
  for (final para in text.split('\n')) {
    final p = para.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (p.isEmpty) continue;
    final marks = _numMarkRe.allMatches(p).toList();
    var sequential = marks.length >= 2 && marks.first.start <= p.length * 0.45;
    if (sequential) {
      for (var k = 0; k < marks.length; k++) {
        if (int.parse(marks[k].group(1)!) != k + 1) {
          sequential = false;
          break;
        }
      }
    }
    if (sequential) {
      final intro = p.substring(0, marks.first.start).trim();
      if (intro.isNotEmpty) out.add(TextLine(intro, ''));
      for (var k = 0; k < marks.length; k++) {
        final from = marks[k].end;
        final to = k + 1 < marks.length ? marks[k + 1].start : p.length;
        final seg =
            p.substring(from, to).trim().replaceAll(RegExp(r'[;\s]+$'), '');
        if (seg.isNotEmpty) out.add(TextLine(seg, '${k + 1}'));
      }
      continue;
    }
    final pipes = p.split(' | ');
    if (pipes.length >= 3) {
      for (final seg in pipes) {
        final s = seg.trim();
        if (s.isNotEmpty) out.add(TextLine(s, '•'));
      }
      continue;
    }
    if (p.length > 200) {
      final sents = _splitSentences(p);
      if (sents.length >= 3) {
        for (final s in sents) {
          out.add(TextLine(s, '•'));
        }
        continue;
      }
    }
    out.add(TextLine(p, ''));
  }
  // A block of 3+ plain lines reads better as bullets (e.g. a properties
  // list where every line is already its own point) — except a first line
  // that is clearly a lead-in ending with ':'.
  final hasNumbered = out.any((l) => l.marker.isNotEmpty && l.marker != '•');
  if (!hasNumbered && out.length >= 3) {
    for (var i = 0; i < out.length; i++) {
      if (out[i].marker.isEmpty &&
          !(i == 0 && out[i].text.trim().endsWith(':'))) {
        out[i] = TextLine(out[i].text, '•');
      }
    }
  }
  return out;
}

/// structuredLines as one plain string (for list cards and the PDF).
String structuredPlain(String text) {
  return structuredLines(text)
      .map((l) => l.marker.isEmpty
          ? l.text
          : (l.marker == '•' ? '• ${l.text}' : '${l.marker}. ${l.text}'))
      .join('\n');
}

/// Renders text as structured lines — numbered points and bullets get an
/// indigo marker column instead of running together as one paragraph.
class StructuredText extends StatelessWidget {
  final String text;
  final TextStyle style;
  const StructuredText({super.key, required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    final lines = structuredLines(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: l.marker.isEmpty
                ? Text(l.text, style: style)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 20,
                        child: Text(
                          l.marker == '•' ? '•' : '${l.marker}.',
                          style: style.copyWith(
                              fontWeight: FontWeight.w800, color: brandInk(context)),
                        ),
                      ),
                      Expanded(child: Text(l.text, style: style)),
                    ],
                  ),
          ),
      ],
    );
  }
}

/// Small kind chip for a card / detail page. Theory entries whose name
/// starts with PROPERTIES or RULE get their own label and colour, so the
/// kinds read differently at a glance while scrolling.
Widget kindBadge(String kind, String rawName) {
  var label = 'Formula';
  var bg = const [Color(0xFFE9E5FC), Color(0xFFD9D2F5)];
  var fg = const Color(0xFF4A3A9E);
  final up = rawName.trim().toUpperCase();
  if (kind == 'table') {
    label = 'Table';
    bg = const [Color(0xFFFFF1CF), Color(0xFFFFE3A3)];
    fg = const Color(0xFF8A6D00);
  } else if (kind == 'theory') {
    label = 'Theory';
    bg = const [Color(0xFFFFF1CF), Color(0xFFFFE3A3)];
    fg = const Color(0xFF8A6D00);
    if (up.startsWith('PROPERTIES')) {
      label = 'Properties';
      bg = const [Color(0xFFCCFBF1), Color(0xFF99F6E4)];
      fg = const Color(0xFF0F766E);
    } else if (up.startsWith('RULE')) {
      label = 'Rule';
      bg = const [Color(0xFFFFE4E6), Color(0xFFFECDD3)];
      fg = const Color(0xFF9F1239);
    }
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: bg),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label,
        style:
            TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
  );
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

final Map<String, String> _revSup = {
  for (final e in _supMap.entries) e.value: e.key
};
final Map<String, String> _revSub = {
  for (final e in _subMap.entries) e.value: e.key
};

/// Search skeleton: flattens a formula or a typed query into one comparable
/// string — spaces removed, superscripts/subscripts folded to their base
/// letters, ^ _ { } dropped, × read as x, π as pi, √ as sqrt. This is what
/// lets "(a+b)²", "(a+b)^2" and "a+b2" all find the same entry.
String skeleton(String s) {
  final buf = StringBuffer();
  for (final ch in s.split('')) {
    if (ch == ' ' || ch == '\n' || ch == '\t') continue;
    final sup = _revSup[ch];
    if (sup != null) {
      buf.write(sup);
      continue;
    }
    final sub = _revSub[ch];
    if (sub != null) {
      buf.write(sub);
      continue;
    }
    switch (ch) {
      case '^':
      case '_':
      case '{':
      case '}':
        continue;
      case '−':
        buf.write('-');
        continue;
      case '×':
        buf.write('x');
        continue;
      case '·':
      case '•':
        continue;
      case 'π':
        buf.write('pi');
        continue;
      case '√':
        buf.write('sqrt');
        continue;
      default:
        buf.write(ch.toLowerCase());
    }
  }
  return buf.toString();
}

/// Shares an entry (system share sheet where available, clipboard fallback).
Future<void> shareEntry(
    BuildContext context, EntryItem e, Map<String, dynamic> details) async {
  final text = '${displayName(e, details)}\n'
      '${displayText(e.body)}\n\n'
      '— MathMitra\n'
      '$kSiteUrl';
  Tracker.instance.share(displayName(e, details));
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

/// Light / dark theme preference, persisted on the device.
class ThemeController extends ChangeNotifier {
  ThemeMode mode = ThemeMode.system;
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString('mm_theme_mode');
      mode = v == 'dark'
          ? ThemeMode.dark
          : v == 'light'
              ? ThemeMode.light
              : ThemeMode.system;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> set(ThemeMode m) async {
    mode = m;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mm_theme_mode',
          m == ThemeMode.dark ? 'dark' : m == ThemeMode.light ? 'light' : 'system');
    } catch (_) {}
  }
}

final ThemeController themeCtl = ThemeController();

NavigationBarThemeData _navTheme(Color bg, Color indicator, Color selected, Color unselected) {
  return NavigationBarThemeData(
    backgroundColor: bg,
    indicatorColor: indicator,
    labelTextStyle: WidgetStateProperty.all(const TextStyle(
        fontFamily: kDisplayFont, fontSize: 12, fontWeight: FontWeight.w600)),
    iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
        color: states.contains(WidgetState.selected) ? selected : unselected)),
  );
}

class FormulaApp extends StatefulWidget {
  const FormulaApp({super.key});

  @override
  State<FormulaApp> createState() => _FormulaAppState();
}

class _FormulaAppState extends State<FormulaApp> {
  @override
  void initState() {
    super.initState();
    themeCtl.load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeCtl,
      builder: (context, _) => MaterialApp(
        title: 'MathMitra',
        debugShowCheckedModeBanner: false,
        themeMode: themeCtl.mode,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: kPrimary),
          useMaterial3: true,
          fontFamily: 'Inter',
          scaffoldBackgroundColor: const Color(0xFFF6F5FB),
          navigationBarTheme: _navTheme(Colors.white,
              const Color(0xFFE3DEFA), kPrimary, Colors.black54),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
                  seedColor: kPrimary, brightness: Brightness.dark)
              .copyWith(
            // Grey family surfaces — the old near-black felt too dark.
            surface: const Color(0xFF26262E),
            surfaceContainerLowest: const Color(0xFF1C1C22),
            surfaceContainerLow: const Color(0xFF222228),
            surfaceContainer: const Color(0xFF26262E),
            surfaceContainerHigh: const Color(0xFF2E2E37),
            surfaceContainerHighest: const Color(0xFF383842),
          ),
          useMaterial3: true,
          fontFamily: 'Inter',
          scaffoldBackgroundColor: const Color(0xFF1C1C22),
          navigationBarTheme: _navTheme(const Color(0xFF26262E),
              const Color(0xFF3730A3), const Color(0xFFA5B4FC), Colors.white54),
        ),
        home: const MainShell(),
      ),
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
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _searchFocus = FocusNode();
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    auth.addListener(_onAuth);
    auth.load();
    library.init();
    noticesSvc.init().then((_) {
      if (mounted) maybeShowNoticePopups(context);
    });
    Tracker.instance.start();
    BrowseSel.instance.addListener(_onBrowse);
    DataPing.instance.addListener(_refreshData);
  }

  @override
  void dispose() {
    auth.removeListener(_onAuth);
    BrowseSel.instance.removeListener(_onBrowse);
    DataPing.instance.removeListener(_refreshData);
    _scrollCtrl.dispose();
    _searchFocus.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Slim-bar search icon: scroll back up to the hero and focus the field.
  void _focusSearch() {
    if (_scrollCtrl.hasClients && _scrollCtrl.offset > 4) {
      _scrollCtrl.animateTo(0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic);
      Future.delayed(const Duration(milliseconds: 380), () {
        if (mounted) _searchFocus.requestFocus();
      });
    } else {
      _searchFocus.requestFocus();
    }
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
      setState(() => _data = fresh);
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
      setState(() => _data = fresh);
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
      // 1) Formula-shaped queries ("(a+b)²", "(a+b)^2", "a2+b2") match on the
      // flattened skeleton of the name + formula text.
      final qSkel = skeleton(raw);
      // 2) Word queries rank by WHERE the words hit: name > section > body.
      const stopwords = {'of', 'the', 'a', 'an', 'and', 'for', 'to', 'in'};
      final tokens = raw
          .split(RegExp(r'\s+'))
          .where((t) => !stopwords.contains(t))
          .map((t) =>
              (t.length > 3 && t.endsWith('s')) ? t.substring(0, t.length - 1) : t)
          .where((t) => t.length >= 2)
          .toList();
      // Very short queries ("g") used to return nothing at all: the
      // token filter above drops 1-letter words and the skeleton match
      // needed 3+ characters. They get their own matching below.
      final shortQ =
          tokens.isEmpty ? raw.replaceAll(RegExp(r'[^a-z0-9]'), '') : '';

      final scored = <(EntryItem, int, int, int)>[]; // entry, skelHit, matched, score
      for (final e in list) {
        final name = displayName(e, _details).toLowerCase();
        final mid = '${e.section} ${catTitle[e.category] ?? ''}'.toLowerCase();
        final body = displayText(e.body).toLowerCase();
        final skelHit = (qSkel.length >= 2 &&
                skeleton('$name $body').contains(qSkel))
            ? 1
            : 0;
        var matched = 0;
        var score = 0;
        for (final t in tokens) {
          var hit = false;
          if (name.contains(t)) {
            score += 3;
            hit = true;
          }
          if (mid.contains(t)) {
            score += 2;
            hit = true;
          }
          if (body.contains(t)) {
            score += 1;
            hit = true;
          }
          if (hit) matched++;
        }
        if (shortQ.length == 1) {
          final c = shortQ;
          bool startsWord(String text) => text
              .split(RegExp(r'[^a-z0-9]+'))
              .any((w) => w.startsWith(c));
          if (startsWord(name)) {
            score += 3;
            matched = 1;
          } else if (startsWord(mid)) {
            score += 2;
            matched = 1;
          } else if (body.contains(' $c ') ||
              body.contains('$c(') ||
              body.contains('$c =')) {
            score += 1;
            matched = 1;
          }
        }
        if (skelHit == 1 || matched > 0) {
          scored.add((e, skelHit, matched, score));
        }
      }
      scored.sort((a, b) {
        if (a.$2 != b.$2) return b.$2.compareTo(a.$2); // skeleton hits first
        if (a.$3 != b.$3) return b.$3.compareTo(a.$3); // then most words hit
        return b.$4.compareTo(a.$4); // then best-weighted score
      });
      list = scored.map((s) => s.$1).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final visible = _visible;
    final searching = _query.trim().isNotEmpty;
    return Scaffold(
      drawer: _drawer(),
      body: data == null
          ? const MathLoader(showIcon: true)
          : CustomScrollView(
              controller: _scrollCtrl,
              slivers: [
                // Big hero at the top; on scroll it collapses to a slim
                // pinned strip: menu · MathMitra · search · add.
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 158,
                  toolbarHeight: 54,
                  backgroundColor: kPrimaryDark,
                  foregroundColor: Colors.white,
                  title: Text('MathMitra',
                      style: displayStyle(
                          size: 18,
                          weight: FontWeight.w700,
                          color: Colors.white)),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.search),
                      tooltip: 'Search',
                      onPressed: _focusSearch,
                    ),
                    ListenableBuilder(
                      listenable: noticesSvc,
                      builder: (context, _) => IconButton(
                        icon: Badge(
                          isLabelVisible: noticesSvc.unread > 0,
                          label: Text('${noticesSvc.unread}'),
                          child:
                              const Icon(Icons.notifications_none_outlined),
                        ),
                        tooltip: 'Notices',
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const NoticesPage())),
                      ),
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: const BoxDecoration(gradient: kBrandGradient),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Find any formula.',
                                style: displayStyle(
                                    size: 24,
                                    weight: FontWeight.w700,
                                    color: Colors.white)),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _searchCtrl,
                              focusNode: _searchFocus,
                              style: TextStyle(
                                  fontSize: 15,
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white
                                      : const Color(0xFF16130E)),
                              decoration: InputDecoration(
                                hintText: 'Search',
                                hintStyle: TextStyle(
                                    color: subtleColor(context), fontSize: 14),
                                prefixIcon: Icon(Icons.search,
                                    color: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? const Color(0xFFA5B4FC)
                                        : kPrimary),
                                filled: true,
                                fillColor: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? const Color(0xFF2E2E37)
                                    : Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                              ),
                              onChanged: (v) => setState(() => _query = v),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 46,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: [
                            _chip('all', 'All Formulas'),
                            _chip('basics', 'All Basics'),
                            for (final c in data.categories)
                              _chip(c.slug, c.title),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          searching
                              ? 'Showing ${visible.length} of ${data.entries.length} entries for "${_query.trim()}"'
                              : 'Showing ${visible.length} of ${data.entries.length} entries',
                          style: TextStyle(
                              fontSize: 13, color: subtleColor(context)),
                        ),
                      ),
                      if (_sectionFilter.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                          child: InputChip(
                            avatar: const Icon(Icons.topic_outlined, size: 16),
                            label: Text('Section: $_sectionFilter'),
                            onDeleted: () =>
                                setState(() => _sectionFilter = ''),
                            deleteIconColor: kPrimary,
                          ),
                        ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
                if (visible.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                        child: Text(
                            'No formula matched. Try a shorter search word.')),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 16),
                    sliver: SliverList.builder(
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child:
                      Image.asset('assets/icon.png', width: 46, height: 46),
                ),
                const SizedBox(height: 10),
                const Text('MathMitra',
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
          ListTile(
            leading: const Icon(Icons.folder_special_outlined),
            title: const Text('My Library'),
            onTap: () {
              Navigator.pop(context);
              _open(const LibraryPage());
            },
          ),
          ListTile(
            leading: const Icon(Icons.campaign_outlined),
            title: const Text('Notices'),
            onTap: () {
              Navigator.pop(context);
              _open(const NoticesPage());
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
    final fullText = isTheory || e.kind == 'table';
    void openDetail() {
      Tracker.instance.formulaView(e.name, e.category);
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DetailPage(
            entry: e,
            categoryTitle: catTitle ?? e.category,
            details: _details),
      ));
    }
    return Entrance(
      id: e.id,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
                color: Color(0x143D2C8F), blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: openDetail,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 4.5,
                    decoration: BoxDecoration(
                        gradient: fullText ? kAmberGradient : kAccentGradient),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(13, 12, 8, 9),
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
                                        style: displayStyle(
                                            size: 16.5,
                                            weight: FontWeight.w700,
                                            color: inkColor(context))),
                                    const SizedBox(height: 2),
                                    Text(
                                      [
                                        if (catTitle != null) catTitle,
                                        if (e.section.isNotEmpty) e.section,
                                      ].join(' · '),
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          color: subtleColor(context)),
                                    ),
                                  ],
                                ),
                              ),
                              kindBadge(e.kind, displayText(e.name)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Theory entries show their FULL text in the list;
                          // formulas get a compact preview. Table entries
                          // render their real grid right here on the card.
                          if (e.kind == 'table' &&
                              parseTable(e.body).length > 1)
                            FormulaTable(
                                rows: parseTable(e.body), compact: true)
                          else
                            Text(
                            fullText
                                ? structuredPlain(stripTitlePrefix(
                                    displayText(e.body),
                                    [displayText(e.name), displayName(e, _details)]))
                                : stripTitlePrefix(displayText(e.body),
                                    [displayText(e.name), displayName(e, _details)]),
                            maxLines: fullText ? null : 3,
                            overflow: fullText
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            style: fullText
                                ? TextStyle(
                                    fontSize: 14,
                                    height: 1.5,
                                    color: Theme.of(context).colorScheme.onSurface)
                                : displayStyle(
                                    size: 15.5,
                                    weight: FontWeight.w500,
                                    color: formulaInk(context),
                                    height: 1.45),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (e.userAdded && e.authorName.isNotEmpty)
                                Expanded(
                                  child: Text('by ${e.authorName}',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          color: subtleColor(context))),
                                )
                              else
                                const Spacer(),
                              ListenableBuilder(
                                listenable: library,
                                builder: (context, _) => IconButton(
                                  icon: Icon(
                                      library.isFavorite(e.id)
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      size: 19),
                                  color: library.isFavorite(e.id)
                                      ? const Color(0xFFE0245E)
                                      : kPrimary,
                                  tooltip: 'Favourite',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => library.toggleFavorite(e),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.share_outlined,
                                    size: 19),
                                color: kPrimary,
                                tooltip: 'Share',
                                visualDensity: VisualDensity.compact,
                                onPressed: () =>
                                    shareEntry(context, e, _details),
                              ),
                              Material(
                                color: kPrimary,
                                borderRadius: BorderRadius.circular(20),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: openDetail,
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 13, vertical: 6),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text('View',
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w600)),
                                        Icon(Icons.chevron_right,
                                            size: 16, color: Colors.white),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
                  style: displayStyle(size: 15, weight: FontWeight.w600)),
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
        flexibleSpace: Container(decoration: kBarDecoration),
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
            style: displayStyle(
                size: 23, weight: FontWeight.w700, color: inkColor(context)),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              kindBadge(entry.kind, displayText(entry.name)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.section.isEmpty
                      ? categoryTitle
                      : '$categoryTitle · ${entry.section}',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFFBBAEF2)
                          : const Color(0xFF7C6AA8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child:
                  Transform.scale(scale: 0.97 + 0.03 * t, child: child),
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: Theme.of(context).brightness == Brightness.dark
                      ? const [Color(0xFF2A2470), Color(0xFF1B1748)]
                      : const [Color(0xFFEEF2FF), Color(0xFFE7E0FC)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF4A3FA0)
                        : const Color(0xFFCFC4F2)),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x1A3D2C8F),
                      blurRadius: 14,
                      offset: Offset(0, 5)),
                ],
              ),
              child: entry.kind == 'table' &&
                      parseTable(entry.body).length > 1
                  ? FormulaTable(rows: parseTable(entry.body))
                  : entry.kind == 'theory'
                  ? StructuredText(
                      text: stripTitlePrefix(displayText(entry.body),
                          [displayText(entry.name), name]),
                      style: TextStyle(
                        fontSize: 15.5,
                        height: 1.55,
                        color: Theme.of(context).colorScheme.onSurface),
                    )
                  : Text(
                      stripTitlePrefix(displayText(entry.body),
                          [displayText(entry.name), name]),
                      textAlign: entry.kind == 'table'
                          ? TextAlign.left
                          : TextAlign.center,
                      style: entry.kind == 'table'
                          ? TextStyle(
                        fontSize: 15.5,
                        height: 1.55,
                        color: Theme.of(context).colorScheme.onSurface)
                          : displayStyle(
                              size: 21,
                              weight: FontWeight.w600,
                              color: formulaInk(context),
                              height: 1.5),
                    ),
            ),
          ),
          if (entry.userAdded && entry.authorName.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Added by ${entry.authorName}'
              '${entry.authorEmail.isNotEmpty ? ' (${entry.authorEmail})' : ''}'
              '${entry.createdAt.isNotEmpty ? ' · ${fmtIst(entry.createdAt)}' : ''}',
              style: TextStyle(fontSize: 12, color: subtleColor(context)),
            ),
          ],
          const SizedBox(height: 12),
          ListenableBuilder(
            listenable: library,
            builder: (context, _) {
              final fav = library.isFavorite(entry.id);
              return Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => library.toggleFavorite(entry),
                      icon: Icon(
                          fav ? Icons.favorite : Icons.favorite_border,
                          size: 18,
                          color: fav ? const Color(0xFFE0245E) : null),
                      label: Text(fav ? 'Favourited' : 'Favourite'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => showFolderPicker(context, entry),
                      icon: const Icon(Icons.folder_open_outlined, size: 18),
                      label: const Text('Add to Folder'),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: kBrandGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x333D2C8F),
                    blurRadius: 10,
                    offset: Offset(0, 4)),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () =>
                    openFormulaAi(context, entry, details, categoryTitle),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 13),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.auto_awesome, size: 18, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Ask AI about this formula',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (about.isNotEmpty)
            _block(context, 'What is this formula for?', displayText(about)),
          if (symbols.isNotEmpty) _symbolsBlock(context, symbols),
          if (example.isNotEmpty)
            _block(context, 'Example — how to use it', displayText(example),
                green: true),
          if (!hasDetail)
            Text(
              'Details for this one (meaning, symbols and a solved example) are being added — check back soon.',
              style: TextStyle(color: subtleColor(context), fontSize: 13.5),
            ),
        ],
      ),
    );
  }

  Widget _block(BuildContext context, String title, String text, {bool green = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 13),
      padding:
          green ? const EdgeInsets.all(13) : EdgeInsets.zero,
      decoration: green
          ? BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF12271A)
                  : const Color(0xFFF4FBF4),
              border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF2E5339)
                      : const Color(0xFFCFE8CF)),
              borderRadius: BorderRadius.circular(10))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: displayStyle(
                  size: 14.5,
                  weight: FontWeight.w700,
                  color: green
                      ? (Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF86D997)
                          : const Color(0xFF22702C))
                      : brandInk(context))),
          const SizedBox(height: 5),
          StructuredText(
              text: text,
              style: const TextStyle(fontSize: 14.5, height: 1.55)),
        ],
      ),
    );
  }

  Widget _symbolsBlock(BuildContext context, String symbols) {
    final parts = <String>[];
    for (final line in displayText(symbols).split('\n')) {
      var segs = line
          .split(';')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (segs.length == 1) {
        final s = segs[0];
        if (' = '.allMatches(s).length >= 3 && s.contains(', ')) {
          segs = s
              .split(', ')
              .map((x) => x.trim())
              .where((x) => x.isNotEmpty)
              .toList();
        } else if (s.contains(' · ')) {
          segs = s
              .split(' · ')
              .map((x) => x.trim())
              .where((x) => x.isNotEmpty)
              .toList();
        }
      }
      parts.addAll(segs);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What the symbols mean',
              style: displayStyle(
                  size: 14.5, weight: FontWeight.w700, color: brandInk(context))),
          const SizedBox(height: 5),
          for (final p in parts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: _symbolRow(context, p),
            ),
        ],
      ),
    );
  }

  Widget _symbolRow(BuildContext context, String p) {
    const style = TextStyle(fontSize: 14.5, height: 1.5);
    var cut = p.indexOf(' = ');
    if (cut < 0) cut = p.indexOf(' ≈ ');
    if (cut <= 0 || cut > 24) return Text(p, style: style);
    return RichText(
      text: TextSpan(
        style: style.copyWith(color: Theme.of(context).colorScheme.onSurface),
        children: [
          TextSpan(
              text: p.substring(0, cut),
              style: displayStyle(
                  size: 14.5, weight: FontWeight.w700, color: brandInk(context))),
          TextSpan(text: p.substring(cut)),
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
        flexibleSpace: Container(decoration: kBarDecoration),
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
        flexibleSpace: Container(decoration: kBarDecoration),
        foregroundColor: Colors.white,
        title: const Text('Browse by Topic'),
      ),
      body: data == null
          ? const MathLoader()
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
              children: [
                Card(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Theme.of(context).colorScheme.surfaceContainerHighest
                      : const Color(0xFFEFEBFB),
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
              leading: Icon(Icons.topic_outlined,
                  size: 19, color: subtleColor(context)),
              title: Text(s.key),
              trailing: Text('${s.value}',
                  style: TextStyle(color: subtleColor(context), fontSize: 12)),
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
        flexibleSpace: Container(decoration: kBarDecoration),
        foregroundColor: Colors.white,
        title: const Text('Add'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Text(
            'Add formulas, classes and syllabus notes — your name shows as the author.',
            style: TextStyle(fontSize: 13.5, color: subtleColor(context), height: 1.5),
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
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'You will be asked to log in first — adding is free for every student.',
                style: TextStyle(fontSize: 12.5, color: subtleColor(context)),
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
  SheetData? _data;
  Map<String, dynamic> _details = {};
  bool _pdfBusy = false;

  @override
  void initState() {
    super.initState();
    auth.addListener(_onAuth);
    _loadData();
  }

  @override
  void dispose() {
    auth.removeListener(_onAuth);
    super.dispose();
  }

  void _onAuth() {
    if (mounted) setState(() {});
  }

  Future<void> _loadData() async {
    final d = await _svc.loadCache() ?? await _svc.loadBundled();
    if (mounted) {
      setState(() {
        _cats = d.categories;
        _data = d;
      });
    }
    _svc.details().then((det) {
      if (mounted) setState(() => _details = det);
    });
    final fresh = await _svc.fetchNetwork();
    if (fresh != null && mounted) {
      setState(() {
        _cats = fresh.categories;
        _data = fresh;
      });
    }
  }

  Future<void> _makePdf() async {
    if (_pdfBusy) return;
    setState(() => _pdfBusy = true);
    showMsg(context, 'Preparing your PDF — this can take a few seconds\u2026');
    try {
      final data = _data ?? await _svc.loadBundled();
      // The PDF libraries load on demand, keeping the first app load light.
      await pdf_export.loadLibrary();
      await pdf_export.exportAllFormulasPdf(data, _details);
      if (mounted && kIsWeb) {
        showMsg(context, 'PDF downloaded — check your downloads.');
      }
    } catch (e) {
      if (mounted) showMsg(context, 'PDF error: $e');
    }
    if (mounted) setState(() => _pdfBusy = false);
  }

  void _push(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _chooseTheme() async {
    final picked = await showDialog<ThemeMode>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Appearance'),
        children: [
          for (final (mode, label) in [
            (ThemeMode.light, 'Light'),
            (ThemeMode.dark, 'Dark'),
            (ThemeMode.system, 'System default'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, mode),
              child: Row(
                children: [
                  Icon(
                      themeCtl.mode == mode
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: kPrimary),
                  const SizedBox(width: 10),
                  Text(label),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null) {
      await themeCtl.set(picked);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = auth.isLoggedIn;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kPrimaryDark,
        flexibleSpace: Container(decoration: kBarDecoration),
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child:
                      Image.asset('assets/icon.png', width: 46, height: 46),
                ),
                const SizedBox(height: 10),
                const Text('MathMitra',
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
            leading:
                const Icon(Icons.picture_as_pdf_outlined, color: kPrimary),
            title: const Text('Download All Formulas (PDF)'),
            subtitle: const Text('Well-structured PDF of all formulas'),
            trailing: _pdfBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_outlined, color: kPrimary),
            onTap: _pdfBusy ? null : _makePdf,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.campaign_outlined),
            title: const Text('Notices'),
            subtitle: const Text('Announcements and app updates'),
            trailing: ListenableBuilder(
              listenable: noticesSvc,
              builder: (context, _) => noticesSvc.unread > 0
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0245E),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('${noticesSvc.unread}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    )
                  : const SizedBox.shrink(),
            ),
            onTap: () => _push(const NoticesPage()),
          ),
          ListTile(
            leading: const Icon(Icons.folder_special_outlined),
            title: const Text('My Library'),
            subtitle:
                const Text('Favourites and your personal folders'),
            onTap: () => _push(const LibraryPage()),
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
          const Divider(),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Appearance'),
            subtitle: Text(themeCtl.mode == ThemeMode.dark
                ? 'Dark'
                : themeCtl.mode == ThemeMode.light
                    ? 'Light'
                    : 'System default'),
            onTap: _chooseTheme,
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 2),
            child: Text('About',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('App version'),
            subtitle: const Text('Version $kAppVersion'),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Creator & Owner'),
            subtitle: const Text('Yash Sharma'),
          ),
          ListTile(
            leading: const Icon(Icons.language_outlined),
            title: const Text('Website'),
            subtitle: const Text('www.yashx.xyz'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => openLink('https://yashx.xyz'),
          ),
          ListTile(
            leading: const Icon(Icons.call_outlined),
            title: const Text('Contact'),
            subtitle: const Text('9201980161'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => openLink('tel:9201980161'),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terms & Conditions'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => openLink('https://yashx.xyz/terms'),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => openLink('https://yashx.xyz/privacy'),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              'MathMitra uses analytics to understand how the app is used and to improve it. Everything that is collected is listed in the Privacy Policy, and you can opt out any time in My Profile.',
              style: TextStyle(
                  fontSize: 12, color: subtleColor(context), height: 1.5),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'Version $kAppVersion · Created by Yash Sharma',
              style: TextStyle(fontSize: 12, color: subtleColor(context)),
            ),
          ),
          const SizedBox(height: 26),
        ],
      ),
    );
  }
}
