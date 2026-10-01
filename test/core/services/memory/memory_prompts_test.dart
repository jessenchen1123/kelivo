import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:timezone/data/latest.dart' as tz_data;
// ignore: depend_on_referenced_packages
import 'package:timezone/timezone.dart' as tz;

import 'package:Kelivo/core/services/memory/memory_prompts.dart';

void main() {
  group('formatCurrentTimeTag (§9.1)', () {
    test('ISO 8601 includes signed offsets, fractional hours and DST', () {
      tz_data.initializeTimeZones();
      for (final sample in [
        ('Asia/Shanghai', 1, '+08:00'),
        ('Asia/Kolkata', 1, '+05:30'),
        ('Asia/Kathmandu', 1, '+05:45'),
        ('America/St_Johns', 1, '-03:30'),
        ('America/Los_Angeles', 1, '-08:00'),
        ('America/Los_Angeles', 7, '-07:00'),
        ('Europe/London', 1, '+00:00'),
      ]) {
        final timestamp = tz.TZDateTime(
          tz.getLocation(sample.$1),
          2026,
          sample.$2,
          5,
          9,
          8,
          7,
        );
        final month = sample.$2.toString().padLeft(2, '0');
        final formatted = MemoryPrompts.formatCurrentTimeTag(
          timestamp,
          useIso8601: true,
        );
        expect(
          formatted,
          '<current_time>2026-$month-05T09:08:07${sample.$3}</current_time>',
        );
        final value = formatted.replaceAll(RegExp(r'</?current_time>'), '');
        expect(DateTime.parse(value).isAtSameMomentAs(timestamp), isTrue);
      }
    });

    test(
      'ISO 8601 converts UTC inputs to local time without changing the instant',
      () {
        final timestamp = DateTime.utc(2026, 1, 1, 0, 0, 1);
        final formatted = MemoryPrompts.formatCurrentTimeTag(
          timestamp,
          useIso8601: true,
        );
        expect(
          formatted,
          MemoryPrompts.formatCurrentTimeTag(
            timestamp.toLocal(),
            useIso8601: true,
          ),
        );
        final value = formatted.replaceAll(RegExp(r'</?current_time>'), '');
        expect(DateTime.parse(value), timestamp);
      },
    );

    test(
      'formats across weekdays, year boundary, and single-digit month/day',
      () {
        // 2026-08-03 is a Monday in the Gregorian calendar.
        final monday = DateTime(2026, 8, 3, 14, 3, 22);
        expect(monday.weekday, DateTime.monday);
        expect(
          MemoryPrompts.formatCurrentTimeTag(monday),
          '<current_time>Mon 2026-08-03 14:03:22</current_time>',
        );

        final samples = <DateTime, String>{
          DateTime(2026, 8, 3, 0, 0, 0): 'Mon',
          DateTime(2026, 8, 4, 0, 0, 0): 'Tue',
          DateTime(2026, 8, 5, 0, 0, 0): 'Wed',
          DateTime(2026, 8, 6, 0, 0, 0): 'Thu',
          DateTime(2026, 8, 7, 0, 0, 0): 'Fri',
          DateTime(2026, 8, 8, 0, 0, 0): 'Sat',
          DateTime(2026, 8, 9, 0, 0, 0): 'Sun',
        };
        for (final entry in samples.entries) {
          final formatted = MemoryPrompts.formatCurrentTimeTag(entry.key);
          expect(formatted, contains('<current_time>${entry.value} '));
        }

        // Year boundary uses a four-digit year.
        expect(
          MemoryPrompts.formatCurrentTimeTag(
            DateTime(2025, 12, 31, 23, 59, 59),
          ),
          '<current_time>Wed 2025-12-31 23:59:59</current_time>',
        );
        expect(
          MemoryPrompts.formatCurrentTimeTag(DateTime(2026, 1, 1, 0, 0, 1)),
          '<current_time>Thu 2026-01-01 00:00:01</current_time>',
        );

        // Single-digit month and day are zero-padded.
        expect(
          MemoryPrompts.formatCurrentTimeTag(DateTime(2026, 3, 5, 9, 8, 7)),
          '<current_time>Thu 2026-03-05 09:08:07</current_time>',
        );
      },
    );
  });

  group('detectTimeVariablesInSystemPrompt (§9.3)', () {
    test('detects the three time variables; ignores {timezone}', () {
      expect(
        MemoryPrompts.detectTimeVariablesInSystemPrompt('Today is {cur_date}.'),
        ['{cur_date}'],
      );
      expect(
        MemoryPrompts.detectTimeVariablesInSystemPrompt('Clock: {cur_time}'),
        ['{cur_time}'],
      );
      expect(
        MemoryPrompts.detectTimeVariablesInSystemPrompt('Now {cur_datetime}'),
        ['{cur_datetime}'],
      );
      expect(
        MemoryPrompts.detectTimeVariablesInSystemPrompt(
          'TZ={timezone} locale={locale}',
        ),
        isEmpty,
      );
      // Fixed order: cur_date, cur_time, cur_datetime; {timezone} ignored.
      expect(
        MemoryPrompts.detectTimeVariablesInSystemPrompt(
          '{cur_datetime} {cur_time} {cur_date} {timezone}',
        ),
        ['{cur_date}', '{cur_time}', '{cur_datetime}'],
      );
    });
  });

  group('RP memory rules (P0-a acceptance)', () {
    test('rules name all four roleplay categories in both languages', () {
      for (final rules in [MemoryPrompts.rulesZh, MemoryPrompts.rulesEn]) {
        expect(rules, contains('plot_event'));
        expect(rules, contains('relationship'));
        expect(rules, contains('character_fact'));
        expect(rules, contains('foreshadow'));
      }
      expect(MemoryPrompts.rulesZh, contains('剧情事件'));
      expect(MemoryPrompts.rulesZh, contains('人物关系'));
      expect(MemoryPrompts.rulesZh, contains('约定伏笔'));
      expect(MemoryPrompts.rulesEn, contains('story events'));
    });

    test(
      'the old exclude-casual-topics clause is replaced by plot-memory rules',
      () {
        // Old rule: 用户只是随口提到的话题 → do not write.
        expect(MemoryPrompts.rulesZh.contains('随口提到的话题'), isFalse);
        // New rule: passing remarks that matter to the story must be written.
        expect(MemoryPrompts.rulesZh.contains('哪怕只是顺带提到'), isTrue);
        expect(MemoryPrompts.rulesZh.contains('剧情就会接不上'), isTrue);
        expect(MemoryPrompts.rulesEn.contains('even in passing'), isTrue);
      },
    );

    test('extract prompts harvest from both sides of the dialogue', () {
      expect(MemoryPrompts.extractZh, contains('plot_event'));
      expect(MemoryPrompts.extractZh, contains('foreshadow'));
      expect(MemoryPrompts.extractZh, contains('用户说的话和角色说的话'));
      expect(MemoryPrompts.extractZh.contains('只从用户说的话里提取'), isFalse);
      expect(MemoryPrompts.extractEn, contains('plot_event'));
      expect(MemoryPrompts.extractEn, contains('what the character said and did'));
    });

    test('gate leans inclusive for roleplay conversations', () {
      expect(MemoryPrompts.gateZh, contains('剧情推进'));
      expect(MemoryPrompts.gateZh, contains('宜宽不宜严'));
      expect(MemoryPrompts.gateEn, contains('lean towards true'));
    });
  });
}
