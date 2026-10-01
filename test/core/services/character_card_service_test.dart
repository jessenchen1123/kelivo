import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/models/character_card.dart';
import 'package:Kelivo/core/models/world_book.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/world_book_provider.dart';
import 'package:Kelivo/core/services/character_card_codec.dart';
import 'package:Kelivo/core/services/character_card_service.dart';

import '../../support/business_test_harness.dart';

Map<String, dynamic> cardData() => {
  'name': '星尘旅者',
  'description': '一位漫游星海的神秘旅人。',
  'personality': '冷静、好奇。',
  'scenario': '你们在客栈相遇。',
  'first_mes': '*她抬起头* 你也看见那颗流星了吗？',
  'mes_example': '',
  'tags': ['fantasy'],
  'creator': 'someone',
  'character_book': {
    'name': '世界设定',
    'entries': [
      {
        'keys': ['tavern', '客栈'],
        'content': '悬崖边的小客栈，旅人的据点。',
        'insertion_order': 500,
        'position': 'before_char',
        'case_sensitive': true,
      },
      {
        'keys': [],
        'content': '这个世界魔力稀薄，星辰有灵。',
        'constant': true,
      },
      {
        'keys': ['moon'],
        'content': '月亮升起时魔法增强。',
        'position': 'an_top',
      },
      {
        'keys': ['ritual'],
        'content': '召唤仪式需要三根蜡烛。',
        'position': 'at_depth',
        'extensions': {'depth': 3},
      },
      {'keys': ['disabled'], 'content': 'x', 'enabled': false},
      {'keys': ['empty'], 'content': '   '},
    ],
  },
};

CharacterCard cardFromData() =>
    CharacterCard.parseJsonMap(CharacterCard.buildEnvelope(cardData()))!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CharacterCardMapper.buildAssistant', () {
    test('maps persona, greeting and RP defaults', () {
      final assistant = CharacterCardMapper.buildAssistant(
        id: 'char-1',
        card: cardFromData(),
        avatarPath: '/avatars/x.png',
      );

      expect(assistant.id, 'char-1');
      expect(assistant.name, '星尘旅者');
      expect(assistant.isCharacter, isTrue);
      expect(assistant.avatar, '/avatars/x.png');
      expect(assistant.useAssistantAvatar, isTrue);
      expect(assistant.useAssistantName, isTrue);
      // RP memory defaults (P0-a): remember, self-scoped.
      expect(assistant.enableMemory, isTrue);
      expect(assistant.autoOrganizeMemory, isTrue);
      expect(assistant.memoryWriteScope, MemoryWriteScope.alwaysAssistant);
      // Greeting becomes an assistant preset message.
      expect(assistant.presetMessages, hasLength(1));
      expect(assistant.presetMessages.single.role, 'assistant');
      expect(assistant.presetMessages.single.content, contains('流星'));
      // Persona composed into the system prompt.
      expect(assistant.systemPrompt, contains('一位漫游星海的神秘旅人。'));
      expect(assistant.systemPrompt, contains('Personality: 冷静、好奇。'));
      // Card data kept verbatim for lossless export.
      expect(assistant.characterCardData!['creator'], 'someone');
    });

    test('no greeting → no preset messages', () {
      final data = cardData()..['first_mes'] = '';
      final assistant = CharacterCardMapper.buildAssistant(
        id: 'c2',
        card: CharacterCard.parseJsonMap(CharacterCard.buildEnvelope(data))!,
      );
      expect(assistant.presetMessages, isEmpty);
    });
  });

  group('CharacterCardMapper.buildWorldBook', () {
    test('maps entries with positions, constants and order', () {
      final book = CharacterCardMapper.buildWorldBook(
        bookId: 'wb-1',
        card: cardFromData(),
      );

      expect(book, isNotNull);
      expect(book!.name, '世界设定');
      expect(book.entries, hasLength(5)); // empty-content entry dropped

      final tavern = book.entries[0];
      expect(tavern.keywords, ['tavern', '客栈']);
      expect(tavern.constantActive, isFalse);
      expect(tavern.position, WorldBookInjectionPosition.beforeSystemPrompt);
      expect(tavern.priority, 500);
      expect(tavern.caseSensitive, isTrue);

      final constant = book.entries[1];
      expect(constant.constantActive, isTrue);
      expect(constant.keywords, isEmpty);

      final moon = book.entries[2];
      expect(moon.position, WorldBookInjectionPosition.topOfChat);

      final ritual = book.entries[3];
      expect(ritual.position, WorldBookInjectionPosition.atDepth);
      expect(ritual.injectDepth, 3);

      // Disabled entries keep their flag (user can re-enable).
      expect(book.entries.any((e) => !e.enabled), isTrue);
    });

    test('returns null when the card has no usable entries', () {
      final data = cardData()..remove('character_book');
      final book = CharacterCardMapper.buildWorldBook(
        bookId: 'wb-2',
        card: CharacterCard.parseJsonMap(CharacterCard.buildEnvelope(data))!,
      );
      expect(book, isNull);
    });
  });

  group('CharacterCardMapper.buildEnvelope', () {
    test('re-exports stored card data verbatim', () {
      final assistant = CharacterCardMapper.buildAssistant(
        id: 'c3',
        card: cardFromData(),
      );
      final envelope = CharacterCardMapper.buildEnvelope(assistant);
      expect(envelope['spec'], 'chara_card_v2');
      expect((envelope['data'] as Map)['creator'], 'someone');
      expect(
        (envelope['data'] as Map)['character_book'],
        isA<Map>(),
      );
    });

    test('synthesizes an envelope from a plain assistant', () {
      const plain = Assistant(
        id: 'a1',
        name: '老兵',
        systemPrompt: '你是一位沉默的老兵。',
        presetMessages: [],
      );
      final envelope = CharacterCardMapper.buildEnvelope(plain);
      final data = envelope['data'] as Map;
      expect(data['name'], '老兵');
      expect(data['description'], '你是一位沉默的老兵。');
      expect(data['first_mes'], '');
    });
  });

  group('CharacterCardCodec round trip through the service', () {
    test('an exported PNG re-imports with the same character', () async {
      SharedPreferences.setMockInitialValues({});
      // Avatar files land under AppDirectories → path_provider; mock the
      // platform channel so the imported PNG really is written and readable.
      const avatarRoot = '/tmp/kelivo_character_card_test';
      Directory(avatarRoot).createSync(recursive: true);
      const pathProviderChannel = MethodChannel(
        'plugins.flutter.io/path_provider',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory' ||
            call.method == 'getApplicationSupportDirectory') {
          return avatarRoot;
        }
        return null;
      });
      final preferences = createBusinessTestPreferences();
      final assistants = AssistantProvider(preferences: preferences);
      final worldBooks = WorldBookProvider(preferences: preferences);

      // A card PNG: embed the envelope into a synthetic avatar PNG.
      final avatar = CharacterCardCodec.encodeCardPng(
        pngBytes: _minimalPng(),
        cardEnvelope: CharacterCard.buildEnvelope(cardData()),
      );

      final service = CharacterCardService(
        assistants: assistants,
        worldBooks: worldBooks,
      );
      final id = await service.importFromPngBytes(avatar);

      final imported = assistants.getById(id);
      expect(imported, isNotNull);
      expect(imported!.avatar!.startsWith('/tmp/kelivo_character_card_test'), isTrue);
      expect(imported!.name, '星尘旅者');
      expect(imported.presetMessages.single.content, contains('流星'));

      // The bound world book was created and activated for this character.
      final books = worldBooks.books;
      expect(books, hasLength(1));
      expect(
        worldBooks.activeBookIdsFor(id),
        contains(books.single.id),
      );
      expect(books.single.entries.length, 5);

      // Export → import round trip preserves the persona.
      final exported = await service.exportToPngBytes(imported);
      expect(exported, isNotNull);
      final again = CharacterCardCodec.decodeCard(exported);
      expect(again!.name, '星尘旅者');
      expect(again.book, isNotNull);
    });
  });
}

/// Minimal but structurally valid 1×1 RGBA PNG.
Uint8List _minimalPng() {
  final out = BytesBuilder();
  out.add(CharacterCardCodec.pngSignature);
  void chunk(String type, List<int> data) {
    final len = ByteData(4)..setUint32(0, data.length);
    final crc = ByteData(4)
      ..setUint32(0, CharacterCardCodec.crc32([...latin1.encode(type), ...data]));
    out.add(len.buffer.asUint8List());
    out.add(latin1.encode(type));
    out.add(data);
    out.add(crc.buffer.asUint8List());
  }

  chunk('IHDR', [0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0]);
  chunk('IDAT', [1, 2, 3, 4]);
  chunk('IEND', const []);
  return out.toBytes();
}
