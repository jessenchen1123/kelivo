import 'dart:convert';

import '../../../core/models/assistant.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../core/services/logging/flutter_logger.dart';

/// Who the group-chat director tells to speak next.
enum GroupDirectorDecision { speaker, endTurn }

class GroupDirectorVerdict {
  const GroupDirectorVerdict({
    required this.decision,
    this.nextCharacterId,
    this.reason,
  });

  final GroupDirectorDecision decision;

  /// Character (assistant) id chosen to speak next; null when [decision] is
  /// [GroupDirectorDecision.endTurn] or the verdict could not be resolved.
  final String? nextCharacterId;

  /// One-line explanation from the director, for the context log.
  final String? reason;
}

/// P5 群聊导演模式：每条回复结束后由一次轻量的元调用决定下一个发言者。
///
/// 导演不是群成员——它不占角色位、没有气泡、不写记忆，只做调度。输入是
/// 成员名单（名字+一句话身份）、带 `[名字]:` 前缀的最近对话和护栏状态，
/// 输出是严格的 JSON：`{"next": "名字|USER", "reason": "一句话"}`。
///
/// 任何失败（网络、解析、无效名字）都返回 [endTurn] 兜底：宁可把话语权
/// 交还用户，也不能让群聊卡死或刷屏。
abstract final class GroupDirector {
  /// Same character may speak at most this many times in a row.
  static const int maxConsecutiveSameSpeaker = 3;

  /// Label used for the human user in the director transcript.
  static const String userNicknameLabel = '用户';

  /// Hard cap on generated replies per user message, so a confused director
  /// cannot keep a round alive forever.
  static int maxRepliesPerRound(int memberCount) =>
      memberCount <= 0 ? 4 : memberCount * 2;

  /// Builds the director prompt. Kept pure for testability.
  ///
  /// [infinite] is the "endless show" mode: the human is a spectator, so the
  /// director must always pick a member and never hand the turn back.
  static String buildPrompt({
    required List<({String name, String identity})> roster,
    required List<({String speaker, String content})> recent,
    required String userNickname,
    required Map<String, int> speakCounts,
    required MemoryPromptLangLike lang,
    bool infinite = false,
  }) {
    final buf = StringBuffer();
    if (lang == MemoryPromptLangLike.zh) {
      buf.writeln('你是角色群聊的导演（隐形调度者），负责决定此刻谁最适合开口。');
      buf.writeln();
      buf.writeln('群成员（名字 — 身份）：');
      for (final member in roster) {
        buf.writeln('- 「${member.name}」：${member.identity}');
      }
      buf.writeln();
      buf.writeln('最近对话（[名字] 为说话者，「用户」是真人）：');
      for (final turn in recent) {
        buf.writeln('[${turn.speaker}]: ${turn.content}');
      }
      buf.writeln();
      buf.writeln('本轮已发言次数：');
      for (final member in roster) {
        buf.writeln('- 「${member.name}」：${speakCounts[member.name] ?? 0}');
      }
      buf.writeln();
      buf.writeln('判断规则：');
      buf.writeln('1. 直接被提问、被点名回应的人优先开口。');
      buf.writeln('2. 剧情需要时允许同一人连续发言（如分段讲故事、连续动作）。');
      buf.writeln('3. 两人自然对谈时可以让他们交替，其他人不必每轮都插话。');
      if (infinite) {
        buf.writeln(
          '4. 这是一场不会停的即兴演出：真人用户是旁观者、不参与对话，'
          '绝不要选 USER，永远从成员里选下一位把戏接下去。',
        );
        buf.writeln('5. 不要让所有成员轮流把同一件事点评一遍。');
      } else {
        buf.writeln('4. 对话自然收尾、或接下来轮到用户行动时，选 USER。');
        buf.writeln('5. 不要让所有成员轮流把同一件事点评一遍。');
      }
      buf.writeln();
      buf.write(
        infinite
            ? '只输出 JSON（不要其他文字）：{"next": "成员名字", "reason": "一句话理由"}'
            : '只输出 JSON（不要其他文字）：{"next": "成员名字或USER", "reason": "一句话理由"}',
      );
    } else {
      buf.writeln(
        'You are the invisible director of a character group chat; decide who should speak next.',
      );
      buf.writeln();
      buf.writeln('Group members (name — identity):');
      for (final member in roster) {
        buf.writeln('- "${member.name}": ${member.identity}');
      }
      buf.writeln();
      buf.writeln(
        'Recent turns ([name] is the speaker; "用户"/user is the human):',
      );
      for (final turn in recent) {
        buf.writeln('[${turn.speaker}]: ${turn.content}');
      }
      buf.writeln();
      buf.writeln('Times spoken this round:');
      for (final member in roster) {
        buf.writeln('- "${member.name}": ${speakCounts[member.name] ?? 0}');
      }
      buf.writeln();
      buf.writeln('Rules:');
      buf.writeln(
        '1. Whoever was directly addressed or asked a question speaks first.',
      );
      buf.writeln(
        '2. The same character may speak several times in a row when the scene calls for it.',
      );
      buf.writeln(
        '3. Two characters in a natural exchange may alternate; the others need not chime in.',
      );
      if (infinite) {
        buf.writeln(
          '4. This is an endless improvisation: the human is a spectator who does not participate. '
          'Never answer USER — always pick the next member to carry the scene forward.',
        );
        buf.writeln(
          '5. Do not let every member comment on the same thing in turn.',
        );
      } else {
        buf.writeln(
          '4. When the scene settles or it is the user\'s turn to act, answer USER.',
        );
        buf.writeln(
          '5. Do not let every member comment on the same thing in turn.',
        );
      }
      buf.writeln();
      buf.write(
        infinite
            ? 'Output JSON only (no other text): {"next": "member name", "reason": "one short sentence"}'
            : 'Output JSON only (no other text): {"next": "member name or USER", "reason": "one short sentence"}',
      );
    }
    return buf.toString();
  }

  /// Extracts the first JSON object from a model reply (models sometimes wrap
  /// it in code fences).
  static Map<String, dynamic>? parseVerdictJson(String raw) {
    var text = raw.trim();
    final fenceStart = text.indexOf('{');
    final fenceEnd = text.lastIndexOf('}');
    if (fenceStart >= 0 && fenceEnd > fenceStart) {
      text = text.substring(fenceStart, fenceEnd + 1);
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  /// Asks the director who speaks next. Returns endTurn on any failure.
  ///
  /// [recentTurns] are preformatted recent messages (speaker label + clipped
  /// content), newest last. [userMessageText] is the fresh user message when
  /// the round is starting (not yet in history). Names must be unique across
  /// the roster — duplicates make the verdict unresolvable and the caller
  /// falls back to rotation.
  static Future<GroupDirectorVerdict> decideNextSpeaker({
    required List<({String name, String identity})> roster,
    required List<({String speaker, String content})> recentTurns,
    String? userMessageText,
    required String providerKey,
    required String modelId,
    required ProviderConfig Function(String providerKey) providerConfigOf,
    required bool useZhPrompts,
    required Map<String, int> speakCountsByName,
    required Map<String, String> memberNamesById,
    bool infinite = false,
  }) async {
    final names = memberNamesById.values.toSet();
    if (names.length != memberNamesById.length) {
      return const GroupDirectorVerdict(
        decision: GroupDirectorDecision.endTurn,
      );
    }
    final recent = <({String speaker, String content})>[...recentTurns];
    if (userMessageText != null && userMessageText.isNotEmpty) {
      recent.add((speaker: userNicknameLabel, content: userMessageText));
    }
    final prompt = buildPrompt(
      roster: roster,
      recent: recent,
      userNickname: userNicknameLabel,
      speakCounts: speakCountsByName,
      lang: useZhPrompts ? MemoryPromptLangLike.zh : MemoryPromptLangLike.en,
      infinite: infinite,
    );
    try {
      final config = providerConfigOf(providerKey);
      final raw = await ChatApiService.generateText(
        config: config,
        modelId: modelId,
        prompt: prompt,
        extraBody: const {'temperature': 0.2},
      );
      final verdict = parseVerdictJson(raw);
      final next = (verdict?['next'] ?? '').toString().trim();
      final reason = (verdict?['reason'] ?? '').toString().trim();
      FlutterLogger.log(
        '[GroupDirector] next=$next reason=$reason',
        tag: 'GroupDirector',
      );
      if (next.toUpperCase() == 'USER' || next.isEmpty) {
        return GroupDirectorVerdict(
          decision: GroupDirectorDecision.endTurn,
          reason: reason.isEmpty ? null : reason,
        );
      }
      for (final entry in memberNamesById.entries) {
        if (entry.value.trim() == next) {
          return GroupDirectorVerdict(
            decision: GroupDirectorDecision.speaker,
            nextCharacterId: entry.key,
            reason: reason.isEmpty ? null : reason,
          );
        }
      }
      // Unknown name: the model hallucinated a member.
      return const GroupDirectorVerdict(
        decision: GroupDirectorDecision.endTurn,
      );
    } catch (e) {
      FlutterLogger.log(
        '[GroupDirector] decision failed, ending round: $e',
        tag: 'GroupDirector',
      );
      return const GroupDirectorVerdict(
        decision: GroupDirectorDecision.endTurn,
      );
    }
  }

  /// Clips a transcript line to keep the director call light.
  static String clipText(String text, [int max = 200]) => _clip(text, max);

  /// One-line identity for the director roster: card description, else a
  /// system-prompt snippet, else a generic label.
  static String identityOf(Assistant member) {
    final data = member.characterCardData;
    final description = ((data?['description'] as String?) ?? '').trim();
    if (description.isNotEmpty) return _clip(description, 60);
    final systemPrompt = member.systemPrompt.trim();
    if (systemPrompt.isNotEmpty) return _clip(systemPrompt, 60);
    return member.isCharacter ? '角色' : '助手';
  }

  static String _clip(String text, [int max = 160]) {
    final flat = text.replaceAll('\n', ' ').trim();
    if (flat.length <= max) return flat;
    return '${flat.substring(0, max)}…';
  }
}

/// Local stand-in for MemoryPromptLang to avoid importing the memory layer
/// into this file's API surface.
enum MemoryPromptLangLike { zh, en }
