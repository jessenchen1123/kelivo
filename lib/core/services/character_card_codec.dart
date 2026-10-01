import 'dart:convert';
import 'dart:typed_data';

import '../models/character_card.dart';

/// PNG tEXt-chunk codec for SillyTavern character cards.
///
/// A card is a PNG whose `tEXt` chunk with keyword `chara` (V2) or `ccv3`
/// (V3) carries `base64(JSON)` of the card. Chunks live between the 8-byte
/// PNG signature and the IEND chunk; each is
/// `<u32 length><4-byte type><data><u32 crc32(type+data)>`.
abstract final class CharacterCardCodec {
  static const List<int> pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  static const String textKeywordV2 = 'chara';
  static const String textKeywordV3 = 'ccv3';

  /// True when [bytes] starts with the PNG signature.
  static bool isPng(List<int> bytes) {
    if (bytes.length < 8) return false;
    for (var i = 0; i < pngSignature.length; i++) {
      if (bytes[i] != pngSignature[i]) return false;
    }
    return true;
  }

  /// Iterate raw chunks: (type ascii string, data bytes).
  static List<({String type, Uint8List data})> readChunks(List<int> bytes) {
    final out = <({String type, Uint8List data})>[];
    if (!isPng(bytes)) return out;
    final data = Uint8List.fromList(bytes);
    final view = ByteData.sublistView(data);
    var offset = 8;
    while (offset + 8 <= data.length) {
      final length = view.getUint32(offset);
      final type = latin1.decode(data.sublist(offset + 4, offset + 8));
      final dataStart = offset + 8;
      if (dataStart + length + 4 > data.length) break;
      out.add((
        type: type,
        data: Uint8List.sublistView(data, dataStart, dataStart + length),
      ));
      offset = dataStart + length + 4; // data + CRC
    }
    return out;
  }

  /// All `tEXt` chunks as a keyword → text map (Latin-1 per PNG spec).
  static Map<String, String> readTextChunks(List<int> bytes) {
    final out = <String, String>{};
    for (final chunk in readChunks(bytes)) {
      if (chunk.type != 'tEXt') continue;
      final zero = chunk.data.indexOf(0);
      if (zero <= 0) continue;
      final keyword = latin1.decode(chunk.data.sublist(0, zero));
      final text = latin1.decode(chunk.data.sublist(zero + 1));
      out[keyword] = text;
    }
    return out;
  }

  /// Extract a card from PNG bytes. Tries the V2 keyword, then V3.
  /// Returns null when the file is not a PNG or carries no card.
  static CharacterCard? decodeCard(List<int> bytes) {
    if (!isPng(bytes)) return null;
    final texts = readTextChunks(bytes);
    for (final keyword in [textKeywordV2, textKeywordV3]) {
      final payload = texts[keyword];
      if (payload == null || payload.isEmpty) continue;
      final card = _decodeBase64Payload(payload);
      if (card != null) return card;
    }
    // Some exporters write the JSON directly (not base64) into the chunk.
    for (final payload in texts.values) {
      final card = CharacterCard.parseEmbeddedJson(payload);
      if (card != null) return card;
    }
    return null;
  }

  static CharacterCard? _decodeBase64Payload(String payload) {
    final raw = payload.trim();
    if (raw.isEmpty) return null;
    String json;
    try {
      // ST tolerates data: URI prefixes; strip anything before base64 body.
      final comma = raw.indexOf(',');
      final base64Body = raw.startsWith('data:') && comma >= 0
          ? raw.substring(comma + 1)
          : raw;
      json = utf8.decode(base64Decode(base64Body));
    } catch (_) {
      return null;
    }
    return CharacterCard.parseEmbeddedJson(json);
  }

  /// Embed [cardEnvelope] into [pngBytes] as a `tEXt` chunk (inserted right
  /// after IHDR) and return the new PNG. Non-PNG input throws [ArgumentError].
  static Uint8List encodeCardPng({
    required List<int> pngBytes,
    required Map<String, dynamic> cardEnvelope,
    String keyword = textKeywordV2,
  }) {
    if (!isPng(pngBytes)) {
      throw ArgumentError.value(pngBytes, 'pngBytes', 'not a PNG file');
    }
    final source = Uint8List.fromList(pngBytes);
    final view = ByteData.sublistView(source);

    // Locate the end of the mandatory first IHDR chunk and the start of IEND.
    var ihdrEnd = -1;
    var iendStart = source.length;
    {
      var offset = 8;
      while (offset + 8 <= source.length) {
        final length = view.getUint32(offset);
        final type = latin1.decode(source.sublist(offset + 4, offset + 8));
        final dataStart = offset + 8;
        if (type == 'IHDR') {
          ihdrEnd = dataStart + length + 4;
        } else if (type == 'IEND') {
          iendStart = offset;
          break;
        }
        offset = dataStart + length + 4;
      }
    }
    if (ihdrEnd < 0 || ihdrEnd > source.length) {
      throw ArgumentError.value(pngBytes, 'pngBytes', 'missing IHDR chunk');
    }

    final payload = base64Encode(utf8.encode(jsonEncode(cardEnvelope)));
    final textData = <int>[...latin1.encode(keyword), 0, ...latin1.encode(payload)];
    final chunk = _buildChunk('tEXt', textData);

    final result = BytesBuilder(copy: false);
    result.add(source.sublist(0, ihdrEnd));
    result.add(chunk);
    result.add(source.sublist(ihdrEnd, iendStart));
    result.add(source.sublist(iendStart));
    return result.toBytes();
  }

  static Uint8List _buildChunk(String type, List<int> data) {
    final typeBytes = latin1.encode(type);
    if (typeBytes.length != 4) {
      throw ArgumentError('chunk type must be 4 ASCII bytes');
    }
    final crc = ByteData(4)
      ..setUint32(0, _crc32(Uint8List.fromList([...typeBytes, ...data])));
    final length = ByteData(4)..setUint32(0, data.length);
    final body = BytesBuilder(copy: false);
    body.add(length.buffer.asUint8List());
    body.add(Uint8List.fromList(typeBytes));
    body.add(Uint8List.fromList(data));
    body.add(crc.buffer.asUint8List());
    return body.toBytes();
  }

  /// CRC-32 (ISO 3309 / ITU-T V.42), the PNG chunk checksum.
  static int crc32(List<int> bytes) => _crc32(Uint8List.fromList(bytes));

  static int _crc32(Uint8List bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc ^= byte;
      for (var i = 0; i < 8; i++) {
        final mask = -(crc & 1);
        crc = (crc >> 1) ^ (0xedb88320 & mask);
      }
    }
    return (~crc) & 0xffffffff;
  }
}
