import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/memory_entry.dart';
import 'package:Kelivo/core/services/memory/memory_retrieval.dart';

MemoryEntry _entry({
  required String id,
  required String content,
  required DateTime updatedAt,
  MemoryType type = MemoryType.plotEvent,
}) {
  return MemoryEntry(
    id: id,
    scope: MemoryScope.global,
    type: type,
    content: content,
    createdAt: updatedAt,
    updatedAt: updatedAt,
  );
}

void main() {
  group('MemoryRetrieval.selectEntries', () {
    test(
      'P0-b acceptance: the round-1 entry is recalled at round 50',
      () {
        // Round 1: the user mentions an ear piercing; the extractor writes it.
        final round1 = _entry(
          id: 'mem_round01',
          content: '用户的左耳有一个耳洞。',
          updatedAt: DateTime(2026, 9, 1, 8),
        );
        // Rounds 2..49 write unrelated plot entries, each newer than the last.
        final middle = List.generate(48, (i) {
          return _entry(
            id: 'mem_round${(i + 2).toString().padLeft(2, '0')}',
            content: '剧情推进事件 ${i + 2}：酒馆战斗、旅行与新的城镇。',
            updatedAt: DateTime(2026, 9, 1, 9).add(Duration(hours: i)),
          );
        });
        // Round 50 talks about the earring again.
        final queryText = '用户：你还记得我耳朵上有什么吗？\n'
            '助手：你提起过耳朵上的装饰。\n'
            '用户：对，就是耳洞那边。';

        final picked = MemoryRetrieval.selectEntries(
          entries: [round1, ...middle],
          maxItems: 10,
          queryText: queryText,
        );

        expect(picked, contains(round1));
        // The storyline stays: recency quota is filled by the newest entries.
        expect(picked.length, 10);
      },
    );

    test('empty query keeps pure recency selection', () {
      final entries = List.generate(12, (i) {
        return _entry(
          id: 'mem_${i.toString().padLeft(2, '0')}',
          content: 'entry $i',
          updatedAt: DateTime(2026, 1, 1).add(Duration(days: i)),
        );
      });

      final picked = MemoryRetrieval.selectEntries(
        entries: entries,
        maxItems: 10,
      );

      // The 10 newest survive; the two oldest are dropped.
      expect(picked.map((e) => e.id), everyElement(isNot('mem_00')));
      expect(picked.map((e) => e.id), isNot(contains('mem_01')));
      expect(picked.length, 10);
    });

    test('recency quota keeps the storyline alongside relevant old entries', () {
      final oldRelevant = _entry(
        id: 'mem_old',
        content: '用户角色背负着断剑，来自北方的雪山村庄。',
        updatedAt: DateTime(2026, 1, 1),
      );
      final filler = List.generate(20, (i) {
        return _entry(
          id: 'mem_fill${i.toString().padLeft(2, '0')}',
          content: '无关的剧情事件 $i',
          updatedAt: DateTime(2026, 2, 1).add(Duration(days: i)),
        );
      });

      final picked = MemoryRetrieval.selectEntries(
        entries: [oldRelevant, ...filler],
        maxItems: 10,
        queryText: '用户：我的断剑呢？\n助手：你还背着那把断剑。',
      );

      expect(picked, contains(oldRelevant));
      expect(picked.length, 10);
    });

    test('below the limit everything is returned', () {
      final entries = List.generate(5, (i) {
        return _entry(
          id: 'mem_$i',
          content: 'entry $i',
          updatedAt: DateTime(2026, 1, 1).add(Duration(days: i)),
        );
      });
      final picked = MemoryRetrieval.selectEntries(
        entries: entries,
        maxItems: 10,
        queryText: 'entry',
      );
      expect(picked.length, 5);
    });
  });

  group('MemoryRetrieval.relevanceScore / tokensForQuery', () {
    test('scores by token overlap and ignores disjoint content', () {
      final query = MemoryRetrieval.tokensForQuery(
        '用户：耳洞还疼吗？\n助手：你提到过耳朵。',
      );
      expect(query, isNotEmpty);
      expect(
        MemoryRetrieval.relevanceScore('用户的左耳有一个耳洞。', query),
        greaterThan(0),
      );
      expect(
        MemoryRetrieval.relevanceScore(' completely unrelated topic ', query),
        0,
      );
    });

    test('tokensForQuery caps at maxQueryTokens', () {
      final buffer = StringBuffer();
      for (var i = 0; i < 100; i++) {
        buffer.writeln('keyword$i 词汇$i');
      }
      final tokens = MemoryRetrieval.tokensForQuery(buffer.toString());
      expect(tokens.length, MemoryRetrieval.maxQueryTokens);
    });

    test('tokensForQuery of blank text is empty', () {
      expect(MemoryRetrieval.tokensForQuery('  \n  '), isEmpty);
      expect(MemoryRetrieval.tokensForQuery(null), isEmpty);
    });
  });
}
