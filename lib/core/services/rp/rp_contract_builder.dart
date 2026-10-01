import '../../models/assistant.dart';
import '../memory/memory_prompts.dart';

/// The roleplay contract injected near the END of the context for imported
/// characters.
///
/// Long conversations dilute the persona in the system prompt: recent turns
/// dominate and the model drifts from warm to terse/cold (observed in the
/// wild as "火热 → 高冷"). SillyTavern solves this with
/// `post_history_instructions`; this block combines that field with
/// anti-drift and formatting rules and rides at the bottom of every request
/// where attention is highest.
abstract final class RpContractBuilder {
  /// Build the contract block. Empty when [assistant] is not a character.
  static String build(Assistant? assistant, MemoryPromptLang lang) {
    if (assistant == null || !assistant.isCharacter) return '';
    final data = assistant.characterCardData ?? const <String, dynamic>{};
    final phi = ((data['post_history_instructions'] as String?) ?? '').trim();
    return lang == MemoryPromptLang.zh ? _zh(assistant.name, phi) : _en(assistant.name, phi);
  }

  static String _zh(String name, String phi) {
    final buf = StringBuffer('<roleplay_contract>');
    buf.writeln();
    buf.writeln('［系统提示：以下是写给「$name」的扮演规则，由系统注入，不是用户发言。］');
    buf.writeln();
    buf.writeln('你现在扮演「$name」。这不是助手问答，是持续的roleplay：');
    buf.writeln();
    buf.writeln('1. 【保持热度】从头到尾保持你已经建立的性格、热情程度、语气和对用户的称呼习惯。剧情没有明确改变关系之前，不许变得冷漠、简短、客气或像客服。觉得"该收着点"的时候，往往正是角色该保持本色的时候。');
    buf.writeln('2. 【写作格式】动作用*星号*包裹，对白直接写；用与用户相同的语言；像写小说一样给出动作和情绪细节，不要只回一两句话。');
    buf.writeln('3. 【边界】绝不代替用户说话、行动或做决定；每次回复把反应的空间留给用户。');
    buf.writeln('4. 【连续性】<user_memory>、<previous_story>里记载的剧情、关系与约定必须延续；用户提起过去的事时，先对照记忆再回答。');
    if (phi.isNotEmpty) {
      buf.writeln();
      buf.writeln('【卡片附加指令（优先级高于上述条款）】');
      buf.write(phi);
      buf.writeln();
    }
    buf.write('</roleplay_contract>');
    return buf.toString();
  }

  static String _en(String name, String phi) {
    final buf = StringBuffer('<roleplay_contract>');
    buf.writeln();
    buf.writeln('[System note: roleplay rules for "$name", injected by the system. Not a user message.]');
    buf.writeln();
    buf.writeln('You are playing "$name". This is not assistant Q&A; it is a continuous roleplay:');
    buf.writeln();
    buf.writeln('1. [Keep the warmth] Keep the personality, warmth, tone and way of addressing the user that you established at the start. Until the story explicitly changes the relationship, do not turn cold, terse, polite or assistant-like. When you feel like toning it down is usually exactly when the character should stay in character.');
    buf.writeln('2. [Format] Wrap actions in *asterisks*; write dialogue plainly; reply in the user\'s language; give action and emotional detail like a novel instead of one-liners.');
    buf.writeln('3. [Boundaries] Never speak, act or decide for the user; leave room for their reaction in every reply.');
    buf.writeln('4. [Continuity] The plot, relationships and promises recorded in <user_memory> and <previous_story> must carry forward; when the user mentions the past, check memory before answering.');
    if (phi.isNotEmpty) {
      buf.writeln();
      buf.writeln('[Card-specific instructions (override the rules above)]');
      buf.write(phi);
      buf.writeln();
    }
    buf.write('</roleplay_contract>');
    return buf.toString();
  }

  /// Whether [assistant] would produce a non-empty contract.
  static bool appliesTo(Assistant? assistant) =>
      assistant != null && assistant.isCharacter;
}
