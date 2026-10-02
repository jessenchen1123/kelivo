/// Splits assistant content into narration and dialogue segments for the
/// roleplay narration style (P3).
///
/// Narration is recognised in three shapes:
/// - **wrapped line** — the whole trimmed line is one pair:
///   `*她抬起头*`, `（她抬起头）`, `(she looks up)`
/// - **trailing aside** — an action parenthetical closing out a finished
///   sentence: `"我没事。"（她笑了笑）`
/// - **leading aside** — an action parenthetical opening a quoted line:
///   `（她笑了笑）"我没事。"`
///
/// Bold lines (`**整行加粗**`), mixed `*动作*对白` lines and unclosed streaming
/// lines stay dialogue. The aside rules are deliberately narrow: the trailing
/// shape needs a sentence-ending mark right before the bracket, and the leading
/// shape needs a quote right after it, so ordinary prose like `答案是 (A)` or
/// `他走过来（手里拿着花）` keeps its place inside the bubble.
///
/// Consecutive narration chunks merge into one block; everything else keeps its
/// raw text and renders as usual (markdown already italics inline `*...*`
/// inside bubbles).
///
/// Pure and line-based: safe on partial streaming content, where an unclosed
/// narration simply renders as dialogue until its closing bracket arrives.
class NarrationSegment {
  const NarrationSegment({required this.text, required this.narration});

  final String text;
  final bool narration;
}

/// Wrapped-line narration, inner text captured. One entry per bracket style so
/// `*文字）` can never pair up.
final List<RegExp> _wrappedLinePatterns = <RegExp>[
  RegExp(r'^\*([^*]+)\*$'),
  RegExp(r'^（([^（）]+)）$'),
  RegExp(r'^\(([^()]+)\)$'),
];

/// `"我没事。"（她笑了笑）` — the bracket closes an already finished sentence.
final RegExp _trailingAside = RegExp(
  r'^(.*[。！？…"”』」.!?])\s*(?:（([^（）]+)）|\(([^()]+)\))$',
);

/// `（她笑了笑）"我没事。"` — the bracket opens the line and a quote follows.
final RegExp _leadingAside = RegExp(
  r'^(?:（([^（）]+)）|\(([^()]+)\))\s*(?=["“「『])',
);

/// Inner text when [line] is a whole-line narration, otherwise null.
String? narrationLineBody(String line) {
  final trimmed = line.trim();
  if (trimmed.length < 3) return null;
  for (final pattern in _wrappedLinePatterns) {
    final match = pattern.firstMatch(trimmed);
    if (match != null) return match.group(1);
  }
  return null;
}

bool isNarrationLine(String line) => narrationLineBody(line) != null;

typedef _Part = ({String text, bool narration});

/// Expands one source line into the chunks it renders as.
List<_Part> _partsOfLine(String line) {
  final body = narrationLineBody(line);
  if (body != null) return <_Part>[(text: body, narration: true)];

  final trailing = _trailingAside.firstMatch(line.trimRight());
  if (trailing != null) {
    final dialogue = trailing.group(1)!.trimRight();
    final inner = trailing.group(2) ?? trailing.group(3);
    if (dialogue.isNotEmpty && inner != null) {
      return <_Part>[
        (text: dialogue, narration: false),
        (text: inner, narration: true),
      ];
    }
  }

  final source = line.trimLeft();
  final leading = _leadingAside.firstMatch(source);
  if (leading != null) {
    final inner = leading.group(1) ?? leading.group(2);
    final rest = source.substring(leading.end).trimLeft();
    if (inner != null && rest.isNotEmpty) {
      return <_Part>[
        (text: inner, narration: true),
        (text: rest, narration: false),
      ];
    }
  }

  return <_Part>[(text: line, narration: false)];
}

List<NarrationSegment> splitAssistantNarration(String text) {
  if (!text.contains('*') && !text.contains('（') && !text.contains('(')) {
    return <NarrationSegment>[NarrationSegment(text: text, narration: false)];
  }

  final segments = <NarrationSegment>[];
  final buffer = <String>[];
  bool? bufferNarration;

  void flush() {
    final narration = bufferNarration;
    if (buffer.isEmpty || narration == null) return;
    final chunk = buffer.join('\n');
    buffer.clear();
    bufferNarration = null;
    if (chunk.trim().isEmpty) return;
    segments.add(NarrationSegment(text: chunk, narration: narration));
  }

  void add(String chunk, {required bool narration}) {
    if (bufferNarration != null && bufferNarration != narration) flush();
    bufferNarration = narration;
    buffer.add(chunk);
  }

  for (final line in text.split('\n')) {
    for (final part in _partsOfLine(line)) {
      add(part.text, narration: part.narration);
    }
  }
  flush();

  if (segments.length == 1 && !segments.single.narration) {
    return <NarrationSegment>[NarrationSegment(text: text, narration: false)];
  }
  return segments;
}
