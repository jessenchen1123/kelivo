import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../models/assistant.dart';
import '../models/character_card.dart';
import '../models/preset_message.dart';
import '../models/world_book.dart';
import '../providers/assistant_provider.dart';
import '../providers/world_book_provider.dart';
import '../../utils/app_directories.dart';
import 'character_card_codec.dart';

/// Pure card → Kelivo-model mapping (no Flutter provider dependencies).
abstract final class CharacterCardMapper {
  /// Build the character assistant. [avatarPath] is the already-managed copy
  /// of the card PNG (null leaves the avatar unset).
  static Assistant buildAssistant({
    required String id,
    required CharacterCard card,
    String? avatarPath,
  }) {
    return Assistant(
      id: id,
      name: card.name,
      avatar: avatarPath,
      useAssistantAvatar: avatarPath != null,
      useAssistantName: true,
      systemPrompt: card.composeSystemPrompt(),
      presetMessages: card.firstMes.isEmpty
          ? const <PresetMessage>[]
          : <PresetMessage>[PresetMessage(role: 'assistant', content: card.firstMes)],
      // RP defaults: a character remembers (P0 root cause #1) and keeps its
      // memories scoped to itself so characters never leak each other's plot.
      enableMemory: true,
      autoOrganizeMemory: true,
      memoryWriteScope: MemoryWriteScope.alwaysAssistant,
      limitContextMessages: false,
      characterCardData: card.data,
    );
  }

  /// Map the ST character_book onto a Kelivo world book. Returns null when
  /// the card has no book or all entries are empty.
  static WorldBook? buildWorldBook({
    required String bookId,
    required CharacterCard card,
  }) {
    final book = card.book;
    if (book == null || book.entries.isEmpty) return null;

    final entries = <WorldBookEntry>[];
    for (final e in book.entries) {
      if (e.content.trim().isEmpty) continue;
      entries.add(_mapEntry(e));
    }
    if (entries.isEmpty) return null;

    return WorldBook(
      id: bookId,
      name: book.name.isNotEmpty ? book.name : card.name,
      description: book.description,
      enabled: true,
      entries: entries,
    );
  }

  static WorldBookEntry _mapEntry(CharacterBookEntry e) {
    return WorldBookEntry(
      id: const Uuid().v4(),
      name: e.name,
      enabled: e.enabled,
      priority: e.insertionOrder,
      position: _mapPosition(e.position),
      content: e.content.trim(),
      injectDepth: (e.depth ?? 4).clamp(1, 200),
      role: WorldBookInjectionRole.user,
      keywords: e.keys,
      useRegex: false,
      caseSensitive: e.caseSensitive,
      scanDepth: 4,
      // ST `constant` entries inject without keywords; Kelivo has the same
      // concept and it is how character base settings stay always-on.
      constantActive: e.constant,
      sticky: 0,
      cooldown: 0,
      delay: 0,
    );
  }

  static WorldBookInjectionPosition _mapPosition(String? st) {
    switch (st) {
      case 'before_char':
        return WorldBookInjectionPosition.beforeSystemPrompt;
      case 'an_top':
        return WorldBookInjectionPosition.topOfChat;
      case 'an_bottom':
        return WorldBookInjectionPosition.bottomOfChat;
      case 'at_depth':
        return WorldBookInjectionPosition.atDepth;
      case 'after_char':
        return WorldBookInjectionPosition.afterSystemPrompt;
      default:
        // ST default is before_char; treat unknown values as after_char to
        // keep lore close to the character block without hiding the persona.
        return st == null
            ? WorldBookInjectionPosition.beforeSystemPrompt
            : WorldBookInjectionPosition.afterSystemPrompt;
    }
  }

  /// Rebuild the card envelope from an assistant. Import assistants carry
  /// their original `data` verbatim; synthesized exports fill the required
  /// fields from the assistant itself.
  static Map<String, dynamic> buildEnvelope(Assistant assistant) {
    final stored = assistant.characterCardData;
    if (stored != null && stored.isNotEmpty) {
      return CharacterCard.buildEnvelope(stored);
    }
    String firstMes = '';
    for (final pm in assistant.presetMessages) {
      if (pm.role == 'assistant' && pm.content.trim().isNotEmpty) {
        firstMes = pm.content;
        break;
      }
    }
    return CharacterCard.buildEnvelope({
      'name': assistant.name,
      'description': assistant.systemPrompt,
      'first_mes': firstMes,
      'personality': '',
      'scenario': '',
      'mes_example': '',
      'creator_notes': '',
      'system_prompt': '',
      'post_history_instructions': '',
      'alternate_greetings': const <dynamic>[],
      'tags': const <dynamic>[],
      'creator': '',
      'character_version': '',
      'extensions': const <String, dynamic>{},
    });
  }
}

/// Provider-backed import/export orchestration.
class CharacterCardService {
  CharacterCardService({required this.assistants, required this.worldBooks});

  final AssistantProvider assistants;
  final WorldBookProvider worldBooks;

  /// Result of [importFromPngBytes].
  ({String assistantId, int worldBookEntryCount})? _lastImport;
  ({String assistantId, int worldBookEntryCount})? get lastImport =>
      _lastImport;

  /// Parse [pngBytes] as a character card PNG and install it: assistant +
  /// avatar file + bound world book. Returns the new assistant id.
  Future<String> importFromPngBytes(List<int> pngBytes) async {
    final card = CharacterCardCodec.decodeCard(pngBytes);
    if (card == null) {
      throw const CharacterCardFormatException('no character card in PNG');
    }

    final id = const Uuid().v4();
    final avatarPath = await _writeAvatarFile(id, pngBytes);
    final assistant = CharacterCardMapper.buildAssistant(
      id: id,
      card: card,
      avatarPath: avatarPath,
    );

    WorldBook? book;
    var entryCount = 0;
    if (card.book != null && card.book!.entries.isNotEmpty) {
      book = CharacterCardMapper.buildWorldBook(
        bookId: const Uuid().v4(),
        card: card,
      );
      if (book != null) {
        entryCount = book.entries.length;
        await worldBooks.addBook(book);
      }
    }

    await assistants.addAssistantObject(assistant);
    if (book != null) {
      await worldBooks.setActiveBookIds([book.id], assistantId: id);
    }
    _lastImport = (assistantId: id, worldBookEntryCount: entryCount);
    return id;
  }

  Future<String> _writeAvatarFile(String assistantId, List<int> bytes) async {
    try {
      final dir = await AppDirectories.getAvatarsDirectory();
      if (!await dir.exists()) await dir.create(recursive: true);
      final safeId = assistantId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final file = File(
        '${dir.path}/assistant_${safeId}_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return ''; // avatar is optional; character still imports
    }
  }

  /// Export [assistant] as a character-card PNG. Returns null when the
  /// assistant has no PNG avatar to embed (the JSON alone cannot be written).
  Future<Uint8List?> exportToPngBytes(Assistant assistant) async {
    List<int>? png;
    final path = (assistant.avatar ?? '').trim();
    if (path.isNotEmpty && !path.startsWith('http') && !path.startsWith('data:')) {
      try {
        final file = File(path);
        if (await file.exists()) {
          png = await file.readAsBytes();
        }
      } catch (_) {
        png = null;
      }
    }
    if (png == null || !CharacterCardCodec.isPng(png)) return null;
    return CharacterCardCodec.encodeCardPng(
      pngBytes: png,
      cardEnvelope: CharacterCardMapper.buildEnvelope(assistant),
    );
  }
}

class CharacterCardFormatException implements Exception {
  const CharacterCardFormatException(this.message);
  final String message;

  @override
  String toString() => 'CharacterCardFormatException: $message';
}
