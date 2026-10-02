import 'dart:io' show File;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/assistant.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/haptics.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/emoji_text.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../theme/app_font_weights.dart';
import 'package:Kelivo/theme/app_semantic_colors.dart';
import '../../../utils/avatar_cache.dart';
import '../../../utils/sandbox_path_resolver.dart';

/// P5 群聊：多选角色建立群聊会话。
///
/// 返回按选择顺序排列的成员 assistant id 列表（首位是主持人），取消返回 null。
Future<List<String>?> showGroupChatMemberPicker(BuildContext context) async {
  final isDesktop =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;
  if (!isDesktop) {
    final maxHeight = MediaQuery.of(context).size.height * 0.8;
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.overlaySurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx)!;
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: _GroupMemberPickerBody(
              title: l10n.groupChatPickerTitle,
              confirmLabel: l10n.groupChatPickerStart,
            ),
          ),
        );
      },
    );
  }
  // Desktop: plain dialog hosting the same body.
  return showDialog<List<String>>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
          child: _GroupMemberPickerBody(
            title: AppLocalizations.of(ctx)!.groupChatPickerTitle,
            confirmLabel: AppLocalizations.of(ctx)!.groupChatPickerStart,
          ),
        ),
      );
    },
  );
}

class _GroupMemberPickerBody extends StatefulWidget {
  const _GroupMemberPickerBody({
    required this.title,
    required this.confirmLabel,
  });

  final String title;
  final String confirmLabel;

  @override
  State<_GroupMemberPickerBody> createState() => _GroupMemberPickerBodyState();
}

class _GroupMemberPickerBodyState extends State<_GroupMemberPickerBody> {
  final List<String> _selected = <String>[];

  void _toggle(Assistant a) {
    Haptics.light();
    setState(() {
      if (_selected.contains(a.id)) {
        _selected.remove(a.id);
      } else {
        _selected.add(a.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final assistants = context.watch<AssistantProvider>().assistants;
    final canStart = _selected.length >= 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.title,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, fontWeight: AppFontWeights.emphasis),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.groupChatPickerMinHint,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [for (final a in assistants) _memberRow(context, a)],
              ),
            ),
          ),
          const SizedBox(height: 12),
          IosCardPress(
            borderRadius: BorderRadius.circular(14),
            baseColor: canStart
                ? cs.primary.withValues(alpha: 0.15)
                : cs.onSurface.withValues(alpha: 0.05),
            duration: const Duration(milliseconds: 260),
            onTap: canStart
                ? () => Navigator.of(context).pop(List<String>.of(_selected))
                : null,
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Text(
                canStart ? widget.confirmLabel : l10n.groupChatPickerMinHint,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: AppFontWeights.medium,
                  color: canStart
                      ? cs.primary
                      : cs.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _memberRow(BuildContext context, Assistant a) {
    final cs = Theme.of(context).colorScheme;
    final selected = _selected.contains(a.id);
    final order = _selected.indexOf(a.id) + 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        height: 48,
        child: IosCardPress(
          borderRadius: BorderRadius.circular(14),
          baseColor: selected
              ? cs.primary.withValues(alpha: 0.1)
              : Theme.of(context).cardColor.withValues(alpha: 0.4),
          duration: const Duration(milliseconds: 260),
          onTap: () => _toggle(a),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              memberAvatar(context, a, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  a.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: AppFontWeights.medium,
                  ),
                ),
              ),
              if (selected)
                Text(
                  '#$order',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: AppFontWeights.medium,
                    color: cs.primary,
                  ),
                ),
              const SizedBox(width: 8),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 20,
                color: selected
                    ? cs.primary
                    : cs.onSurface.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget memberAvatar(BuildContext context, Assistant a, {double size = 26}) {
  final cs = Theme.of(context).colorScheme;
  final av = (a.avatar ?? '').trim();
  if (av.isNotEmpty) {
    if (av.startsWith('http')) {
      return FutureBuilder<String?>(
        future: AvatarCache.getPath(av),
        builder: (ctx, snap) {
          final p = snap.data;
          if (p != null && File(p).existsSync()) {
            return ClipOval(
              child: Image(
                image: FileImage(File(p)),
                width: size,
                height: size,
                fit: BoxFit.cover,
              ),
            );
          }
          return ClipOval(
            child: Image.network(
              av,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => memberInitial(cs, a.name, size),
            ),
          );
        },
      );
    } else if (!kIsWeb && (av.startsWith('/') || av.contains(':'))) {
      final fixed = SandboxPathResolver.fix(av);
      final f = File(fixed);
      if (f.existsSync()) {
        return ClipOval(
          child: Image(
            image: FileImage(f),
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        );
      }
    } else {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: EmojiText(
          av.characters.take(1).toString(),
          fontSize: size * 0.5,
          optimizeEmojiAlign: true,
        ),
      );
    }
  }
  return memberInitial(cs, a.name, size);
}

Widget memberInitial(ColorScheme cs, String name, double size) {
  final letter = name.trim().isNotEmpty ? name.trim()[0] : '?';
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: cs.primary.withValues(alpha: 0.15),
      shape: BoxShape.circle,
    ),
    alignment: Alignment.center,
    child: Text(
      letter,
      style: TextStyle(
        color: cs.primary,
        fontSize: size * 0.42,
        fontWeight: AppFontWeights.emphasis,
      ),
    ),
  );
}
