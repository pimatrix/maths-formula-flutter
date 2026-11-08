// AI Tutor — asks the Gemini-backed /api/ai endpoint. Two modes:
//  - main tutor: any maths question, solved step by step.
//  - per-formula: opened from a formula's detail page with that formula as
//    context, so answers stay about that formula.
// Login is required (same as the photo scan) to protect the AI quota.

import 'dart:convert';

import 'package:flutter/material.dart';

import 'features.dart';
import 'main.dart';

class _Msg {
  final bool mine;
  final String text;
  const _Msg(this.mine, this.text);
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
  bool _busy = false;

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
    if (q.isEmpty || _busy) return;
    setState(() {
      _msgs.add(_Msg(true, q));
      _busy = true;
    });
    _input.clear();
    _scrollDown();
    try {
      final r = await auth.api('/api/ai', method: 'POST', body: {
        'question': q,
        if (_hasContext) 'context': widget.contextText,
      });
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (r.statusCode == 200 && d['answer'] != null) {
          _msgs.add(_Msg(false, d['answer'].toString()));
        } else {
          _msgs.add(_Msg(
              false,
              (d['error'] ?? 'Something went wrong. Please try again.')
                  .toString()));
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _msgs.add(const _Msg(
              false, 'Network error. Please check your connection and ask again.'));
        });
      }
    }
    _scrollDown();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kPrimaryDark,
        foregroundColor: Colors.white,
        title: const Text('AI Tutor', style: TextStyle(fontSize: 17)),
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
            const Text(
              'Ask any maths question and get a step-by-step solution. '
              'Log in (free) to use the AI Tutor — this keeps the AI fair for everyone.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, height: 1.5),
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
            style: const TextStyle(
                fontSize: 14, color: Colors.black54, height: 1.55),
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
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 10),
              Text('Thinking…',
                  style: TextStyle(color: Colors.black45, fontSize: 13)),
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
            child: SelectableText(
              m.mine ? m.text : displayText(m.text),
              style: TextStyle(
                  fontSize: 14.5,
                  height: 1.5,
                  color: m.mine ? Colors.white : Colors.black87),
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
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE3DEF7))),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                decoration: const InputDecoration(
                  hintText: 'Type your maths question…',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
