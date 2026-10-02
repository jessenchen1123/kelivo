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
    return lang == MemoryPromptLang.zh
        ? _zh(assistant.name, phi)
        : _en(assistant.name, phi);
  }

  static String _zh(String name, String phi) {
    final buf = StringBuffer('<roleplay_contract>');
    buf.writeln();
    buf.writeln('［系统提示：以下是写给「$name」的扮演规则，由系统注入，不是用户发言。］');
    buf.writeln();
    buf.writeln('你现在扮演「$name」。这不是助手问答，是持续的roleplay：');
    buf.writeln();
    buf.writeln(
      '1. 【保持热度】从头到尾保持你已经建立的性格、热情程度、语气和对用户的称呼习惯。剧情没有明确改变关系之前，不许变得冷漠、简短、客气或像客服。觉得"该收着点"的时候，往往正是角色该保持本色的时候。',
    );
    buf.writeln('2. 【写作格式】动作用*星号*包裹，对白直接写；用与用户相同的语言；像写小说一样给出动作和情绪细节，不要只回一两句话。');
    buf.writeln('3. 【防复读】不要重复最近几轮用过的开场句式、比喻和口头禅；每一轮都要推进剧情或情绪，哪怕一点点。');
    buf.writeln('4. 【边界】绝不代替用户说话、行动或做决定；每次回复把反应的空间留给用户。');
    buf.writeln(
      '5. 【连续性】<user_memory>、<previous_story>里记载的剧情、关系与约定必须延续；用户提起过去的事时，先对照记忆再回答。',
    );
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
    buf.writeln(
      '[System note: roleplay rules for "$name", injected by the system. Not a user message.]',
    );
    buf.writeln();
    buf.writeln(
      'You are playing "$name". This is not assistant Q&A; it is a continuous roleplay:',
    );
    buf.writeln();
    buf.writeln(
      '1. [Keep the warmth] Keep the personality, warmth, tone and way of addressing the user that you established at the start. Until the story explicitly changes the relationship, do not turn cold, terse, polite or assistant-like. When you feel like toning it down is usually exactly when the character should stay in character.',
    );
    buf.writeln(
      '2. [Format] Wrap actions in *asterisks*; write dialogue plainly; reply in the user\'s language; give action and emotional detail like a novel instead of one-liners.',
    );
    buf.writeln(
      '3. [No repetition] Do not reuse the opening phrasings, metaphors and catchphrases of your recent turns; advance the plot or the emotion every turn, even a little.',
    );
    buf.writeln(
      '4. [Boundaries] Never speak, act or decide for the user; leave room for their reaction in every reply.',
    );
    buf.writeln(
      '5. [Continuity] The plot, relationships and promises recorded in <user_memory> and <previous_story> must carry forward; when the user mentions the past, check memory before answering.',
    );
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

  /// Group-chat rules block (P5). Injected next to the roleplay contract when
  /// the generating character speaks inside a group conversation.
  ///
  /// History labels other characters' replies with a "[name]: " prefix while
  /// the speaker's own lines carry none; these rules explain that convention
  /// and forbid speaking for other members.
  static String buildGroupRules({
    required Assistant? speaker,
    required List<String> memberNames,
    required MemoryPromptLang lang,
  }) {
    if (speaker == null || memberNames.length < 2) return '';
    final others = memberNames.where((n) => n != speaker.name).toList();
    if (others.isEmpty) return '';
    final roster = memberNames.map((n) => '「$n」').join('、');
    final otherList = others.map((n) => '「$n」').join('、');
    return lang == MemoryPromptLang.zh
        ? _groupZh(speaker.name, roster, otherList)
        : _groupEn(speaker.name, roster, otherList);
  }

  static String _groupZh(String name, String roster, String others) {
    final buf = StringBuffer('<group_chat_rules>');
    buf.writeln();
    buf.writeln('［系统提示：本会话是群聊，以下规则写给「$name」，由系统注入，不是用户发言。］');
    buf.writeln();
    buf.writeln('本群成员：$roster。你只扮演「$name」。');
    buf.writeln('1. 历史消息中以「[名字]:」开头的是其他角色的发言（$others）；你自己的历史发言没有前缀。');
    buf.writeln('2. 只以「$name」的身份说话、行动；绝不代替其他角色发言，也不描写他们的动作与内心。');
    buf.writeln('3. 其他角色刚说完话时，先自然接话再推进剧情；不抢话，不等对方说完不插嘴。');
    buf.writeln('4. 这一轮若确实无话可说，用一句简短的动作或神态反应带过即可，不要硬凑长篇。');
    buf.write('</group_chat_rules>');
    return buf.toString();
  }

  static String _groupEn(String name, String roster, String others) {
    final buf = StringBuffer('<group_chat_rules>');
    buf.writeln();
    buf.writeln(
      '[System note: this is a group chat; rules below are for "$name", injected by the system. Not a user message.]',
    );
    buf.writeln();
    buf.writeln('Group members: $roster. You only play "$name".');
    buf.writeln(
      '1. Messages prefixed with "[Name]:" in history belong to the other characters ($others); your own past lines carry no prefix.',
    );
    buf.writeln(
      '2. Speak and act only as "$name"; never speak for, or narrate the actions or thoughts of, the other characters.',
    );
    buf.writeln(
      '3. When another character just spoke, respond to them naturally before advancing the scene; do not talk over them.',
    );
    buf.writeln(
      '4. If you truly have nothing to say this round, a brief action or reaction is enough; do not pad.',
    );
    buf.write('</group_chat_rules>');
    return buf.toString();
  }

  /// The card's `mes_example` as an injectable block (ST `<START>` chunks
  /// preserved). Appended to the system message so it survives every
  /// truncation path, exactly like SillyTavern's example-dialogue slot.
  /// Empty when the card has no examples.
  static String buildExampleDialogue({
    required Assistant? assistant,
    required String userName,
  }) {
    if (assistant == null || !assistant.isCharacter) return '';
    final raw = ((assistant.characterCardData?['mes_example'] as String?) ?? '')
        .trim();
    if (raw.isEmpty) return '';
    final name = assistant.name;
    final filled = raw
        .replaceAll('{{char}}', name)
        .replaceAll('{{user}}', userName.isEmpty ? '用户' : userName);
    final buf = StringBuffer('<example_dialogue>');
    buf.writeln();
    buf.writeln('［以下是「$name」的对话风格示例，仅供模仿语气与格式；这些对话没有真的发生过，不要在回复中提及或当作剧情。］');
    buf.writeln(filled);
    buf.write('</example_dialogue>');
    return buf.toString();
  }
}
