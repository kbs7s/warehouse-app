import 'dart:convert';

import 'package:http/http.dart' as http;

/// Talks to Claude straight from the browser with the user's own API key.
/// The key never leaves the device except in requests to api.anthropic.com.
class ClaudeClient {
  ClaudeClient(this.apiKey, {http.Client? client}) : _http = client ?? http.Client();
  final String apiKey;
  final http.Client _http;

  static const model = 'claude-sonnet-5-5';

  /// [history] alternates user / assistant turns, oldest first, ending with the user's question.
  Future<String> ask({required String system, required List<({bool user, String text})> history}) async {
    final res = await _http.post(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'anthropic-dangerous-direct-browser-access': 'true',
      },
      body: jsonEncode({
        'model': model,
        'max_tokens': 1500,
        'system': system,
        'messages': [
          for (final m in history) {'role': m.user ? 'user' : 'assistant', 'content': m.text},
        ],
      }),
    );
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      final msg = (body['error'] as Map?)?['message'] ?? 'HTTP ${res.statusCode}';
      throw ClaudeError(res.statusCode, '$msg');
    }
    return [
      for (final b in body['content'] as List)
        if ((b as Map)['type'] == 'text') b['text'] as String,
    ].join('\n').trim();
  }
}

class ClaudeError implements Exception {
  ClaudeError(this.status, this.message);
  final int status;
  final String message;

  String get friendly => switch (status) {
        401 => 'The API key was not accepted. Check it in Settings.',
        429 => 'Too many questions at once, or the account has no credit left. Try again shortly.',
        529 || 503 => 'Claude is busy right now. Try again in a minute.',
        _ => 'Claude could not answer: $message',
      };

  @override
  String toString() => friendly;
}

const assistantSystemPrompt = '''
You are the assistant inside a small business app used on an iPad. The owner runs a warehouse
(stock items, often with Arabic names), bills clients with invoices, buys from suppliers and pays running costs.
They have no bookkeeping experience.

How to answer:
- Reply in the language the owner writes in (English or Arabic).
- Plain words, short paragraphs or a few bullets. Explain any accounting term in one phrase.
- Amounts are in IQD; write them with thousands separators.
- Base every number on the business data below. If the data does not show something, say so instead of guessing.
- When useful, end with one concrete next step they can take in the app (e.g. record a payment, reorder an item).

Cost of goods uses FIFO cost layers (oldest stock is sold first). "Supplies used" is stock given to internal
departments: a cost with no sale.
''';
