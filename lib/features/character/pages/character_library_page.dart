import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/assistant.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/world_book_provider.dart';
import '../../../core/services/character_card_service.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';
import 'package:Kelivo/theme/app_semantic_colors.dart';
import '../../../utils/sandbox_path_resolver.dart';
import '../../assistant/pages/assistant_settings_edit_page.dart';

/// Character library: SillyTavern card imports rendered as a card flow.
///
/// Characters are assistants with [Assistant.characterCardData] set; "use"
/// simply switches the current assistant so the next chat carries the
/// character's persona, greeting and bound world book.
class CharacterLibraryPage extends StatefulWidget {
  const CharacterLibraryPage({super.key});

  @override
  State<CharacterLibraryPage> createState() => _CharacterLibraryPageState();
}

class _CharacterLibraryPageState extends State<CharacterLibraryPage> {
  String _query = '';
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<AssistantProvider>();
    final characters = provider.assistants
        .where((a) => a.isCharacter)
        .where(_matchesQuery)
        .toList(growable: false);
    final currentId = provider.currentAssistantId;

    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: IconButton(
            icon: const Icon(Lucide.ArrowLeft, size: 22),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.characterLibraryPageTitle),
        actions: [
          Tooltip(
            message: l10n.characterLibraryImport,
            child: IconButton(
              icon: _importing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Lucide.Upload, size: 22),
              onPressed: _importing ? null : _importCard,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: InputDecoration(
                prefixIcon: const Icon(Lucide.Search, size: 20),
                hintText: l10n.characterLibrarySearchHint,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: cs.onSurface.withValues(alpha: 0.05),
              ),
            ),
          ),
          Expanded(
            child: characters.isEmpty
                ? _EmptyState(onImport: _importCard)
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.72,
                    ),
                    itemCount: characters.length,
                    itemBuilder: (context, index) => _CharacterTile(
                      assistant: characters[index],
                      inUse: characters[index].id == currentId,
                      onUse: () => _useCharacter(characters[index]),
                      onEdit: () => _editCharacter(characters[index]),
                      onExport: () => _exportCharacter(characters[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  bool _matchesQuery(Assistant a) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    final data = a.characterCardData ?? const <String, dynamic>{};
    final tags = (data['tags'] as List?) ?? const <dynamic>[];
    return a.name.toLowerCase().contains(q) ||
        a.systemPrompt.toLowerCase().contains(q) ||
        tags.any((t) => t.toString().toLowerCase().contains(q));
  }

  Future<void> _importCard() async {
    final l10n = AppLocalizations.of(context)!;
    final assistantProvider = context.read<AssistantProvider>();
    final worldBookProvider = context.read<WorldBookProvider>();
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['png'],
      );
      final file = res?.files.single;
      if (file == null) return;
      final bytes = file.bytes;
      if (bytes == null) {
        if (!mounted) return;
        showAppSnackBar(
          context,
          message: l10n.characterLibraryImportFailed(l10n.characterLibraryReadFileFailed),
          type: NotificationType.error,
        );
        return;
      }
      setState(() => _importing = true);
      final service = CharacterCardService(
        assistants: assistantProvider,
        worldBooks: worldBookProvider,
      );
      final id = await service.importFromPngBytes(bytes);
      final imported = assistantProvider.getById(id);
      if (!mounted) return;
      final entries = service.lastImport?.worldBookEntryCount ?? 0;
      showAppSnackBar(
        context,
        message: l10n.characterLibraryImportSuccess(
          imported?.name ?? '',
          entries,
        ),
        type: NotificationType.success,
      );
    } on CharacterCardFormatException catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.characterLibraryImportFailed(e.message),
        type: NotificationType.error,
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.characterLibraryImportFailed(e.toString()),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _useCharacter(Assistant assistant) async {
    Haptics.light();
    await context.read<AssistantProvider>().setCurrentAssistant(assistant.id);
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  void _editCharacter(Assistant assistant) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            AssistantSettingsEditPage(assistantId: assistant.id),
      ),
    );
  }

  Future<void> _exportCharacter(Assistant assistant) async {
    final l10n = AppLocalizations.of(context)!;
    final service = CharacterCardService(
      assistants: context.read<AssistantProvider>(),
      worldBooks: context.read<WorldBookProvider>(),
    );
    try {
      final png = await service.exportToPngBytes(assistant);
      if (png == null) {
        if (!mounted) return;
        showAppSnackBar(
          context,
          message: l10n.characterLibraryNoPng,
          type: NotificationType.error,
        );
        return;
      }
      final safeName = assistant.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final saved = await FilePicker.platform.saveFile(
        fileName: '$safeName.png',
        bytes: Uint8List.fromList(png),
      );
      if (!mounted) return;
      if (saved == null) return;
      // Desktop pickers return a path without writing; mobile SAF already
      // wrote the bytes when [bytes] was supplied.
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(saved).writeAsBytes(png, flush: true);
        if (!mounted) return;
      }
      showAppSnackBar(
        context,
        message: l10n.characterLibraryExportSuccess,
        type: NotificationType.success,
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.characterLibraryExportFailed(e.toString()),
        type: NotificationType.error,
      );
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Lucide.WandSparkles,
              size: 44,
              color: cs.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.characterLibraryEmpty,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Lucide.Upload, size: 18),
              label: Text(l10n.characterLibraryImport),
            ),
          ],
        ),
      ),
    );
  }
}

class _CharacterTile extends StatelessWidget {
  const _CharacterTile({
    required this.assistant,
    required this.inUse,
    required this.onUse,
    required this.onEdit,
    required this.onExport,
  });

  final Assistant assistant;
  final bool inUse;
  final VoidCallback onUse;
  final VoidCallback onEdit;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final appColors = context.appColors;
    final l10n = AppLocalizations.of(context)!;
    final data = assistant.characterCardData ?? const <String, dynamic>{};
    final tags = [
      for (final t in (data['tags'] as List?) ?? const <dynamic>[])
        t.toString(),
    ];
    final snippet = ((data['description'] as String?) ?? assistant.systemPrompt)
        .trim();

    Widget avatar;
    final path = (assistant.avatar ?? '').trim();
    if (path.isNotEmpty && !path.startsWith('http') && File(path).existsSync()) {
      avatar = ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        child: Image(
          image: FileImage(File(SandboxPathResolver.fix(path))),
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
        ),
      );
    } else {
      avatar = Container(
        color: cs.primary.withValues(alpha: 0.12),
        alignment: Alignment.center,
        child: Text(
          assistant.name.isNotEmpty ? assistant.name.characters.first : '?',
          style: TextStyle(
            fontSize: 34,
            fontWeight: AppFontWeights.emphasis,
            color: cs.primary,
          ),
        ),
      );
    }

    return IosCardPress(
      onTap: onUse,
      onLongPress: () => _showActions(context, l10n),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: appColors.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: inUse
                ? cs.primary.withValues(alpha: 0.6)
                : cs.onSurface.withValues(alpha: 0.08),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: avatar),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          assistant.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: AppFontWeights.emphasis,
                          ),
                        ),
                      ),
                      if (inUse)
                        Icon(Lucide.Check, size: 15, color: cs.primary),
                    ],
                  ),
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      tags.take(2).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.primary.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                  if (snippet.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      snippet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.25,
                        color: cs.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showActions(BuildContext context, AppLocalizations l10n) {
    Haptics.light();
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Lucide.Play, size: 20),
              title: Text(l10n.characterLibraryUse),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onUse();
              },
            ),
            ListTile(
              leading: const Icon(Lucide.SquarePen, size: 20),
              title: Text(l10n.characterLibraryEdit),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onEdit();
              },
            ),
            ListTile(
              leading: const Icon(Lucide.Download, size: 20),
              title: Text(l10n.characterLibraryExport),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onExport();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
