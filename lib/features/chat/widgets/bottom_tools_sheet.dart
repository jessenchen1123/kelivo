import '../utils/prompt_injection_selection.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/assistant.dart';
import '../../../core/models/conversation_group_chat.dart';
import '../../../core/models/skills_binding.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/instruction_injection_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/haptics.dart';
import '../../../core/services/skills/skills_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/world_book_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../home/widgets/instruction_injection_sheet.dart';
import '../../home/widgets/world_book_sheet.dart';
import '../../instruction_injection/pages/instruction_injection_page.dart';
import '../../character/pages/character_library_page.dart';
import '../../world_book/pages/world_book_page.dart';
import '../../model/widgets/ocr_prompt_sheet.dart';
import '../../workspace/pages/skills_page.dart';
import '../../workspace/widgets/skills/conversation_skills_sheet.dart';
import '../utils/ensure_conversation.dart';
import 'group_chat_member_picker.dart';
import 'package:Kelivo/theme/app_semantic_colors.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../theme/app_font_weights.dart';
import 'tools_sheet_row.dart';

/// Row that opens the session skills picker, and pushes the skills library on
/// a long press.
const Key sessionSkillsKey = ValueKey<String>('bottom-tools-session-skills');

class BottomToolsSheet extends StatelessWidget {
  const BottomToolsSheet({
    super.key,
    this.onCamera,
    this.onPhotos,
    this.onUpload,
    this.onClear,
    this.clearLabel,
    this.assistantId,
    this.conversationId,
    this.onClose,
    this.onStartGroupChat,
  });

  final VoidCallback? onCamera;
  final VoidCallback? onPhotos;
  final VoidCallback? onUpload;
  final VoidCallback? onClear;
  final String? clearLabel;
  final String? assistantId;
  final String? conversationId;
  final VoidCallback? onClose;

  /// P5 群聊：成员多选完成后回调（建群逻辑在持有 ChatController 的宿主里）。
  final ValueChanged<({List<String> members, bool director})>? onStartGroupChat;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bg = context.overlaySurface;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.8;

    Widget roundedAction({
      required IconData icon,
      required String label,
      VoidCallback? onTap,
    }) {
      final cardColor = sheetTileColor(context);
      return Expanded(
        child: SizedBox(
          height: 72,
          child: IosCardPress(
            baseColor: cardColor,
            borderRadius: BorderRadius.circular(14),
            pressedScale: 0.98,
            duration: const Duration(milliseconds: 260),
            onTap: () {
              Haptics.light();
              onTap?.call();
            },
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 24,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  const SizedBox(height: 6),
                  Text(label, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Theme.of(
                context,
              ).colorScheme.shadow.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ..._attachmentActions(
                      l10n: l10n,
                      roundedAction: roundedAction,
                    ),
                    _LearningAndClearSection(
                      clearLabel: clearLabel,
                      onClear: onClear,
                      assistantId: assistantId,
                      conversationId: conversationId,
                      onClose: onClose,
                      onStartGroupChat: onStartGroupChat,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _attachmentActions({
    required AppLocalizations l10n,
    required Widget Function({
      required IconData icon,
      required String label,
      VoidCallback? onTap,
    })
    roundedAction,
  }) {
    final actions = <Widget>[
      if (onCamera != null)
        roundedAction(
          icon: Lucide.Camera,
          label: l10n.bottomToolsSheetCamera,
          onTap: onCamera,
        ),
      if (onPhotos != null)
        roundedAction(
          icon: Lucide.Image,
          label: l10n.bottomToolsSheetPhotos,
          onTap: onPhotos,
        ),
      if (onUpload != null)
        roundedAction(
          icon: Lucide.Paperclip,
          label: l10n.bottomToolsSheetUpload,
          onTap: onUpload,
        ),
    ];
    if (actions.isEmpty) return const [];
    return [
      Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            actions[i],
          ],
        ],
      ),
      const SizedBox(height: 12),
    ];
  }
}

class _LearningAndClearSection extends StatefulWidget {
  const _LearningAndClearSection({
    this.onClear,
    this.clearLabel,
    this.assistantId,
    this.conversationId,
    this.onClose,
    this.onStartGroupChat,
  });
  final VoidCallback? onClear;
  final String? clearLabel;
  final String? assistantId;
  final String? conversationId;
  final VoidCallback? onClose;

  /// P5 群聊：成员多选完成后回调（建群逻辑在持有 ChatController 的宿主里）。
  final ValueChanged<({List<String> members, bool director})>? onStartGroupChat;

  @override
  State<_LearningAndClearSection> createState() =>
      _LearningAndClearSectionState();
}

class _LearningAndClearSectionState extends State<_LearningAndClearSection> {
  String? _promptConversationId;

  Future<String?> _promptScopeId() async {
    if (_assistant()?.allowConversationPromptInjection != true) return null;
    return _promptConversationId ??= await ensureConversationId(
      context,
      conversationId: widget.conversationId,
      assistantId: widget.assistantId,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Future.wait([
        context.read<WorldBookProvider>().initialize(),
        context.read<InstructionInjectionProvider>().initialize(),
      ]);
    });
  }

  Assistant? _assistant({bool listen = false}) {
    try {
      final provider = Provider.of<AssistantProvider>(context, listen: listen);
      final id = widget.assistantId;
      if (id != null) return provider.getById(id);
      return provider.currentAssistant;
    } catch (_) {
      return null;
    }
  }

  /// P5：当前会话是否为群聊（决定是否显示导演调度开关）。
  bool _isGroupConversation(ChatService chat) {
    final id = widget.conversationId;
    if (id == null) return false;
    return ConversationGroupChat.fromExtras(
      chat.getConversation(id)?.extras ?? const {},
    ).isGroup;
  }

  /// P5：当前群聊会话是否启用导演调度。
  bool _isDirectorEnabled(ChatService chat) {
    final id = widget.conversationId;
    if (id == null) return false;
    return ConversationGroupChat.fromExtras(
      chat.getConversation(id)?.extras ?? const {},
    ).directorEnabled;
  }

  /// P5：当前群聊会话是否启用无限流（看戏模式）。
  bool _isInfiniteEnabled(ChatService chat) {
    final id = widget.conversationId;
    if (id == null) return false;
    return ConversationGroupChat.fromExtras(
      chat.getConversation(id)?.extras ?? const {},
    ).infiniteEnabled;
  }

  Future<void> _openSessionSkills() async {
    Haptics.light();
    final id = await ensureConversationId(
      context,
      conversationId: _promptConversationId ?? widget.conversationId,
      assistantId: widget.assistantId,
    );
    if (id == null || !mounted) return;
    _promptConversationId = id;
    await showConversationSkillsSheet(
      context,
      conversationId: id,
      assistant: _assistant(),
    );
  }

  /// P5 群聊：多选角色后交给宿主建群。
  Future<void> _startGroupChat(BuildContext context) async {
    final result = await showGroupChatMemberPicker(context);
    if (result == null || result.members.length < 2) return;
    if (!context.mounted) return;
    Navigator.of(context).maybePop();
    widget.onStartGroupChat?.call((
      members: result.members,
      director: result.director,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final worldBookProvider = context.watch<WorldBookProvider>();
    final injections = context.watch<InstructionInjectionProvider>();
    final skills = context.watch<SkillsService>();
    final chat = context.watch<ChatService>();
    final assistant = _assistant(listen: true);
    final hasOcrModel =
        settings.ocrModelProvider != null && settings.ocrModelId != null;
    final hasWorldBooks = worldBookProvider.books.isNotEmpty;
    final scoped = assistant?.allowConversationPromptInjection == true;
    final scopeId = _promptConversationId ?? widget.conversationId;
    Set<String> activeIds(PromptSelectionKind kind) => scoped && scopeId == null
        ? <String>{}
        : promptSelectionIds(
            context,
            kind: kind,
            assistantId: widget.assistantId,
            conversationId: scoped ? scopeId : null,
          ).toSet();
    final activeWorldBookIds = activeIds(PromptSelectionKind.worldBook);
    final enabledWorldBookCount = worldBookProvider.books
        .where((book) => book.enabled && activeWorldBookIds.contains(book.id))
        .length;
    final activeInstructionIds = activeIds(PromptSelectionKind.instruction);
    final enabledInstructionCount = injections.items
        .where((item) => activeInstructionIds.contains(item.id))
        .length;
    final skillBinding = SkillsBinding.fromExtras(
      scopeId == null
          ? const {}
          : chat.getConversation(scopeId)?.extras ?? const {},
    );
    final enabledSkillCount = skills
        .resolveForAssistant(
          assistant,
          conversationOverride: skillBinding.skillIds,
        )
        .length;
    final chevron = ToolsSheetRow.chevron(context);
    Widget selectionTrailing(int enabled, int total) => enabled == 0
        ? chevron
        : Text(
            '$enabled/$total',
            style: TextStyle(
              fontSize: 13,
              fontWeight: AppFontWeights.medium,
              color: Theme.of(context).colorScheme.primary,
            ),
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ToolsSheetRow(
          icon: Lucide.Drama,
          label: l10n.characterLibraryPageTitle,
          subtitle: l10n.characterLibraryEntrySubtitle,
          onTap: () {
            Haptics.light();
            final rootNav = Navigator.of(context, rootNavigator: true);
            Navigator.of(context).maybePop();
            Future.microtask(() {
              if (!rootNav.mounted) return;
              rootNav.push(
                MaterialPageRoute(builder: (_) => const CharacterLibraryPage()),
              );
            });
          },
          trailing: chevron,
        ),
        const SizedBox(height: 8),
        ToolsSheetRow(
          icon: Lucide.MessagesSquare,
          label: l10n.groupChatRowLabel,
          subtitle: l10n.groupChatRowSubtitle,
          onTap: () {
            Haptics.light();
            _startGroupChat(context);
          },
          trailing: chevron,
        ),
        const SizedBox(height: 8),
        ToolsSheetRow(
          key: sessionSkillsKey,
          icon: Lucide.WandSparkles,
          label: l10n.workspaceEntrySessionSkills,
          onTap: () => unawaited(_openSessionSkills()),
          onLongPress: () {
            Haptics.light();
            final rootNav = Navigator.of(context, rootNavigator: true);
            Navigator.of(context).maybePop();
            Future.microtask(() {
              if (!rootNav.mounted) return;
              unawaited(openSkillsPage(rootNav.context));
            });
          },
          trailing: selectionTrailing(enabledSkillCount, skills.skills.length),
        ),
        const SizedBox(height: 8),
        ToolsSheetRow(
          icon: Lucide.Layers,
          label: l10n.instructionInjectionTitle,
          onTap: () async {
            Haptics.light();
            final scoped =
                _assistant()?.allowConversationPromptInjection == true;
            final scopeId = await _promptScopeId();
            if (!context.mounted || (scoped && scopeId == null)) return;
            await showInstructionInjectionSheet(
              context,
              assistantId: widget.assistantId,
              conversationId: scopeId,
            );
          },
          onLongPress: () {
            Haptics.light();
            final rootNav = Navigator.of(context, rootNavigator: true);
            Navigator.of(context).maybePop();
            Future.microtask(() {
              rootNav.push(
                MaterialPageRoute(
                  builder: (_) => const InstructionInjectionPage(),
                ),
              );
            });
          },
          trailing: selectionTrailing(
            enabledInstructionCount,
            injections.items.length,
          ),
        ),
        if (hasWorldBooks) ...[
          const SizedBox(height: 8),
          ToolsSheetRow(
            icon: Lucide.BookOpen,
            label: l10n.worldBookTitle,
            onTap: () async {
              Haptics.light();
              final scoped =
                  _assistant()?.allowConversationPromptInjection == true;
              final scopeId = await _promptScopeId();
              if (!context.mounted || (scoped && scopeId == null)) return;
              await showWorldBookSheet(
                context,
                assistantId: widget.assistantId,
                conversationId: scopeId,
              );
            },
            onLongPress: () {
              Haptics.light();
              final rootNav = Navigator.of(context, rootNavigator: true);
              Navigator.of(context).maybePop();
              Future.microtask(() {
                rootNav.push(
                  MaterialPageRoute(builder: (_) => const WorldBookPage()),
                );
              });
            },
            trailing: selectionTrailing(
              enabledWorldBookCount,
              worldBookProvider.books.length,
            ),
          ),
        ],
        if (hasOcrModel) ...[
          const SizedBox(height: 8),
          ToolsSheetRow(
            icon: Lucide.Eye,
            label: l10n.bottomToolsSheetOcr,
            selected: settings.ocrEnabled,
            onTap: () async {
              Haptics.light();
              final sp = context.read<SettingsProvider>();
              await sp.setOcrEnabled(!sp.ocrEnabled);
              if (!context.mounted) return;
              Navigator.of(context).maybePop();
            },
            onLongPress: () => showOcrPromptSheet(context),
          ),
        ],
        const SizedBox(height: 8),
        ToolsSheetRow(
          icon: Lucide.Maximize,
          label: l10n.immersiveModeRowLabel,
          subtitle: l10n.immersiveModeRowSubtitle,
          selected: settings.immersiveChatMode,
          onTap: () async {
            Haptics.light();
            final sp = context.read<SettingsProvider>();
            await sp.setImmersiveChatMode(!sp.immersiveChatMode);
            if (!context.mounted) return;
            Navigator.of(context).maybePop();
          },
        ),
        // P5 导演调度开关：仅群聊会话显示，切换当前会话的调度策略。
        if (_isGroupConversation(chat)) ...[
          const SizedBox(height: 8),
          ToolsSheetRow(
            icon: Lucide.Drama,
            label: l10n.groupChatDirectorToggleLabel,
            subtitle: l10n.groupChatDirectorToggleSubtitle,
            selected: _isDirectorEnabled(chat),
            onTap: () async {
              Haptics.light();
              final id = widget.conversationId;
              if (id == null) return;
              await chat.updateConversationExtras(id, (extras) {
                final group = ConversationGroupChat.fromExtras(extras);
                if (!group.isGroup) return extras;
                return group
                    .copyWith(directorEnabled: !group.directorEnabled)
                    .applyTo(extras);
              });
              if (!context.mounted) return;
              Navigator.of(context).maybePop();
            },
          ),
          // P5 无限流开关：让角色们自己一直演下去，用户插话才结束本轮。
          const SizedBox(height: 8),
          ToolsSheetRow(
            icon: Lucide.Infinity,
            label: l10n.groupChatInfiniteToggleLabel,
            subtitle: l10n.groupChatInfiniteToggleSubtitle,
            selected: _isInfiniteEnabled(chat),
            onTap: () async {
              Haptics.light();
              final id = widget.conversationId;
              if (id == null) return;
              await chat.updateConversationExtras(id, (extras) {
                final group = ConversationGroupChat.fromExtras(extras);
                if (!group.isGroup) return extras;
                return group
                    .copyWith(infiniteEnabled: !group.infiniteEnabled)
                    .applyTo(extras);
              });
              if (!context.mounted) return;
              Navigator.of(context).maybePop();
            },
          ),
        ],
        const SizedBox(height: 8),
        ToolsSheetRow(
          icon: Lucide.workflow,
          label: l10n.contextManagement,
          onTap: () {
            Haptics.light();
            widget.onClear?.call();
          },
          trailing: chevron,
        ),
      ],
    );
  }
}
