import 'dart:convert';

/// SillyTavern Character Card V2 (`chara_card_v2`).
///
/// Only the fields Kelivo consumes are typed; everything else survives
/// round-trips through [CharacterCardData.raw] so an imported card can be
/// re-exported without loss.
typedef CharacterCardData = Map<String, dynamic>;

const String characterCardSpec = 'chara_card_v2';
const String characterCardSpecVersion = '2.0';

class CharacterBookEntry {
  const CharacterBookEntry({
    required this.keys,
    required this.content,
    this.enabled = true,
    this.insertionOrder = 100,
    this.caseSensitive = false,
    this.name = '',
    this.constant = false,
    this.position,
    this.depth,
    this.secondaryKeys = const <String>[],
    this.extensions = const <String, dynamic>{},
  });

  final List<String> keys;
  final String content;
  final bool enabled;
  final int insertionOrder;
  final bool caseSensitive;
  final String name;
  final bool constant;

  /// `before_char` / `after_char` (spec) or `an_top` / `an_bottom` /
  /// `at_depth` (extension values in the wild). Null follows ST defaults.
  final String? position;

  /// Only meaningful with `at_depth`.
  final int? depth;
  final List<String> secondaryKeys;
  final Map<String, dynamic> extensions;

  static CharacterBookEntry fromJson(Map<String, dynamic> json) {
    String? position;
    final extPosition = (json['extensions'] is Map)
        ? (json['extensions'] as Map)['position']
        : null;
    final rawPosition = extPosition ?? json['position'];
    if (rawPosition is String && rawPosition.trim().isNotEmpty) {
      position = rawPosition.trim();
    } else if (rawPosition is num) {
      // Legacy numeric positions: 0 = before char, 1 = after char.
      position = rawPosition.toInt() == 0 ? 'before_char' : 'after_char';
    }
    final depthRaw = (json['extensions'] is Map)
        ? (json['extensions'] as Map)['depth']
        : null;
    return CharacterBookEntry(
      keys: _stringList(json['keys']),
      content: (json['content'] as String?) ?? '',
      enabled: (json['enabled'] as bool?) ?? true,
      insertionOrder:
          (json['insertion_order'] as num?)?.toInt() ??
          (json['priority'] as num?)?.toInt() ??
          100,
      caseSensitive: (json['case_sensitive'] as bool?) ?? false,
      name:
          ((json['name'] as String?) ?? (json['comment'] as String?) ?? '')
              .trim(),
      constant: (json['constant'] as bool?) ?? false,
      position: position,
      depth: (depthRaw as num?)?.toInt(),
      secondaryKeys: _stringList(json['secondary_keys']),
      extensions: json['extensions'] is Map
          ? Map<String, dynamic>.from(json['extensions'] as Map)
          : const <String, dynamic>{},
    );
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const <String>[];
    return [
      for (final e in raw)
        if (e != null && e.toString().trim().isNotEmpty)
          e.toString().trim(),
    ];
  }
}

class CharacterBook {
  const CharacterBook({
    this.name = '',
    this.description = '',
    this.entries = const <CharacterBookEntry>[],
  });

  final String name;
  final String description;
  final List<CharacterBookEntry> entries;

  static CharacterBook? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final rawEntries = map['entries'];
    final entries = <CharacterBookEntry>[];
    if (rawEntries is List) {
      for (final e in rawEntries) {
        if (e is Map) {
          entries.add(
            CharacterBookEntry.fromJson(
              Map<String, dynamic>.from(e),
            ),
          );
        }
      }
    }
    return CharacterBook(
      name: ((map['name'] as String?) ?? '').trim(),
      description: ((map['description'] as String?) ?? '').trim(),
      entries: entries,
    );
  }
}

class CharacterCard {
  const CharacterCard({required this.data, this.book});

  /// The full ST V2 `data` object, kept verbatim for lossless export.
  final CharacterCardData data;
  final CharacterBook? book;

  String get name => ((data['name'] as String?) ?? '').trim();
  String get description => ((data['description'] as String?) ?? '').trim();
  String get personality => ((data['personality'] as String?) ?? '').trim();
  String get scenario => ((data['scenario'] as String?) ?? '').trim();
  String get firstMes => ((data['first_mes'] as String?) ?? '').trim();
  String get systemPrompt =>
      ((data['system_prompt'] as String?) ?? '').trim();
  List<String> get tags => [
    for (final t in (data['tags'] as List?) ?? const <dynamic>[])
      if (t != null && t.toString().trim().isNotEmpty)
        t.toString().trim(),
  ];

  /// Compose the Kelivo assistant system prompt from the card fields.
  ///
  /// Plain labelled sections — the RP prompt engine (P2) builds on this.
  String composeSystemPrompt() {
    final buf = StringBuffer();
    void section(String label, String text) {
      final t = text.trim();
      if (t.isEmpty) return;
      if (buf.isNotEmpty) buf.writeln();
      buf.writeln(label.isEmpty ? t : '$label: $t');
    }

    section('', systemPrompt);
    section('', description);
    section('Personality', personality);
    section('Scenario', scenario);
    return buf.toString().trim();
  }

  /// Parse a card JSON map. Accepts both the V2 envelope
  /// (`{spec, spec_version, data}`) and bare data objects (V1 cards).
  static CharacterCard? parseJsonMap(Map<String, dynamic> json) {
    final spec = (json['spec'] as String?)?.trim();
    final dataRaw = json['data'];
    final Map<String, dynamic> data;
    if (spec == characterCardSpec && dataRaw is Map) {
      data = Map<String, dynamic>.from(dataRaw);
    } else if (spec == null && json.containsKey('name')) {
      // V1-style bare object; normalize into a data map.
      data = Map<String, dynamic>.from(json);
    } else {
      return null;
    }
    if (((data['name'] as String?) ?? '').trim().isEmpty) return null;
    return CharacterCard(
      data: data,
      book: CharacterBook.fromJson(data['character_book']),
    );
  }

  /// Parse the embedded JSON of a card (already base64-decoded).
  static CharacterCard? parseEmbeddedJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return parseJsonMap(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return null;
  }

  /// Wrap [data] into the V2 envelope used for embedding and export.
  static Map<String, dynamic> buildEnvelope(CharacterCardData data) => {
    'spec': characterCardSpec,
    'spec_version': characterCardSpecVersion,
    'data': data,
  };
}
