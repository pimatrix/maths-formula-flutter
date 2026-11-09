// AI Tutor — asks the Gemini-backed /api/ai endpoint. Two modes:
//  - main tutor: any maths question, solved step by step.
//  - per-formula: opened from a formula's detail page with that formula as
//    context, so answers stay about that formula.
// Login is required (same as the photo scan) to protect the AI quota.
//
// Usage model: the house Gemini key allows 10 free questions per user per
// day (enforced by the server). A user can also paste their OWN free
// Gemini key (BYOK): it is stored only on this device, never sent to our
// server or database, and the app then calls Google directly with it —
// no daily limit.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

import 'features.dart';
import 'main.dart';

/// The same tutor instructions the server sends with the house key, so
/// answers feel identical whichever key answers.
const String kAiSystem =
    'You are a friendly maths tutor for a first-year engineering student (Maths-I level: matrices, differential and integral calculus, ordinary differential equations, complex numbers, plus school basics like algebra, trigonometry, indices and logarithms).\n'
    'Rules for every answer:\n'
    '- Use simple, clear English. Explain step by step, like a good teacher.\n'
    '- When solving, show each step briefly and give the final answer clearly at the end.\n'
    '- Write formulas in FormulaText markup so the app can render them nicely: fraction \\frac{num}{den}; power x^{2} (always braces); subscript a_{n}; root \\sqrt{...}; commands \\pi \\theta \\alpha \\beta \\lambda \\Delta \\int \\sum \\partial \\infty \\pm \\leq \\geq \\neq \\approx \\to \\times \\cdot; functions as plain words (sin, cos, tan, log, ln, lim, det); matrix as MAT(a, b; c, d).\n'
    '- Plain text only: no markdown headings, no **bold**, no code fences. Short lines and numbered steps are welcome.\n'
    '- Keep the answer under 350 words unless the question truly needs more.\n'
    '- If the question is not about maths, politely say you only help with maths.';

/// The user's own Gemini API key — kept ONLY in this device's local
/// storage. It is never sent to the MathMitra server or database.
class Byok {
  static String key = '';
  static bool _loaded = false;

  static bool get active => key.isNotEmpty;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      key = prefs.getString('mm_gemini_key') ?? '';
    } catch (_) {}
  }

  static Future<void> save(String value) async {
    key = value.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (key.isEmpty) {
        await prefs.remove('mm_gemini_key');
      } else {
        await prefs.setString('mm_gemini_key', key);
      }
    } catch (_) {}
  }
}

Map<String, dynamic> _inlineImage(String dataUrl) {
  final comma = dataUrl.indexOf(',');
  final head = comma > 0 ? dataUrl.substring(0, comma) : '';
  final mime = head.startsWith('data:')
      ? head.substring(5).split(';').first
      : 'image/jpeg';
  return {
    'inline_data': {
      'mime_type': mime,
      'data': comma > 0 ? dataUrl.substring(comma + 1) : dataUrl,
    }
  };
}

/// Asks Google Gemini DIRECTLY with the user's own key (same models,
/// same instructions as the server path).
Future<String> askWithOwnKey(String question, String? contextText,
    {String? imageDataUrl}) async {
  final userText = (contextText != null && contextText.isNotEmpty)
      ? 'The student is viewing this formula in the app:\n$contextText\n\nStudent\'s question: $question'
      : 'Student\'s question: $question';
  final payload = jsonEncode({
    'systemInstruction': {
      'parts': [
        {'text': kAiSystem}
      ]
    },
    'contents': [
      {
        'parts': [
          {'text': userText},
          if (imageDataUrl != null) _inlineImage(imageDataUrl),
        ]
      }
    ],
    'generationConfig': {'temperature': 0.3, 'maxOutputTokens': 1400},
  });
  String lastErr = 'network error';
  for (final model in ['gemini-3.5-flash-lite', 'gemini-3.8-flash']) {
    try {
      final r = await http
          .post(
            Uri.parse(
                'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent'),
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': Byok.key,
            },
            body: payload,
          )
          .timeout(const Duration(seconds: 40));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode == 200) {
        final parts =
            (d['candidates']?[0]?['content']?['parts'] as List?) ?? const [];
        final text = parts
            .map((x) => ((x as Map)['text'] ?? '').toString())
            .join()
            .trim();
        if (text.isNotEmpty) return text;
        lastErr = 'empty reply';
        continue;
      }
      final msg = (d['error']?['message'] ?? '').toString();
      if (msg.contains('API key not valid') || msg.contains('API_KEY_INVALID')) {
        throw 'Your saved key was not accepted by Google. Open the key settings (key icon above) and paste the key again.';
      }
      lastErr = msg.isNotEmpty ? msg : 'HTTP ${r.statusCode}';
    } catch (e) {
      if (e is String) rethrow;
      lastErr = 'network error';
    }
  }
  throw 'Your own key could not get an answer right now ($lastErr). Please try again in a moment.';
}

class _Msg {
  final bool mine;
  final String text;
  final bool hasImage;
  final bool noSave;
  const _Msg(this.mine, this.text, {this.hasImage = false, this.noSave = false});

  Map<String, dynamic> toJson() =>
      {'m': mine, 't': text, if (hasImage) 'i': 1, if (noSave) 'n': 1};

  factory _Msg.fromJson(Map<String, dynamic> j) => _Msg(
        j['m'] == true,
        (j['t'] ?? '').toString(),
        hasImage: j['i'] == 1,
        noSave: j['n'] == 1,
      );
}

class AiTutorPage extends StatefulWidget {
  final String? formulaName;
  final String? contextText;
  const AiTutorPage({super.key, this.formulaName, this.contextText});

  @override
  State<AiTutorPage> createState() => _AiTutorPageState();
}

class _AiTutorPageState extends State<AiTutorPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [];
  String? _pendingImage;
  bool _busy = false;
  static const String _chatKey = 'mm_ai_chat_v1';

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_chatKey);
      if (raw != null) {
        final list = (jsonDecode(raw) as List)
            .map((e) => _Msg.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        if (mounted && list.isNotEmpty) {
          setState(() => _msgs.addAll(list));
        }
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tail =
          _msgs.length > 100 ? _msgs.sublist(_msgs.length - 100) : _msgs;
      await prefs.setString(
          _chatKey, jsonEncode(tail.map((m) => m.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> _clearChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear this chat?'),
        content: const Text(
            'The conversation saved on this device will be deleted. Your Saved Solutions stay saved.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true) {
      setState(() => _msgs.clear());
      _persist();
    }
  }

  Future<void> _pickImage() async {
    try {
      final x = await ImagePicker().pickImage(
          source: ImageSource.gallery, imageQuality: 72, maxWidth: 1280);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final mime = x.mimeType ?? 'image/jpeg';
      setState(() => _pendingImage = 'data:$mime;base64,${base64Encode(bytes)}');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not attach that photo.')));
      }
    }
  }

  void _saveSolution(int i) {
    var q = '';
    for (var j = i - 1; j >= 0; j--) {
      if (_msgs[j].mine) {
        q = _msgs[j].text;
        break;
      }
    }
    if (q.isEmpty) return;
    library.saveSolution(q, _msgs[i].text);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Saved — find it in My Library, Saved Solutions.')));
  }

  Widget _imagePreview() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 0),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
                base64Decode(_pendingImage!.split(',').last),
                width: 44,
                height: 44,
                fit: BoxFit.cover),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Photo attached — type a question or just send.',
                style: TextStyle(fontSize: 12.5)),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 19),
            onPressed: () => setState(() => _pendingImage = null),
          ),
        ],
      ),
    );
  }
  int? _remaining;
  int _limit = 10; // the admin can change this; refreshed from the server

  @override
  void initState() {
    super.initState();
    _loadHistory();
    Byok.load().then((_) {
      if (mounted) setState(() {});
    });
    _refreshUsage();
  }

  Future<void> _refreshUsage() async {
    if (!auth.isLoggedIn || Byok.active) return;
    try {
      final r = await auth.api('/api/ai');
      if (r.statusCode != 200) return;
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (mounted && d['remaining'] is num) {
        setState(() {
          _remaining = (d['remaining'] as num).toInt();
          if (d['limit'] is num) _limit = (d['limit'] as num).toInt();
        });
      }
    } catch (_) {}
  }

  Future<void> _showKeyDialog() async {
    final ctrl = TextEditingController(text: Byok.key);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your own Gemini key'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The free questions on our key are limited to 10 a day. With your own free key from Google, there is no daily limit — and this app then talks to Google directly with your key.',
                style: TextStyle(fontSize: 13.5, height: 1.5),
              ),
              const SizedBox(height: 12),
              const Text('How to get a free key:',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              const SizedBox(height: 4),
              const Text(
                '1. Open Google AI Studio (button below) and sign in with your Google account.\n'
                '2. Tap "Create API key". If it asks for a project, choose the default one.\n'
                '3. Copy the key Google gives you.\n'
                '4. Paste it here and tap Save.',
                style: TextStyle(fontSize: 13.5, height: 1.6),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () =>
                    openLink('https://aistudio.google.com/apikey'),
                icon: const Icon(Icons.open_in_new, size: 17),
                label: const Text('Open Google AI Studio'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                obscureText: true,
                decoration: fieldDeco('Paste your Gemini API key',
                    icon: Icons.key_outlined),
              ),
              const SizedBox(height: 10),
              const Text(
                'Your key is saved only on this device. It is never sent to our server and never stored in our database.',
                style: TextStyle(fontSize: 12.5, height: 1.45),
              ),
            ],
          ),
        ),
        actions: [
          if (Byok.active)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'remove'),
              child: const Text('Remove key',
                  style: TextStyle(color: Colors.red)),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kPrimary),
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Save key'),
          ),
        ],
      ),
    );
    if (result == 'save') {
      await Byok.save(ctrl.text);
      if (mounted) {
        setState(() {});
        showMsg(
            context,
            Byok.active
                ? 'Key saved on this device — unlimited questions are on.'
                : 'Please paste a key first.');
        if (!Byok.active) _refreshUsage();
      }
    } else if (result == 'remove') {
      await Byok.save('');
      if (mounted) {
        setState(() {});
        showMsg(context, 'Your key was removed from this device.');
        _refreshUsage();
      }
    }
    ctrl.dispose();
  }

  Widget _statusLine() {
    if (Byok.active) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Row(
          children: [
            const Icon(Icons.key_outlined, size: 16, color: kPrimary),
            const SizedBox(width: 7),
            const Expanded(
              child: Text('Using your own Gemini key — no daily limit.',
                  style: TextStyle(fontSize: 12.5)),
            ),
            TextButton(
              onPressed: _showKeyDialog,
              child: const Text('Change', style: TextStyle(fontSize: 12.5)),
            ),
          ],
        ),
      );
    }
    if (_remaining == null) return const SizedBox.shrink();
    final left = _remaining!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(Icons.auto_awesome_outlined,
              size: 16, color: left == 0 ? Colors.red : kPrimary),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              left == 0
                  ? 'Today\'s $_limit free questions are over — they reset at midnight.'
                  : 'Free questions left today: $left of $_limit',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          TextButton(
            onPressed: _showKeyDialog,
            child: const Text('Use your own key',
                style: TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  bool get _hasContext => (widget.contextText ?? '').isNotEmpty;

  List<String> get _suggestions => _hasContext
      ? const [
          'Explain this formula in simple words',
          'Give me a solved example using this formula',
          'Where is this formula used?',
          'What are the common mistakes students make with this?',
        ]
      : const [
          'Solve: dy/dx + y = e^x',
          'Explain the chain rule with an example',
          'How do I find the inverse of a 2x2 matrix?',
          'Integrate x^2 from 0 to 3, step by step',
        ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send(String raw) async {
    final q = raw.trim();
    final image = _pendingImage;
    if ((q.isEmpty && image == null) || _busy) return;
    setState(() {
      _msgs.add(_Msg(true, q.isNotEmpty ? q : 'Please solve this photo',
          hasImage: image != null));
      _busy = true;
      _pendingImage = null;
    });
    _input.clear();
    _scrollDown();
    try {
      if (Byok.active) {
        final answer = await askWithOwnKey(
            q.isNotEmpty ? q : 'Solve the problem in this photo step by step.',
            _hasContext ? widget.contextText : null,
            imageDataUrl: image);
        if (!mounted) return;
        setState(() {
          _busy = false;
          _msgs.add(_Msg(false, answer));
        });
      } else {
        final r = await auth.api('/api/ai', method: 'POST', body: {
          'question': q,
          if (_hasContext) 'context': widget.contextText,
          if (image != null) 'image': image,
        });
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          _busy = false;
          if (r.statusCode == 200 && d['answer'] != null) {
            _msgs.add(_Msg(false, d['answer'].toString()));
            final u = d['usage'];
            if (u is Map && u['remaining'] is num) {
              _remaining = (u['remaining'] as num).toInt();
              if (u['limit'] is num) _limit = (u['limit'] as num).toInt();
            }
          } else {
            if (r.statusCode == 429 && d['limit_reached'] == true) {
              _remaining = 0;
            }
            _msgs.add(_Msg(
                false,
                (d['error'] ?? 'Something went wrong. Please try again.')
                    .toString(),
                noSave: true));
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _msgs.add(_Msg(
              false,
              e is String
                  ? e
                  : 'Network error. Please check your connection and ask again.',
              noSave: true));
        });
      }
    }
    _persist();
    _scrollDown();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kPrimaryDark,
        flexibleSpace: Container(decoration: kBarDecoration),
        foregroundColor: Colors.white,
        title: const Text('AI Tutor', style: TextStyle(fontSize: 17)),
        actions: [
          if (_msgs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear chat',
              onPressed: _clearChat,
            ),
          IconButton(
            icon: const Icon(Icons.key_outlined),
            tooltip: 'Your own Gemini key',
            onPressed: _showKeyDialog,
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: auth,
        builder: (context, _) {
          if (!auth.isLoggedIn) {
            return _loginGate(context);
          }
          return Column(
            children: [
              if (_hasContext) _contextBanner(),
              _statusLine(),
              Expanded(child: _chatList()),
              _inputBar(),
            ],
          );
        },
      ),
    );
  }

  Widget _loginGate(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 52, color: kPrimary),
            const SizedBox(height: 14),
            const Text('AI Tutor',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              'Ask any maths question and get a step-by-step solution. '
              'Log in (free) to use the AI Tutor — this keeps the AI fair for everyone.',
              textAlign: TextAlign.center,
              style: TextStyle(color: subtleColor(context), height: 1.5),
            ),
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kPrimary),
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AuthPage())),
              child: const Text('Log in / Sign up'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contextBanner() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFEFEBFB),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          const Icon(Icons.functions, size: 18, color: kPrimary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Asking about: ${widget.formulaName ?? 'this formula'}',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: kPrimaryDark),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chatList() {
    if (_msgs.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            _hasContext
                ? 'Ask anything about this formula — its meaning, a solved example, or a question you want to try with it.'
                : 'Type any maths question — an equation to solve, a formula to understand, or a doubt from class — and get a step-by-step answer.',
            style: TextStyle(
                fontSize: 14, color: subtleColor(context), height: 1.55),
          ),
          const SizedBox(height: 14),
          const Text('Try one of these:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in _suggestions)
                ActionChip(
                  label: Text(s, style: const TextStyle(fontSize: 12.5)),
                  onPressed: () => _send(s),
                ),
            ],
          ),
        ],
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(14),
      itemCount: _msgs.length + (_busy ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _msgs.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 10),
              Text('Thinking…',
                  style: TextStyle(color: subtleColor(context), fontSize: 13)),
            ]),
          );
        }
        final m = _msgs[i];
        return Align(
          alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.86),
            decoration: BoxDecoration(
              color: m.mine ? kPrimary : const Color(0xFFF1EFFB),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (m.hasImage && m.mine)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.image_outlined,
                            size: 14, color: Colors.white70),
                        SizedBox(width: 5),
                        Text('Photo',
                            style: TextStyle(
                                fontSize: 11.5, color: Colors.white70)),
                      ],
                    ),
                  ),
                SelectableText(
                  m.mine ? m.text : displayText(m.text),
                  style: TextStyle(
                      fontSize: 14.5,
                      height: 1.5,
                      color: m.mine ? Colors.white : Colors.black87),
                ),
                if (!m.mine && !m.noSave)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _saveSolution(i),
                      icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                      label:
                          const Text('Save', style: TextStyle(fontSize: 12.5)),
                      style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 6)),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF26262E)
              : Colors.white,
          border: Border(
              top: BorderSide(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF383842)
                      : const Color(0xFFE3DEF7))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pendingImage != null) _imagePreview(),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  color: kPrimary,
                  tooltip: 'Attach a photo of the question',
                  onPressed: _busy ? null : _pickImage,
                ),
                Expanded(
                  child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : null),
                decoration: InputDecoration(
                  hintText: 'Type your question…',
                  hintStyle: TextStyle(color: subtleColor(context)),
                  filled: true,
                  fillColor: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF2E2E37)
                      : Colors.white,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              ),
            ),
                IconButton(
                  icon: const Icon(Icons.send),
                  color: kPrimary,
                  onPressed: _busy ? null : () => _send(_input.text),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the AI Tutor focused on one formula (from its detail page).
void openFormulaAi(BuildContext context, EntryItem e,
    Map<String, dynamic> details, String categoryTitle) {
  final name = displayName(e, details);
  final ctx = StringBuffer()
    ..writeln('Formula name: $name')
    ..writeln('Topic: $categoryTitle'
        '${e.section.isNotEmpty ? ' · ${e.section}' : ''}')
    ..writeln('Formula: ${displayText(e.body)}');
  if (e.about.isNotEmpty) ctx.writeln('About: ${e.about}');
  if (!e.userAdded) {
    final d = details[e.id];
    if (d is Map && (d['about'] as String?)?.isNotEmpty == true) {
      ctx.writeln('About: ${d['about']}');
    }
  }
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) =>
        AiTutorPage(formulaName: name, contextText: ctx.toString()),
  ));
}
