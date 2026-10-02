/// Group-chat configuration stored in [Conversation.extras] (drift
/// `conversation_rows.extras_json`).
///
/// A group conversation has an ordered member list of assistant ids. The
/// first member is the host: it owns the conversation-level assistant binding
/// (`Conversation.assistantId`) and any conversation-scoped setting that
/// assumes a single assistant. Replies rotate through members in order (v1:
/// plain round-robin, start offset kept in the stored turn index).
class ConversationGroupChat {
  static const String keyEnabled = 'groupChat.enabled';
  static const String keyMembers = 'groupChat.members';
  static const String keyTurnIndex = 'groupChat.turnIndex';
  static const String keyDirector = 'groupChat.director';
  static const String keyInfinite = 'groupChat.infinite';
  static const String keyTalkToDirector = 'groupChat.talkToDirector';

  /// 伪作者标记：用户↔导演的私聊消息用它写进 `character_id`/`sender_id` 列。
  ///
  /// 这些消息对角色们不可见（`buildApiMessages` 直接跳过），但导演的调度
  /// 上下文包含它们，「接下来让 A 和 B 吵一架」这类舞台指令因此能生效。
  static const String directorMarkerId = '__director__';

  /// Minimum participants for an actual group (a single member is just a
  /// normal 1:1 conversation and must not enable group mode).
  static const int minMembers = 2;

  final bool enabled;
  final List<String> members;
  final int turnIndex;

  /// P5 导演调度：每条回复后由一次隐形元调用决定下一个发言者，
  /// 允许同一人连续发言与两人对谈；关闭时为纯轮转。
  final bool directorEnabled;

  /// P5 无限流（看戏模式）：群聊轮次永不交还用户，角色们自己一直演下去，
  /// 用户插话（发送消息）才结束本轮。定时任务不触发无限流。
  final bool infiniteEnabled;

  /// P5 和导演对话：用户发消息直接给隐形导演（舞台指令/剧情问答），
  /// 不走角色生成管线。角色们看不到这个频道。
  final bool talkToDirector;

  const ConversationGroupChat({
    this.enabled = false,
    this.members = const <String>[],
    this.turnIndex = 0,
    this.directorEnabled = false,
    this.infiniteEnabled = false,
    this.talkToDirector = false,
  });

  bool get isGroup => enabled && members.length >= minMembers;

  /// The host assistant id, or null when this is not an active group.
  String? get hostId => isGroup ? members.first : null;

  static ConversationGroupChat fromExtras(Map<String, dynamic> extras) {
    final members =
        (extras[keyMembers] as List?)?.cast<String>() ?? const <String>[];
    return ConversationGroupChat(
      enabled: extras[keyEnabled] as bool? ?? false,
      members: members,
      turnIndex: (extras[keyTurnIndex] as num?)?.toInt() ?? 0,
      directorEnabled: extras[keyDirector] as bool? ?? false,
      infiniteEnabled: extras[keyInfinite] as bool? ?? false,
      talkToDirector: extras[keyTalkToDirector] as bool? ?? false,
    );
  }

  /// Returns a new map with the group config written. Disabled or
  /// under-populated groups remove the keys instead of leaving junk behind.
  Map<String, dynamic> applyTo(Map<String, dynamic> extras) {
    final next = Map<String, dynamic>.from(extras);
    if (!isGroup) {
      next.remove(keyEnabled);
      next.remove(keyMembers);
      next.remove(keyTurnIndex);
      next.remove(keyDirector);
      next.remove(keyInfinite);
      next.remove(keyTalkToDirector);
      return next;
    }
    next[keyEnabled] = enabled;
    next[keyMembers] = members;
    next[keyTurnIndex] = turnIndex;
    next[keyDirector] = directorEnabled;
    next[keyInfinite] = infiniteEnabled;
    next[keyTalkToDirector] = talkToDirector;
    return next;
  }

  ConversationGroupChat copyWith({
    bool? enabled,
    List<String>? members,
    int? turnIndex,
    bool? directorEnabled,
    bool? infiniteEnabled,
    bool? talkToDirector,
  }) {
    return ConversationGroupChat(
      enabled: enabled ?? this.enabled,
      members: members ?? this.members,
      turnIndex: turnIndex ?? this.turnIndex,
      directorEnabled: directorEnabled ?? this.directorEnabled,
      infiniteEnabled: infiniteEnabled ?? this.infiniteEnabled,
      talkToDirector: talkToDirector ?? this.talkToDirector,
    );
  }
}
