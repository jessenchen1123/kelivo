import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/chat/utils/assistant_narration_splitter.dart';

void main() {
  group('splitAssistantNarration', () {
    test('pulls whole-line narration out of dialogue', () {
      final segments = splitAssistantNarration(
        '*她抬起头，望向夜空*\n你也看见那颗流星了吗？\n*轻笑*',
      );
      expect(segments, hasLength(3));
      expect(segments[0].narration, isTrue);
      expect(segments[0].text, '她抬起头，望向夜空');
      expect(segments[1].narration, isFalse);
      expect(segments[1].text, '你也看见那颗流星了吗？');
      expect(segments[2].narration, isTrue);
      expect(segments[2].text, '轻笑');
    });

    test('consecutive narration lines merge into one block', () {
      final segments = splitAssistantNarration('*走近一步*\n*压低声音*\n别出声。');
      expect(segments, hasLength(2));
      expect(segments[0].narration, isTrue);
      expect(segments[0].text, '走近一步\n压低声音');
    });

    test('bold lines and mixed lines stay dialogue', () {
      final segments = splitAssistantNarration('**整行加粗不是旁白**\n*动作*对白连写\n普通句子');
      expect(segments, hasLength(1));
      expect(segments.single.narration, isFalse);
    });

    test('unclosed streaming narration stays dialogue', () {
      final segments = splitAssistantNarration('你好\n*她还没说完');
      expect(segments, hasLength(1));
      expect(segments.single.narration, isFalse);
    });

    test('no asterisks returns the text untouched', () {
      final text = '第一行\n第二行';
      final segments = splitAssistantNarration(text);
      expect(segments, hasLength(1));
      expect(segments.single.narration, isFalse);
      expect(segments.single.text, text);
    });

    test('pure narration content works too', () {
      final segments = splitAssistantNarration('*夜色渐深*');
      expect(segments, hasLength(1));
      expect(segments.single.narration, isTrue);
      expect(segments.single.text, '夜色渐深');
    });

    test('whole-line parentheses are narration too', () {
      final segments = splitAssistantNarration(
        '（她抬起头，望向夜空）\n你也看见那颗流星了吗？\n(she looks up)',
      );
      expect(segments, hasLength(3));
      expect(segments[0].narration, isTrue);
      expect(segments[0].text, '她抬起头，望向夜空');
      expect(segments[1].narration, isFalse);
      expect(segments[2].narration, isTrue);
      expect(segments[2].text, 'she looks up');
    });

    test('a trailing action aside leaves the bubble', () {
      final segments = splitAssistantNarration('"我没事。"（她笑了笑）');
      expect(segments, hasLength(2));
      expect(segments[0].narration, isFalse);
      expect(segments[0].text, '"我没事。"');
      expect(segments[1].narration, isTrue);
      expect(segments[1].text, '她笑了笑');
    });

    test('a leading action aside leaves the bubble', () {
      final segments = splitAssistantNarration('（她笑了笑）"我没事。"');
      expect(segments, hasLength(2));
      expect(segments[0].narration, isTrue);
      expect(segments[0].text, '她笑了笑');
      expect(segments[1].narration, isFalse);
      expect(segments[1].text, '"我没事。"');
    });

    test('inline parentheses mid-sentence stay in the bubble', () {
      for (final text in <String>['他走过来（手里拿着花）', '答案是 (A)', '她说（笑）了出来']) {
        final segments = splitAssistantNarration(text);
        expect(segments, hasLength(1), reason: text);
        expect(segments.single.narration, isFalse, reason: text);
        expect(segments.single.text, text, reason: text);
      }
    });

    test('unclosed parentheses while streaming stay dialogue', () {
      final segments = splitAssistantNarration('你好\n（她还没说完');
      expect(segments, hasLength(1));
      expect(segments.single.narration, isFalse);
    });
  });
}
