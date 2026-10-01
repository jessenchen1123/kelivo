/// Splits assistant content into narration and dialogue segments for the
/// roleplay narration style (P3).
///
/// A *narration line* is a line whose trimmed form is exactly one asterisk
/// pair — `*她抬起头*` — with no other asterisks inside. Bold lines
/// (`**整行加粗**`), mixed lines (`*动作*对白`) and unclosed streaming lines
/// stay dialogue. Consecutive narration lines merge into one narration block;
/// everything else keeps its raw text and renders as usual (markdown already
/// italics inline `*...*` inside bubbles).
///
/// Pure and line-based: safe on partial streaming content, where an unclosed
/// narration simply renders as dialogue until its closing star arrives.
class NarrationSegment {
  const NarrationSegment({required this.text, required this.narration});

  final String text;
  final bool narration;
}

final RegExp _narrationLine = RegExp(r'^\*([^*]+)\*$');

bool isNarrationLine(String line) {
  final trimmed = line.trim();
  if (trimmed.length < 3) return false;
  return _narrationLine.hasMatch(trimmed);
}

List<NarrationSegment> splitAssistantNarration(String text) {
  if (!text.contains('*')) return <NarrationSegment>[NarrationSegment(text: text, narration: false)];

  final segments = <NarrationSegment>[];
  final narrationBuffer = <String>[];
  final dialogueBuffer = <String>[];

  void flushNarration() {
    if (narrationBuffer.isEmpty) return;
    segments.add(
      NarrationSegment(text: narrationBuffer.join('\n'), narration: true),
    );
    narrationBuffer.clear();
  }

  void flushDialogue() {
    final chunk = dialogueBuffer.join('\n');
    dialogueBuffer.clear();
    if (chunk.trim().isEmpty) return;
    segments.add(NarrationSegment(text: chunk, narration: false));
  }

  for (final line in text.split('\n')) {
    if (isNarrationLine(line)) {
      flushDialogue();
      final match = _narrationLine.firstMatch(line.trim())!;
      narrationBuffer.add(match.group(1)!);
    } else {
      flushNarration();
      dialogueBuffer.add(line);
    }
  }
  flushNarration();
  flushDialogue();

  if (segments.length == 1 && !segments.single.narration) {
    return <NarrationSegment>[NarrationSegment(text: text, narration: false)];
  }
  return segments;
}
