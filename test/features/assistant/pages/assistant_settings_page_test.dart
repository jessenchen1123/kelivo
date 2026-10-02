import 'dart:convert';

import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/assistant/pages/assistant_settings_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows the character library banner above the assistant list', (
    tester,
  ) async {
    final assistantPreferences = createBusinessTestPreferences();
    final settingsPreferences = createBusinessTestPreferences();
    await assistantPreferences.setString(
      'assistants_v1',
      jsonEncode([Assistant(id: 'a1', name: 'Tester').toJson()]),
    );
    await assistantPreferences.setString('current_assistant_id_v1', 'a1');
    final assistants = AssistantProvider(preferences: assistantPreferences);
    await assistants.loaded;
    final settings = SettingsProvider(settingsPreferences);
    await settings.loaded;

    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AssistantProvider>.value(value: assistants),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AssistantSettingsPage(),
        ),
      ),
    );
    await tester.pump();

    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
    // The banner is the prominent entry; the app-bar wand keeps its tooltip.
    expect(find.text(l10n.characterLibraryEntrySubtitle), findsOneWidget);
    expect(find.byTooltip(l10n.characterLibraryPageTitle), findsOneWidget);
    expect(find.text(l10n.assistantSettingsPageTitle), findsOneWidget);
  });
}
