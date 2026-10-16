import 'package:flutter/material.dart';

import '../claude.dart';
import '../insights.dart';
import '../shell.dart';
import '../store.dart';
import '../theme.dart';
import '../ui.dart';
import 'home_screen.dart' show InsightTile;

// Kept for the session so the conversation survives switching tabs (never saved to disk).
final List<({bool user, String text})> _chat = [];

/// Offline insights (always work) plus a chat with Claude when an API key is set.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key, required this.store, this.shell, this.client});
  final WarehouseStore store;
  final Shell? shell;
  final ClaudeClient? client; // for tests

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = false;
  String? _error;

  static const _suggestions = [
    'How did the business do this month?',
    'Who should I chase for payment?',
    'What should I reorder?',
    'Where can I cut costs?',
    'كم ربحنا هذا الشهر؟',
  ];

  Future<void> _send(String text) async {
    final q = text.trim();
    if (q.isEmpty || _busy) return;
    _input.clear();
    setState(() {
      _chat.add((user: true, text: q));
      _busy = true;
      _error = null;
    });
    _toBottom();
    try {
      final client = widget.client ?? ClaudeClient(widget.store.apiKey);
      final answer = await client.ask(
        system: '$assistantSystemPrompt\n\nBusiness data:\n${businessSnapshot(widget.store)}',
        history: _chat,
      );
      _chat.add((user: false, text: answer));
    } on ClaudeError catch (e) {
      _chat.removeLast();
      _input.text = q;
      _error = e.friendly;
    } catch (_) {
      _chat.removeLast();
      _input.text = q;
      _error = 'Could not reach Claude. Check the internet connection. The insights on this page still work offline.';
    }
    if (mounted) setState(() => _busy = false);
    _toBottom();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final insights = buildInsights(widget.store);
    final insightList = _InsightsCard(insights: insights, shell: widget.shell);

    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [Icon(Icons.auto_awesome, color: AppColors.brand), SizedBox(width: 10), Text('Assistant')]),
        actions: [
          if (_chat.isNotEmpty)
            TextButton.icon(
                onPressed: () => setState(() => _chat.clear()), icon: const Icon(Icons.refresh), label: const Text('New chat')),
          const SizedBox(width: 8),
        ],
      ),
      body: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 400, child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 12, 24), children: [insightList])),
              Expanded(child: _chatPane(null)),
            ])
          : _chatPane(insightList),
    );
  }

  Widget _chatPane(Widget? header) {
    final t = Theme.of(context);
    final hasKey = widget.store.apiKey.isNotEmpty || widget.client != null;
    final pad = isPhone(context) ? 16.0 : 24.0;
    return Column(children: [
      Expanded(
        child: ListView(controller: _scroll, padding: EdgeInsets.fromLTRB(pad, 8, pad, 16), children: [
          if (header != null && _chat.isEmpty) ...[header, const SizedBox(height: 16)],
          if (!hasKey)
            _KeyCard(store: widget.store)
          else if (_chat.isEmpty) ...[
            Text('Ask anything about your business', style: t.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Claude reads your figures on this device and answers in English or Arabic.',
                style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final q in _suggestions) ActionChip(label: NameText(q), onPressed: () => _send(q)),
            ]),
          ],
          for (final m in _chat) _Bubble(user: m.user, text: m.text),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text('Thinking…'),
              ]),
            ),
          if (_error != null)
            Card(
              color: AppColors.bad.withValues(alpha: .08),
              child: ListTile(leading: const Icon(Icons.error_outline, color: AppColors.bad), title: Text(_error!)),
            ),
        ]),
      ),
      if (hasKey)
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, 4, pad, 12),
            child: Row(children: [
              Expanded(
                child: ListenableBuilder(
                  listenable: _input,
                  builder: (_, _) => TextField(
                    controller: _input,
                    textDirection: dirOf(_input.text),
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _send,
                    decoration: const InputDecoration(hintText: 'Ask about sales, stock, clients…'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Send',
                onPressed: _busy ? null : () => _send(_input.text),
                icon: const Icon(Icons.arrow_upward),
              ),
            ]),
          ),
        ),
    ]);
  }
}

class _InsightsCard extends StatelessWidget {
  const _InsightsCard({required this.insights, this.shell});
  final List<Insight> insights;
  final Shell? shell;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('What I noticed', style: Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Worked out on this device. No internet needed.', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 10),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            if (insights.isEmpty)
              const ListTile(leading: Icon(Icons.check_circle, color: AppColors.good), title: Text('All good. Nothing needs you right now.')),
            for (final (i, x) in insights.indexed) ...[
              if (i > 0) const Divider(height: 1),
              InsightTile(x, onTap: shell == null || x.target == null ? null : () => shell!.goInsight(x.target!)),
            ],
          ]),
        ),
      ]);
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.user, required this.text});
  final bool user;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 640),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: user ? t.colorScheme.primary : t.cardTheme.color,
          border: user ? null : Border.all(color: t.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
        child: SelectableText(
          _plain(text),
          textDirection: dirOf(text),
          style: TextStyle(color: user ? t.colorScheme.onPrimary : null, height: 1.4),
        ),
      ),
    );
  }

  // Light markdown cleanup: the chat shows plain text.
  static String _plain(String s) => s.replaceAll('**', '').replaceAllMapped(RegExp(r'^#+\s*', multiLine: true), (_) => '');
}

class _KeyCard extends StatefulWidget {
  const _KeyCard({required this.store});
  final WarehouseStore store;

  @override
  State<_KeyCard> createState() => _KeyCardState();
}

class _KeyCardState extends State<_KeyCard> {
  final _key = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Turn on chat with Claude', style: t.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('Paste an Anthropic API key (from console.anthropic.com). It is stored only on this device and never goes '
              'into backup files. When you ask a question, a summary of your figures is sent to Claude to answer it.'),
          const SizedBox(height: 14),
          TextField(
            controller: _key,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'API key', hintText: 'sk-ant-…'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              if (!_key.text.trim().startsWith('sk-')) return toast(context, 'That does not look like an API key.');
              widget.store.setApiKey(_key.text);
            },
            child: const Text('Save key'),
          ),
        ]),
      ),
    );
  }
}
