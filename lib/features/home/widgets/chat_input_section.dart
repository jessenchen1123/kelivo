import 'package:Kelivo/features/chat/utils/prompt_injection_selection.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/chat_input_data.dart';
import '../../../core/models/assistant.dart';
import '../../../core/services/api/reasoning/reasoning_level_options.dart';
import '../../../core/services/api/reasoning/reasoning_dialects.dart';
import '../../../core/services/api/reasoning/reasoning_selection.dart';
import '../../../core/services/model_spec/model_spec_resolver.dart';
import '../../../core/models/workspace_binding.dart';
import '../../../core/models/conversation_group_chat.dart';
import '../../../core/models/skills_binding.dart';
import '../../../core/providers/asr_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/mcp_provider.dart';
import '../../../core/providers/quick_phrase_provider.dart';
import '../../../core/providers/world_book_provider.dart';
import '../../../core/providers/instruction_injection_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/services/skills/skills_service.dart';
import '../../../features/workspace/widgets/environment/environment_status_chip.dart';
import '../../../features/workspace/workspace_navigation.dart';
import '../../../theme/design_tokens.dart';
import '../../chat/widgets/group_chat_member_picker.dart' show memberAvatar;
import 'chat_input_bar.dart';
import 'model_icon.dart';

/// Callback for checking if a model supports tool calling.
typedef IsToolModelCallback = bool Function(String providerKey, String modelId);

/// Callback for checking if a model supports reasoning.
typedef IsReasoningModelCallback =
    bool Function(String providerKey, String modelId);

/// Callback for checking if reasoning is enabled.
typedef IsReasoningEnabledCallback = bool Function(ReasoningRequest request);

/// Widget that wraps ChatInputBar with all the necessary logic and callbacks.
///
/// This widget extracts the _buildChatInputBar logic from HomePageState
/// to reduce coupling and improve maintainability.
class ChatInputSection extends StatelessWidget {
  const ChatInputSection({
    super.key,
    required this.inputBarKey,
    this.chatModelProviderKey,
    this.chatModelId,
    this.chatModelIsConversationOverride = false,
    required this.inputFocus,
    required this.inputController,
    required this.mediaController,
    required this.isTablet,
    required this.isLoading,
    this.allowSendWhileLoading = false,
    required this.isToolModel,
    required this.isReasoningModel,
    required this.isReasoningEnabled,
    this.onMore,
    this.onSelectModel,
    this.onLongPressSelectModel,
    this.onOpenTools,
    this.onLongPressTools,
    this.onOpenWorkspace,
    this.onOpenSkills,
    this.onOpenSearch,
    this.onConfigureReasoning,
    this.onOpenContextUsage,
    this.onSend,
    this.onStop,
    this.hasQueuedInput = false,
    this.queuedPreviewText,
    this.onCancelQueuedInput,
    this.onExpandedChanged,
    this.onQuickPhrase,
    this.onLongPressQuickPhrase,
    this.onToggleOcr,
    this.onOpenMiniMap,
    this.onPickCamera,
    this.onPickPhotos,
    this.onUploadFiles,
    this.onToggleLearningMode,
    this.onOpenWorldBook, // 新增世界书支持桌面端
    this.onLongPressLearning,
    this.onClearContext,
    this.onCompressContext,
    this.conversationId,
    this.sendButtonTooltip,
    this.backgroundImageActive = false,
  });

  final GlobalKey inputBarKey;
  final FocusNode inputFocus;
  final TextEditingController inputController;
  final ChatInputBarController mediaController;
  final bool isTablet;
  final bool isLoading;

  /// P5 无限流：演出进行中也允许发送（发送即插话）。此时有文字时发送键
  /// 按「发送」处理，空输入时仍是「停止」。
  final bool allowSendWhileLoading;

  // Model capability checkers
  final IsToolModelCallback isToolModel;
  final IsReasoningModelCallback isReasoningModel;
  final IsReasoningEnabledCallback isReasoningEnabled;

  // Callbacks
  final VoidCallback? onMore;
  final VoidCallback? onSelectModel;
  final VoidCallback? onLongPressSelectModel;
  final VoidCallback? onOpenTools;
  final VoidCallback? onLongPressTools;
  final VoidCallback? onOpenWorkspace;
  final VoidCallback? onOpenSkills;
  final VoidCallback? onOpenSearch;
  final VoidCallback? onConfigureReasoning;
  final VoidCallback? onOpenContextUsage;
  final Future<ChatInputSubmissionResult> Function(ChatInputData)? onSend;
  final VoidCallback? onStop;
  final bool hasQueuedInput;
  final String? queuedPreviewText;
  final VoidCallback? onCancelQueuedInput;
  final ValueChanged<bool>? onExpandedChanged;
  final VoidCallback? onQuickPhrase;
  final VoidCallback? onLongPressQuickPhrase;
  final VoidCallback? onToggleOcr;
  final VoidCallback? onOpenMiniMap;
  final VoidCallback? onPickCamera;
  final VoidCallback? onPickPhotos;
  final VoidCallback? onUploadFiles;
  final VoidCallback? onToggleLearningMode;
  final VoidCallback? onOpenWorldBook;
  final VoidCallback? onLongPressLearning;
  final VoidCallback? onClearContext;
  final VoidCallback? onCompressContext;
  final String? conversationId;

  /// The model this conversation sends with, already resolved through
  /// conversation override -> assistant -> global default. Resolved by the
  /// caller because only it holds the Conversation; watching ChatService here
  /// would rebuild the composer on every streaming notification.
  final String? chatModelProviderKey;
  final String? chatModelId;

  /// Whether the resolved model above comes from this conversation's own
  /// override rather than from the assistant.
  ///
  /// Gates the capability enforcement below, which writes to the ASSISTANT: a
  /// model picked for one conversation must not wipe the MCP selection or the
  /// thinking budget shared by every other conversation under that assistant.
  final bool chatModelIsConversationOverride;
  final String? sendButtonTooltip;
  final bool backgroundImageActive;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final asr = context.watch<AsrProvider>();
    final ap = context.watch<AssistantProvider>();
    final a = ap.currentAssistant;

    final pk = chatModelProviderKey;
    final mid = chatModelId;
    final selectedReasoning = _selectedReasoning(settings, a, pk, mid);
    final reasoningSpec = (pk != null && mid != null)
        ? ModelSpecResolver.instance.spec(settings.getProviderConfig(pk), mid)
        : null;
    final effectiveReasoning = reasoningSpec == null
        ? selectedReasoning
        : ReasoningRequest(
            resolveReasoning(reasoningSpec, selectedReasoning).effective,
            budgetTokens: selectedReasoning.budgetTokens,
          );

    // Enforce model capabilities: disable MCP selection if model doesn't
    // support tools. Skipped while the conversation overrides the model —
    // these writes land on the assistant and would leak across conversations.
    if (!chatModelIsConversationOverride) {
      _enforceModelCapabilities(context, settings, ap, a, pk, mid);
    }

    final isDesktop = _isDesktopPlatform(context);
    final hasWorldBooks =
        isTablet && context.watch<WorldBookProvider>().books.isNotEmpty;
    final showWorkspaceButton = isDesktop && onOpenWorkspace != null;
    final showEnvChip = !isDesktop && (Platform.isAndroid || Platform.isIOS);
    var workspaceBound = false;
    if (showWorkspaceButton || showEnvChip) {
      workspaceBound = _isWorkspaceBound(context);
    }

    final bar = ChatInputBar(
      key: inputBarKey,
      chatModelProviderKey: pk,
      chatModelId: mid,
      onMore: onMore,
      onSelectModel: onSelectModel,
      onLongPressSelectModel: onLongPressSelectModel,
      conversationId: conversationId,
      onOpenTools: onOpenTools,
      onLongPressTools: onLongPressTools,
      onOpenWorkspace: onOpenWorkspace,
      showWorkspaceButton: showWorkspaceButton,
      workspaceActive: workspaceBound,
      onOpenSkills: isDesktop ? onOpenSkills : null,
      skillsActive:
          isDesktop && onOpenSkills != null && _isSkillsActive(context, a),
      onStop: onStop,
      modelIcon: (pk != null && mid != null)
          ? CurrentModelIcon(
              providerKey: pk,
              modelId: mid,
              size: 40,
              withBackground: true,
              backgroundColor: Colors.transparent,
            )
          : null,
      focusNode: inputFocus,
      controller: inputController,
      mediaController: mediaController,
      asrProvider: asr,
      onConfigureReasoning: onConfigureReasoning,
      onOpenContextUsage: onOpenContextUsage,
      reasoningActive: isReasoningEnabled(effectiveReasoning),
      reasoning: effectiveReasoning,
      reasoningCustomBudget: reasoningSpec != null
          ? isCustomBudgetSelection(reasoningSpec, selectedReasoning)
          : false,
      supportsReasoning: (pk != null && mid != null)
          ? isReasoningModel(pk, mid)
          : false,
      onOpenSearch: onOpenSearch,
      onSend: onSend,
      loading: isLoading,
      allowSendWhileLoading: allowSendWhileLoading,
      sendButtonTooltip: sendButtonTooltip,
      hasQueuedInput: hasQueuedInput,
      queuedPreviewText: queuedPreviewText,
      onCancelQueuedInput: onCancelQueuedInput,
      onExpandedChanged: onExpandedChanged,
      showToolsButton: _shouldShowToolsButton(pk, mid),
      toolsActive: _isToolsActive(context, a, workspaceBound),
      showQuickPhraseButton: _hasQuickPhrases(context, a),
      onQuickPhrase: onQuickPhrase,
      onLongPressQuickPhrase: onLongPressQuickPhrase,
      // OCR button: show on desktop for mobile layout, always check settings for tablet layout
      showOcrButton: isTablet
          ? (settings.ocrModelProvider != null && settings.ocrModelId != null)
          : (isDesktop &&
                settings.ocrModelProvider != null &&
                settings.ocrModelId != null),
      ocrActive: settings.ocrEnabled,
      onToggleOcr: onToggleOcr,
      // Tablet-specific parameters
      showMiniMapButton: isTablet,
      onOpenMiniMap: isTablet ? onOpenMiniMap : null,
      onPickCamera: isTablet ? (isDesktop ? null : onPickCamera) : null,
      onPickPhotos: isTablet ? (isDesktop ? null : onPickPhotos) : null,
      onUploadFiles: isTablet ? onUploadFiles : null,
      onToggleLearningMode: isTablet ? onToggleLearningMode : null,
      onOpenWorldBook: hasWorldBooks ? onOpenWorldBook : null,
      onLongPressLearning: isTablet ? onLongPressLearning : null,
      learningModeActive:
          isTablet &&
          _isPromptSelectionActive(context, a, PromptSelectionKind.instruction),
      worldBookActive:
          isTablet &&
          _isPromptSelectionActive(context, a, PromptSelectionKind.worldBook),
      showMoreButton: !isTablet,
      onClearContext: isTablet ? onClearContext : null,
      onCompressContext: isTablet ? onCompressContext : null,
      backgroundImageActive: backgroundImageActive,
      inputBackgroundOpacityLight: settings.chatInputBackgroundOpacityLight,
      inputBackgroundOpacityDark: settings.chatInputBackgroundOpacityDark,
    );

    final groupMembers = _groupMembers(context);
    Widget result = bar;
    if (groupMembers != null) {
      // P5 群聊：输入框上方显示参与角色 chips，最左侧是「对导演说」模式开关。
      result = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xxs,
              AppSpacing.sm,
              0,
            ),
            child: _GroupMembersChips(
              members: groupMembers,
              talkToDirector: _talkToDirector(context),
              onToggleTalkToDirector: () => _toggleTalkToDirector(context),
            ),
          ),
          Flexible(child: result),
        ],
      );
    }
    if (!showEnvChip || !workspaceBound) return result;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showEnvChip && workspaceBound)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xxs,
              AppSpacing.sm,
              0,
            ),
            child: EnvironmentStatusChip(
              onTap: () => WorkspaceNavigation.openEnvironmentPage(context),
            ),
          ),
        Flexible(child: result),
      ],
    );
  }

  /// P5 和导演对话：当前群聊是否把消息直接交给隐形导演。
  bool _talkToDirector(BuildContext context) {
    final id = conversationId;
    if (id == null) return false;
    try {
      final conversation = context.select<ChatService, dynamic>(
        (chat) => chat.getConversation(id),
      );
      if (conversation == null) return false;
      return ConversationGroupChat.fromExtras(
        conversation.extras as Map<String, dynamic>,
      ).talkToDirector;
    } catch (_) {
      return false;
    }
  }

  void _toggleTalkToDirector(BuildContext context) {
    final id = conversationId;
    if (id == null) return;
    final turningOn = !_talkToDirector(context);
    final chat = context.read<ChatService>();
    unawaited(
      chat.updateConversationExtras(id, (extras) {
        final group = ConversationGroupChat.fromExtras(extras);
        if (!group.isGroup) return extras;
        return group
            .copyWith(talkToDirector: !group.talkToDirector)
            .applyTo(extras);
      }),
    );
    // 这个模式是常驻的：开启时必须说清「角色看不到」，否则用户会以为角色没了。
    if (turningOn && context.mounted) {
      showAppSnackBar(
        context,
        message: AppLocalizations.of(context)!.groupChatTalkToDirectorOnNotice,
        duration: const Duration(seconds: 4),
      );
    }
  }

  /// P5 群聊：当前会话的群成员列表；非群聊返回 null。
  List<Assistant>? _groupMembers(BuildContext context) {
    final id = conversationId;
    if (id == null) return null;
    try {
      final conversation = context.select<ChatService, dynamic>(
        (chat) => chat.getConversation(id),
      );
      if (conversation == null) return null;
      final group = ConversationGroupChat.fromExtras(
        conversation.extras as Map<String, dynamic>,
      );
      if (!group.isGroup) return null;
      final ap = context.read<AssistantProvider>();
      return <Assistant>[
        for (final memberId in group.members)
          if (ap.getById(memberId) case final Assistant member) member,
      ];
    } catch (_) {
      return null;
    }
  }

  bool _isPromptSelectionActive(
    BuildContext context,
    Assistant? assistant,
    PromptSelectionKind kind,
  ) {
    final scoped = assistant?.allowConversationPromptInjection == true;
    if (scoped && conversationId == null) return false;
    final ids = promptSelectionIds(
      context,
      kind: kind,
      assistantId: assistant?.id,
      conversationId: scoped ? conversationId : null,
    ).toSet();
    return kind == PromptSelectionKind.worldBook
        ? context.watch<WorldBookProvider>().books.any(
            (book) => book.enabled && ids.contains(book.id),
          )
        : context.watch<InstructionInjectionProvider>().items.any(
            (item) => ids.contains(item.id),
          );
  }

  bool _isSkillsActive(BuildContext context, Assistant? assistant) {
    final skillIds = context.select<ChatService?, List<String>?>((chat) {
      final extras = chat?.getConversation(conversationId ?? '')?.extras;
      return SkillsBinding.fromExtras(extras ?? const {}).skillIds;
    });
    return context.select<SkillsService?, bool>(
      (skills) =>
          skills
              ?.resolveForAssistant(assistant, conversationOverride: skillIds)
              .isNotEmpty ??
          false,
    );
  }

  bool _isWorkspaceBound(BuildContext context) {
    try {
      return context.select<ChatService, bool>((chat) {
        final id = conversationId;
        if (id == null) return false;
        final conversation = chat.getConversation(id);
        if (conversation == null) return false;
        return WorkspaceBinding.fromExtras(conversation.extras).isBound;
      });
    } catch (_) {
      return false;
    }
  }

  bool _isDesktopPlatform(BuildContext context) {
    final platform = Theme.of(context).platform;
    return platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux;
  }

  void _enforceModelCapabilities(
    BuildContext context,
    SettingsProvider settings,
    AssistantProvider ap,
    Assistant? a,
    String? pk,
    String? mid,
  ) {
    if (pk == null || mid == null) return;

    final supportsTools = isToolModel(pk, mid);
    if (!supportsTools && (a?.mcpServerIds.isNotEmpty ?? false)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final aa = ap.currentAssistant;
        if (aa != null && aa.mcpServerIds.isNotEmpty) {
          ap.updateAssistant(aa.copyWith(mcpServerIds: const <String>[]));
        }
      });
    }
  }

  ReasoningRequest _selectedReasoning(
    SettingsProvider settings,
    Assistant? assistant,
    String? providerKey,
    String? modelId,
  ) {
    if (providerKey == null || modelId == null) {
      return assistant?.reasoning ?? ReasoningRequest.auto;
    }
    return selectReasoningRequest(
      settings: settings,
      config: settings.getProviderConfig(providerKey),
      modelId: modelId,
      assistant: assistant,
    );
  }

  /// The button hosts local tools and the workspace as well as MCP, so it
  /// shows for every tool-capable model rather than only when MCP is set up.
  bool _shouldShowToolsButton(String? pk, String? mid) {
    if (pk == null || mid == null) return false;
    return isToolModel(pk, mid);
  }

  bool _isToolsActive(BuildContext context, Assistant? a, bool workspaceBound) {
    if (workspaceBound) return true;
    if ((a?.localToolIds ?? const <String>[]).isNotEmpty) return true;
    final connected = context.watch<McpProvider>().connectedServers;
    final selected = a?.mcpServerIds ?? const <String>[];
    if (selected.isEmpty || connected.isEmpty) return false;
    return connected.any((s) => selected.contains(s.id));
  }

  bool _hasQuickPhrases(BuildContext context, Assistant? a) {
    final quickPhraseProvider = context.watch<QuickPhraseProvider>();
    final globalCount = quickPhraseProvider.globalPhrases.length;
    final assistantCount = a != null
        ? quickPhraseProvider.getForAssistant(a.id).length
        : 0;
    return (globalCount + assistantCount) > 0;
  }
}

/// P5 群聊：输入框上方的参与角色 chips 条（按发言轮转顺序排列）。
class _GroupMembersChips extends StatelessWidget {
  const _GroupMembersChips({
    required this.members,
    required this.talkToDirector,
    required this.onToggleTalkToDirector,
  });

  final List<Assistant> members;

  /// P5 和导演对话：开启后消息全部路由给隐形导演。
  final bool talkToDirector;
  final VoidCallback onToggleTalkToDirector;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final active = talkToDirector;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onToggleTalkToDirector,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: active
                      ? cs.primary.withValues(alpha: 0.14)
                      : cs.onSurface.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(999),
                  border: active
                      ? Border.all(color: cs.primary.withValues(alpha: 0.5))
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Lucide.Clapperboard,
                      size: 13,
                      color: active
                          ? cs.primary
                          : cs.onSurface.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      l10n.groupChatTalkToDirectorLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: active
                            ? cs.primary
                            : cs.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          for (var i = 0; i < members.length; i++)
            Padding(
              padding: EdgeInsets.only(right: i == members.length - 1 ? 0 : 6),
              child: Container(
                padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    memberAvatar(context, members[i], size: 20),
                    const SizedBox(width: 6),
                    Text(
                      members[i].name.trim().isEmpty
                          ? '?'
                          : members[i].name.trim(),
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
