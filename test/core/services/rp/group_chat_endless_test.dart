import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/conversation_group_chat.dart';
import 'package:Kelivo/core/services/rp/group_director.dart';

void main() {
  group('ConversationGroupChat endless flag', () {
    test('round-trips through extras', () {
      const config = ConversationGroupChat(
        enabled: true,
        members: <String>['a', 'b'],
        directorEnabled: true,
        infiniteEnabled: true,
      );

      final extras = config.applyTo(const <String, dynamic>{'keep': 1});
      final decoded = ConversationGroupChat.fromExtras(extras);

      expect(decoded.infiniteEnabled, isTrue);
      expect(decoded.directorEnabled, isTrue);
      expect(decoded.members, <String>['a', 'b']);
      expect(extras['keep'], 1);
    });

    test('defaults to off and is dropped when the group is not active', () {
      expect(
        ConversationGroupChat.fromExtras(
          const <String, dynamic>{},
        ).infiniteEnabled,
        isFalse,
      );

      const disabled = ConversationGroupChat(infiniteEnabled: true);
      final extras = disabled.applyTo(const <String, dynamic>{});
      expect(extras.containsKey(ConversationGroupChat.keyInfinite), isFalse);
    });

    test('copyWith toggles the flag without touching the rest', () {
      const config = ConversationGroupChat(
        enabled: true,
        members: <String>['a', 'b'],
      );
      final next = config.copyWith(infiniteEnabled: true);
      expect(next.infiniteEnabled, isTrue);
      expect(next.members, <String>['a', 'b']);
    });
  });

  group('GroupDirector.buildPrompt endless variant', () {
    final roster = <({String name, String identity})>[
      (name: '阿澈', identity: '沉默的剑客'),
      (name: '小雨', identity: '话多的药师'),
    ];
    final recent = <({String speaker, String content})>[
      (speaker: '阿澈', content: '别乱跑。'),
    ];

    test('endless mode forbids handing the turn back to the user', () {
      final prompt = GroupDirector.buildPrompt(
        roster: roster,
        recent: recent,
        userNickname: GroupDirector.userNicknameLabel,
        speakCounts: const <String, int>{'阿澈': 1},
        lang: MemoryPromptLangLike.zh,
        infinite: true,
      );

      expect(prompt, contains('绝不要选 USER'));
      expect(prompt, isNot(contains('选 USER。')));
      expect(prompt, contains('"next": "成员名字"'));
    });

    test('default mode keeps the hand-back rule and the USER option', () {
      final prompt = GroupDirector.buildPrompt(
        roster: roster,
        recent: recent,
        userNickname: GroupDirector.userNicknameLabel,
        speakCounts: const <String, int>{'阿澈': 1},
        lang: MemoryPromptLangLike.zh,
      );

      expect(prompt, contains('选 USER。'));
      expect(prompt, contains('"next": "成员名字或USER"'));
      expect(prompt, isNot(contains('绝不要选 USER')));
    });

    test('English endless variant is available too', () {
      final prompt = GroupDirector.buildPrompt(
        roster: roster,
        recent: recent,
        userNickname: GroupDirector.userNicknameLabel,
        speakCounts: const <String, int>{},
        lang: MemoryPromptLangLike.en,
        infinite: true,
      );

      expect(prompt, contains('Never answer USER'));
      expect(prompt, isNot(contains('answer USER.')));
    });
  });
}
