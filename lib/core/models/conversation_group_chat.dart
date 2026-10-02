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

  /// Minimum participants for an actual group (a single member is just a
  /// normal 1:1 conversation and must not enable group mode).
  static const int minMembers = 2;

  final bool enabled;
  final List<String> members;
  final int turnIndex;

  /// P5 导演调度：每条回复后由一次隐形元调用决定下一个发言者，
  /// 允许同一人连续发言与两人对谈；关闭时为纯轮转。
  final bool directorEnabled;

  const ConversationGroupChat({
    this.enabled = false,
    this.members = const <String>[],
    this.turnIndex = 0,
    this.directorEnabled = false,
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
      return next;
    }
    next[keyEnabled] = enabled;
    next[keyMembers] = members;
    next[keyTurnIndex] = turnIndex;
    next[keyDirector] = directorEnabled;
    return next;
  }

  ConversationGroupChat copyWith({
    bool? enabled,
    List<String>? members,
    int? turnIndex,
    bool? directorEnabled,
  }) {
    return ConversationGroupChat(
      enabled: enabled ?? this.enabled,
      members: members ?? this.members,
      turnIndex: turnIndex ?? this.turnIndex,
      directorEnabled: directorEnabled ?? this.directorEnabled,
    );
  }
}
