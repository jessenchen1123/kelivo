import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../l10n/app_localizations.dart';
import '../../chat/widgets/chat_message_widget.dart' show LoadingIndicator;

/// P5 导演模式：导演裁决是一个不产生流式消息的元调用，期间聊天界面完全静止，
/// 用户会误以为卡住。这个提示就顶在时间线末尾（打字指示器的位置），
/// 说明「导演正在思考」。
class GroupDirectorThinkingHint extends StatelessWidget {
  const GroupDirectorThinkingHint({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final color = cs.onSurfaceVariant;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LoadingIndicator(height: 12, dotSize: 6, spacing: 4, color: color),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.groupChatDirectorThinking,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: color),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 200.ms);
  }
}
