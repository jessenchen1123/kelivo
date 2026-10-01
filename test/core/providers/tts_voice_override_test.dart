import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/tts_provider.dart';
import 'package:Kelivo/core/services/tts/network_tts.dart';

void main() {
  group('TtsProvider.applyVoiceOverride (P4: 每角色音色)', () {
    test('patches OpenAI-style voice field', () {
      final service = OpenAiTtsOptions(
        id: 'svc-openai',
        enabled: true,
        name: 'OpenAI TTS',
        apiKey: 'sk-test',
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-4o-mini-tts',
        voice: 'alloy',
      );
      final patched = TtsProvider.applyVoiceOverride(service, 'nova');
      expect(patched, isA<OpenAiTtsOptions>());
      expect((patched as OpenAiTtsOptions).voice, 'nova');
      expect(patched.id, 'svc-openai');
    });

    test('patches Gemini-style voiceName field', () {
      final service = GeminiTtsOptions(
        id: 'svc-gemini',
        enabled: true,
        name: 'Gemini TTS',
        apiKey: 'k',
        baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
        model: 'gemini-2.5-flash-preview-tts',
        voiceName: 'Kore',
      );
      final patched = TtsProvider.applyVoiceOverride(service, 'Puck');
      expect(patched, isA<GeminiTtsOptions>());
      expect((patched as GeminiTtsOptions).voiceName, 'Puck');
    });
  });
}
