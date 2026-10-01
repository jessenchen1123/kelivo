import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/character_card.dart';

Map<String, dynamic> cardData({
  String name = '星尘旅者',
  String description = '一位漫游星海的神秘旅人。',
  String personality = '冷静、好奇、喜欢打谜语。',
  String scenario = '你们在悬崖边的小客栈相遇。',
  String firstMes = '*她抬起头* 你也看见那颗流星了吗？',
  String systemPrompt = '',
  List<Map<String, dynamic>>? entries,
}) => {
  'name': name,
  'description': description,
  'personality': personality,
  'scenario': scenario,
  'first_mes': firstMes,
  'mes_example': '',
  if (systemPrompt.isNotEmpty) 'system_prompt': systemPrompt,
  'alternate_greetings': <dynamic>[],
  'tags': <dynamic>['fantasy', 'mystery'],
  'creator': 'someone',
  'character_version': '1.0',
  if (entries != null)
    'character_book': {'name': 'world', 'entries': entries},
};

void main() {
  group('CharacterCard.parseJsonMap', () {
    test('parses the V2 envelope', () {
      final card = CharacterCard.parseJsonMap({
        'spec': 'chara_card_v2',
        'spec_version': '2.0',
        'data': cardData(),
      });
      expect(card, isNotNull);
      expect(card!.name, '星尘旅者');
      expect(card.firstMes, contains('流星'));
      expect(card.tags, ['fantasy', 'mystery']);
    });

    test('parses a V1 bare object by normalizing it into data', () {
      final card = CharacterCard.parseJsonMap({
        'name': 'old card',
        'description': 'desc',
        'first_mes': 'hi',
      });
      expect(card, isNotNull);
      expect(card!.name, 'old card');
    });

    test('rejects envelopes without a name', () {
      expect(
        CharacterCard.parseJsonMap({
          'spec': 'chara_card_v2',
          'data': {'description': 'no name'},
        }),
        isNull,
      );
    });

    test('rejects unknown specs', () {
      expect(
        CharacterCard.parseJsonMap({
          'spec': 'something_else',
          'data': {'name': 'x'},
        }),
        isNull,
      );
    });

    test('exposes the character book when present', () {
      final card = CharacterCard.parseJsonMap({
        'spec': 'chara_card_v2',
        'data': cardData(entries: [
          {
            'keys': ['tavern'],
            'content': 'A safe house.',
            'constant': true,
          },
        ]),
      });
      expect(card!.book, isNotNull);
      expect(card.book!.entries.single.keys, ['tavern']);
    });
  });

  group('CharacterCard.composeSystemPrompt', () {
    test('joins description, personality and scenario', () {
      final card = CharacterCard.parseJsonMap({
        'spec': 'chara_card_v2',
        'data': cardData(),
      })!;
      final prompt = card.composeSystemPrompt();
      expect(prompt, startsWith('一位漫游星海的神秘旅人。'));
      expect(prompt, contains('Personality: 冷静、好奇、喜欢打谜语。'));
      expect(prompt, contains('Scenario: 你们在悬崖边的小客栈相遇。'));
    });

    test('card system_prompt leads when provided', () {
      final card = CharacterCard.parseJsonMap({
        'spec': 'chara_card_v2',
        'data': cardData(systemPrompt: 'Stay in character.'),
      })!;
      expect(card.composeSystemPrompt(), startsWith('Stay in character.'));
    });

    test('empty sections are omitted', () {
      final card = CharacterCard.parseJsonMap({
        'spec': 'chara_card_v2',
        'data': cardData(personality: '', scenario: ''),
      })!;
      expect(card.composeSystemPrompt(), '一位漫游星海的神秘旅人。');
    });
  });

  group('CharacterCard.buildEnvelope', () {
    test('wraps data with the V2 spec markers', () {
      final envelope = CharacterCard.buildEnvelope({'name': 'x'});
      expect(envelope['spec'], 'chara_card_v2');
      expect(envelope['spec_version'], '2.0');
      expect((envelope['data'] as Map)['name'], 'x');
    });
  });
}
