import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/character_card.dart';
import 'package:Kelivo/core/services/character_card_codec.dart';

Uint8List buildTestPng({
  String keyword = 'chara',
  bool includeCard = true,
  String? rawTextPayload,
}) {
  final out = BytesBuilder();
  out.add(CharacterCardCodec.pngSignature);

  void chunk(String type, List<int> data) {
    // PNG layout: <u32 length><type><data><u32 crc32(type+data)>.
    final len = ByteData(4)..setUint32(0, data.length);
    final crc = ByteData(4)
      ..setUint32(0, CharacterCardCodec.crc32([...latin1.encode(type), ...data]));
    out.add(len.buffer.asUint8List());
    out.add(latin1.encode(type));
    out.add(data);
    out.add(crc.buffer.asUint8List());
  }

  // IHDR: 1×1, 8-bit RGBA.
  chunk('IHDR', [0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0]);
  if (includeCard) {
    final envelope = CharacterCard.buildEnvelope({
      'name': '星尘旅者',
      'description': '一位漫游星海的旅人。',
      'first_mes': '你好。',
      'character_book': {
        'name': 'book',
        'entries': [
          {'keys': ['key1'], 'content': 'entry content'},
        ],
      },
    });
    final text = rawTextPayload ??
        base64Encode(utf8.encode(jsonEncode(envelope)));
    chunk('tEXt', [...latin1.encode(keyword), 0, ...latin1.encode(text)]);
  }
  chunk('IDAT', [1, 2, 3, 4]);
  chunk('IEND', const []);
  return out.toBytes();
}

Map<String, dynamic> envelopeFor(String name) =>
    CharacterCard.buildEnvelope({
      'name': name,
      'description': 'd',
      'first_mes': 'hi',
      'character_book': {
        'name': 'book',
        'entries': [
          {'keys': ['key1'], 'content': 'entry content'},
        ],
      },
    });

void main() {
  group('CharacterCardCodec.isPng / readChunks', () {
    test('recognizes the signature', () {
      expect(CharacterCardCodec.isPng(buildTestPng()), isTrue);
      expect(CharacterCardCodec.isPng([1, 2, 3]), isFalse);
    });

    test('walks chunks in order', () {
      final chunks = CharacterCardCodec.readChunks(buildTestPng());
      expect(
        chunks.map((c) => c.type).toList(),
        ['IHDR', 'tEXt', 'IDAT', 'IEND'],
      );
    });
  });

  group('CharacterCardCodec.decodeCard', () {
    test('round-trips a V2 card embedded in a PNG', () {
      final decoded = CharacterCardCodec.decodeCard(buildTestPng());
      expect(decoded, isNotNull);
      expect(decoded!.name, '星尘旅者');
      expect(decoded.book!.entries.single.keys, ['key1']);
    });

    test('falls back to the V3 keyword', () {
      final decoded = CharacterCardCodec.decodeCard(
        buildTestPng(keyword: 'ccv3'),
      );
      expect(decoded, isNotNull);
      expect(decoded!.name, '星尘旅者');
    });

    test('tolerates a data: URI prefix in the payload', () {
      final base64Body = base64Encode(
        utf8.encode(jsonEncode(envelopeFor('uri card'))),
      );
      final decoded = CharacterCardCodec.decodeCard(
        buildTestPng(rawTextPayload: 'data:application/json;base64,$base64Body'),
      );
      expect(decoded, isNotNull);
      expect(decoded!.name, 'uri card');
    });

    test('returns null for a PNG without a card', () {
      expect(
        CharacterCardCodec.decodeCard(buildTestPng(includeCard: false)),
        isNull,
      );
    });

    test('returns null for non-PNG bytes', () {
      expect(
        CharacterCardCodec.decodeCard(utf8.encode('hello, not a png')),
        isNull,
      );
    });
  });

  group('CharacterCardCodec.encodeCardPng', () {
    test('inserts a decodable tEXt chunk after IHDR and keeps the image', () {
      final original = buildTestPng(includeCard: false);
      final embedded = CharacterCardCodec.encodeCardPng(
        pngBytes: original,
        cardEnvelope: envelopeFor('export test'),
      );

      final types = CharacterCardCodec.readChunks(embedded)
          .map((c) => c.type)
          .toList();
      expect(types, ['IHDR', 'tEXt', 'IDAT', 'IEND']);

      final decoded = CharacterCardCodec.decodeCard(embedded);
      expect(decoded, isNotNull);
      expect(decoded!.name, 'export test');
      // The original pixel data survives untouched (IDAT + IEND tail).
      expect(
        embedded.sublist(embedded.length - 12),
        original.sublist(original.length - 12),
      );
    });

    test('rejects non-PNG input', () {
      expect(
        () => CharacterCardCodec.encodeCardPng(
          pngBytes: [1, 2, 3],
          cardEnvelope: envelopeFor('x'),
        ),
        throwsArgumentError,
      );
    });
  });

  group('CharacterCardCodec.crc32', () {
    test('matches known PNG checksums', () {
      // CRC32("IEND") with an empty payload — the standard IEND chunk CRC.
      expect(CharacterCardCodec.crc32(latin1.encode('IEND')), 0xae426082);
      expect(CharacterCardCodec.crc32(latin1.encode('123456789')), 0xcbf43926);
    });
  });
}
