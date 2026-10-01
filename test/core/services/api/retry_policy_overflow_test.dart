import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/api/retry_policy.dart';

void main() {
  group('isContextOverflowError', () {
    test('detects the common provider overflow messages', () {
      expect(
        isContextOverflowError(
          Exception(
            "Error 400: This model's maximum context length is 8192 tokens. "
            'However, you requested 9000 tokens in the messages.',
          ),
        ),
        isTrue,
      );
      expect(
        isContextOverflowError(
          Exception('invalid_request_error: context_length_exceeded'),
        ),
        isTrue,
      );
      expect(
        isContextOverflowError(
          Exception(
            'Your prompt is too long: 204800 tokens > 200000 maximum.',
          ),
        ),
        isTrue,
      );
      expect(
        isContextOverflowError(
          Exception('input is too long for the requested model'),
        ),
        isTrue,
      );
    });

    test('rejects unrelated errors', () {
      expect(isContextOverflowError(Exception('HTTP 500 internal error')), isFalse);
      expect(isContextOverflowError(Exception('HTTP 401 unauthorized')), isFalse);
      expect(isContextOverflowError(Exception('connection reset')), isFalse);
    });
  });

  group('shrinkApiMessagesForOverflow', () {
    List<Map<String, dynamic>> buildMessages(int count) => [
          {'role': 'system', 'content': 'system prompt'},
          for (var i = 0; i < count; i++)
            {'role': 'user', 'content': 'message $i'},
        ];

    test('keeps the system prompt, drops the older half, inserts a marker', () {
      final messages = buildMessages(10);
      final shrunk = shrinkApiMessagesForOverflow(messages);

      expect(shrunk, isTrue);
      expect(messages.first['role'], 'system');
      expect(messages.first['content'], 'system prompt');
      // 10 body messages → 5 dropped, then marker + 5 survivors.
      expect(messages.length, 7);
      final marker = messages[1]['content'] as String;
      expect(marker, contains('[System]'));
      expect(marker, contains('omitted'));
      expect((messages.last['content'] as String), 'message 9');
      expect(
        messages.any((m) => (m['content'] as String) == 'message 0'),
        isFalse,
      );
    });

    test('cleans dangling tool messages at the cut point', () {
      final messages = <Map<String, dynamic>>[
        {'role': 'system', 'content': 'system prompt'},
        {'role': 'user', 'content': 'question'},
        {'role': 'assistant', 'content': 'calling tool'},
        {'role': 'tool', 'content': 'tool result'},
        {'role': 'user', 'content': 'follow-up'},
      ];
      expect(shrinkApiMessagesForOverflow(messages), isTrue);
      // After dropping the older half, any leading tool rows are removed so
      // the request never starts mid-triplet.
      expect(
        (messages[1]['role'] ?? '').toString() == 'tool',
        isFalse,
      );
    });

    test('returns false when there is nothing meaningful to drop', () {
      expect(shrinkApiMessagesForOverflow([]), isFalse);
      expect(
        shrinkApiMessagesForOverflow([
          {'role': 'system', 'content': 'system prompt'},
          {'role': 'user', 'content': 'only message'},
        ]),
        isFalse,
      );
    });
  });
}
