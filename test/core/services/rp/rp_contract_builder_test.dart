import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/services/memory/memory_prompts.dart';
import 'package:Kelivo/core/services/rp/rp_contract_builder.dart';

Assistant character({Map<String, dynamic>? data, String name = '星尘旅者'}) =>
    Assistant(
      id: 'c1',
      name: name,
      characterCardData:
          data ?? {'name': name, 'description': '一位旅人。'},
    );

void main() {
  group('RpContractBuilder.build', () {
    test('only applies to imported characters', () {
      expect(RpContractBuilder.appliesTo(character()), isTrue);
      expect(
        RpContractBuilder.appliesTo(
          const Assistant(id: 'a', name: '普通助手'),
        ),
        isFalse,
      );
      expect(RpContractBuilder.appliesTo(null), isFalse);
      expect(
        RpContractBuilder.build(
          const Assistant(id: 'a', name: '普通助手'),
          MemoryPromptLang.zh,
        ),
        isEmpty,
      );
    });

    test('zh contract carries the anti-drift rules and the name', () {
      final contract = RpContractBuilder.build(character(), MemoryPromptLang.zh);
      expect(contract, startsWith('<roleplay_contract>'));
      expect(contract, endsWith('</roleplay_contract>'));
      expect(contract, contains('星尘旅者'));
      expect(contract, contains('保持热度'));
      expect(contract, contains('不许变得冷漠、简短、客气'));
      expect(contract, contains('防复读'));
      expect(contract, contains('每一轮都要推进剧情'));
      expect(contract, contains('绝不代替用户说话、行动或做决定'));
      expect(contract, contains('<previous_story>'));
    });

    test('en contract mirrors the rules', () {
      final contract = RpContractBuilder.build(
        character(),
        MemoryPromptLang.en,
      );
      expect(contract, contains('Keep the warmth'));
      expect(contract, contains('Never speak, act or decide for the user'));
    });

    test('card post_history_instructions is embedded with override status', () {
      final contract = RpContractBuilder.build(
        character(data: {
          'name': '星尘旅者',
          'post_history_instructions': 'Always end with a question.',
        }),
        MemoryPromptLang.zh,
      );
      expect(contract, contains('卡片附加指令'));
      expect(contract, contains('Always end with a question.'));
    });

    test('example dialogue fills placeholders and frames itself', () {
      final block = RpContractBuilder.buildExampleDialogue(
        assistant: character(data: {
          'name': '星尘旅者',
          'mes_example': '<START>\n{{user}}: 你好\n{{char}}: *抬头* 星光正好。',
        }),
        userName: '阿杰',
      );
      expect(block, startsWith('<example_dialogue>'));
      expect(block, contains('阿杰: 你好'));
      expect(block, contains('星尘旅者: *抬头* 星光正好。'));
      expect(block, contains('没有真的发生过'));
    });

    test('example dialogue empty for non-characters and blank input', () {
      expect(
        RpContractBuilder.buildExampleDialogue(
          assistant: const Assistant(id: 'a', name: '助手'),
          userName: 'u',
        ),
        isEmpty,
      );
      expect(
        RpContractBuilder.buildExampleDialogue(
          assistant: character(data: {'name': 'x', 'mes_example': '  '}),
          userName: 'u',
        ),
        isEmpty,
      );
    });

    test('blank PHI is omitted entirely', () {
      final contract = RpContractBuilder.build(
        character(data: {'name': 'x', 'post_history_instructions': '   '}),
        MemoryPromptLang.zh,
      );
      expect(contract.contains('卡片附加指令'), isFalse);
    });
  });
}
