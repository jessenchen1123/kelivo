import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/features/home/services/message_builder_service.dart';

class _FakeBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('applyContextLimit (P0-c: 前情提要)', () {
    late MessageBuilderService service;

    setUp(() {
      service = MessageBuilderService(
        chatService: ChatService(),
        contextProvider: _FakeBuildContext(),
      );
    });

    List<Map<String, dynamic>> buildMessages(int count) => [
          {'role': 'system', 'content': 'system prompt'},
          for (var i = 0; i < count; i++)
            {
              'role': i.isEven ? 'user' : 'assistant',
              'content': 'message $i',
            },
        ];

    test(
      'trimming injects the stored conversation summary as 前情提要',
      () {
        final assistant = const Assistant(
          id: 'a',
          name: 'A',
        ).copyWith(limitContextMessages: true, contextMessageSize: 6);
        final conversation = Conversation(
          id: 'c1',
          title: 't',
          assistantId: 'a',
          summary: '用户与旅人在酒馆相遇，之后一起踏上旅程。',
        );

        final messages = buildMessages(20);
        service.applyContextLimit(
          messages,
          assistant,
          conversation: conversation,
        );

        final notice = messages
            .map((m) => (m['content'] ?? '').toString())
            .firstWhere((c) => c.contains('<previous_story>'));
        expect(notice, contains('前情提要'));
        expect(notice, contains('酒馆相遇'));
        expect(notice, contains('earlier messages omitted'));
        // System prompt first, notice second, then the kept tail.
        expect(messages[0]['role'], 'system');
        expect((messages[2]['content'] as String), 'message 14');
      },
    );

    test('trimming without a summary still leaves an explicit marker', () {
      final assistant = const Assistant(
        id: 'a',
        name: 'A',
      ).copyWith(limitContextMessages: true, contextMessageSize: 4);

      final messages = buildMessages(10);
      service.applyContextLimit(messages, assistant);

      final notice = messages
          .map((m) => (m['content'] ?? '').toString())
          .firstWhere((c) => c.contains('<previous_story>'));
      expect(notice, contains('No summary is available'));
      expect(notice, contains('earlier messages omitted'));
    });

    test('under the limit nothing is injected', () {
      final assistant = const Assistant(
        id: 'a',
        name: 'A',
      ).copyWith(limitContextMessages: true, contextMessageSize: 64);

      final messages = buildMessages(10);
      service.applyContextLimit(messages, assistant);

      expect(messages.length, 11);
      expect(
        messages.any(
          (m) => (m['content'] as String).contains('<previous_story>'),
        ),
        isFalse,
      );
    });
  });

  group('applyOverflowShrink (P0-c: 接近窗口自动收缩)', () {
    late MessageBuilderService service;

    setUp(() {
      service = MessageBuilderService(
        chatService: ChatService(),
        contextProvider: _FakeBuildContext(),
      );
    });

    List<Map<String, dynamic>> buildMessages(int count, {int chars = 200}) => [
          {'role': 'system', 'content': 'system prompt'},
          for (var i = 0; i < count; i++)
            {
              'role': i.isEven ? 'user' : 'assistant',
              'content': 'message $i ${'x' * chars}',
            },
        ];

    test('shrinks to the target fraction and injects the notice', () {
      final conversation = Conversation(
        id: 'c2',
        title: 't',
        assistantId: 'a',
        summary: '前情：用户与角色建立了信任。',
      );
      // ASCII filler estimates ~7 chars/token → ~715 tokens per message, so
      // 60 messages ≈ 43k tokens against a 40k window → over the 92% trigger.
      final messages = buildMessages(60, chars: 5000);

      final shrunk = service.applyOverflowShrink(
        messages,
        conversation: conversation,
        contextWindowTokens: 40000,
      );

      expect(shrunk, isTrue);
      final notice = messages
          .map((m) => (m['content'] ?? '').toString())
          .firstWhere((c) => c.contains('<previous_story>'));
      expect(notice, contains('前情：用户与角色建立了信任。'));
      expect(messages.length, lessThan(61));
      // Newest message survives.
      expect(
        (messages.last['content'] as String).startsWith('message 59'),
        isTrue,
      );
    });

    test('under the trigger threshold the request is untouched', () {
      final messages = buildMessages(5, chars: 100);
      final before = List.of(messages);

      final shrunk = service.applyOverflowShrink(
        messages,
        contextWindowTokens: 40000,
      );

      expect(shrunk, isFalse);
      expect(messages.length, before.length);
    });

    test('unknown window is a no-op', () {
      final messages = buildMessages(60, chars: 5000);
      expect(
        service.applyOverflowShrink(messages, contextWindowTokens: null),
        isFalse,
      );
      expect(messages.length, 61);
    });

    test('estimateApiMessagesTokens counts content', () {
      final messages = [
        {'role': 'system', 'content': 'hello world'},
        {'role': 'user', 'content': ''},
      ];
      expect(
        MessageBuilderService.estimateApiMessagesTokens(messages),
        greaterThan(0),
      );
    });
  });

  group('buildTruncationNotice', () {
    test('includes summary when present and counts omitted messages', () {
      final notice = MessageBuilderService.buildTruncationNotice(
        omittedCount: 12,
        summary: ' 剧情摘要 ',
      );
      expect(notice, contains('12'));
      expect(notice, contains('剧情摘要'));
      expect(notice.startsWith('<previous_story>'), isTrue);
      expect(notice.endsWith('</previous_story>'), isTrue);
    });

    test('explicitly says when no summary exists', () {
      final notice = MessageBuilderService.buildTruncationNotice(
        omittedCount: 3,
      );
      expect(notice, contains('No summary is available'));
    });
  });

  group('injectRoleplayContract (P2: 防漂移)', () {
    late MessageBuilderService service;

    setUp(() {
      service = MessageBuilderService(
        chatService: ChatService(),
        contextProvider: _FakeBuildContext(),
      );
    });

    List<Map<String, dynamic>> buildMessages() => [
          {'role': 'system', 'content': 'system prompt'},
          {
            'role': 'user',
            'content': 'older message',
            MessageBuilderService.internalRevisionIdKey: 'rev-1',
          },
          {'role': 'assistant', 'content': 'older reply'},
          {
            'role': 'user',
            'content': 'newest message',
            MessageBuilderService.internalRevisionIdKey: 'rev-2',
          },
        ];

    test('injects before the newest user message for characters', () {
      const assistant = Assistant(
        id: 'c1',
        name: '星尘旅者',
        characterCardData: {'name': '星尘旅者'},
      );
      final messages = buildMessages();
      service.injectRoleplayContract(messages, assistant);

      // system, older user, older assistant, [contract], newest user.
      expect(messages.length, 5);
      expect(messages[3]['role'], 'user');
      expect(
        (messages[3]['content'] as String).startsWith('<roleplay_contract>'),
        isTrue,
      );
      expect((messages[3]['content'] as String), contains('星尘旅者'));
      expect((messages[4]['content'] as String), 'newest message');
    });

    test('plain assistants get nothing', () {
      const assistant = Assistant(id: 'a', name: '普通助手');
      final messages = buildMessages();
      service.injectRoleplayContract(messages, assistant);
      expect(messages.length, 4);
    });

    test('survives context limiting (injected after trimming)', () {
      final assistant = const Assistant(
        id: 'c1',
        name: '星尘旅者',
        characterCardData: {'name': '星尘旅者'},
      ).copyWith(limitContextMessages: true, contextMessageSize: 2);
      final messages = buildMessages();
      service.applyContextLimit(messages, assistant);
      service.injectRoleplayContract(messages, assistant);

      final contractAt = messages.indexWhere(
        (m) => (m['content'] as String).startsWith('<roleplay_contract>'),
      );
      expect(contractAt, greaterThanOrEqualTo(0));
    });
  });
}
