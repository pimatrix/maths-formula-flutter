// Contact / Feedback / Support form — submits through Web3Forms using the
// same access key as the portfolio website (submissions land in the same
// inbox). The message is labelled so formula-app mail is easy to spot.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'main.dart';

const String _kWeb3FormsKey = '301bf00e-0a48-4396-af74-d61d876a84f8';

class ContactPage extends StatefulWidget {
  const ContactPage({super.key});

  @override
  State<ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _message = TextEditingController();
  String _type = 'Feedback';
  bool _busy = false;
  bool _sent = false;
  String _error = '';

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final message = _message.text.trim();
    if (name.isEmpty || email.isEmpty || message.isEmpty) {
      setState(() => _error = 'Please fill your name, email and message.');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final r = await http.post(
        Uri.parse('https://api.web3forms.com/submit'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'access_key': _kWeb3FormsKey,
          'subject': '[Formula App] $_type — from $name',
          'from_name': 'Maths Formula Sheet App',
          'name': name,
          'email': email,
          'type': _type,
          'message': message,
          'source': 'Maths Formula Sheet (Flutter web app)',
        }),
      );
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (r.statusCode == 200 && d['success'] == true) {
        setState(() {
          _sent = true;
          _busy = false;
        });
      } else {
        setState(() {
          _busy = false;
          _error = (d['message'] ?? 'Something went wrong. Please try again.')
              .toString();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Network error. Please check your connection and retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kPrimaryDark,
        foregroundColor: Colors.white,
        title: const Text('Contact / Feedback', style: TextStyle(fontSize: 17)),
      ),
      body: _sent
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.mark_email_read_outlined,
                        size: 56, color: kPrimary),
                    const SizedBox(height: 14),
                    const Text('Message sent successfully.',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const Text(
                      'Thank you for reaching out — we read every message and reply on email when needed.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54, height: 1.5),
                    ),
                    const SizedBox(height: 18),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Back'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const Text(
                  'Questions, feedback, a wrong formula, or need help? Send a message — it reaches us directly on email.',
                  style:
                      TextStyle(fontSize: 13.5, color: Colors.black54, height: 1.5),
                ),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'Contact', label: Text('Contact')),
                    ButtonSegment(value: 'Feedback', label: Text('Feedback')),
                    ButtonSegment(value: 'Support', label: Text('Support')),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) =>
                      setState(() => _type = s.first),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Your name *',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Your email *',
                    prefixIcon: Icon(Icons.mail_outline),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _message,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Message *',
                    hintText: 'Write your message…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(_error,
                      style:
                          const TextStyle(color: Colors.red, fontSize: 13.5)),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: kPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: _busy
                      ? const SizedBox(
                          height: 17,
                          width: 17,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_outlined, size: 18),
                  label: const Text('Send Message'),
                ),
              ],
            ),
    );
  }
}
