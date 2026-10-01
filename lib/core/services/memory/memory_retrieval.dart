import '../../models/memory_entry.dart';
import 'memory_tokenizer.dart';

/// Relevance-aware memory selection for context injection.
///
/// The old rule was "most recently updated wins". That serves a live storyline
/// (recent plot entries stay visible) but starves everything older: a fact
/// written in round 1 never resurfaces at round 50 no matter how much the
/// current turn is about it. Selection therefore splits the budget:
///
/// - Half goes to the most recent entries — the story so far.
/// - The rest goes to the most relevant entries among those left, scored by
///   token overlap between entry content and the current conversation tail.
///
/// With no query text the split degenerates to plain recency, which keeps the
/// detached/preview paths and brand-new conversations on the old behavior.
abstract final class MemoryRetrieval {
  /// Upper bound on distinct query tokens kept for scoring. Prevents a very
  /// long conversation tail from matching almost anything.
  static const int maxQueryTokens = 48;

  /// Pick at most [maxItems] entries from [entries].
  ///
  /// [queryText] is recent conversation text (or null). Entries are returned
  /// in no particular display order; the caller sorts for presentation.
  static List<MemoryEntry> selectEntries({
    required List<MemoryEntry> entries,
    required int maxItems,
    String? queryText,
  }) {
    if (maxItems >= entries.length) return List<MemoryEntry>.of(entries);

    final byRecency = List<MemoryEntry>.of(entries)..sort(_recencyCompare);
    final recencyQuota = (maxItems / 2).ceil().clamp(1, maxItems);
    final picked = byRecency.take(recencyQuota).toList();
    var remaining = byRecency.sublist(recencyQuota);
    final budget = maxItems - picked.length;
    if (budget <= 0 || remaining.isEmpty) return picked;

    final queryTokens = tokensForQuery(queryText);
    if (queryTokens.isEmpty) {
      picked.addAll(remaining.take(budget));
      return picked;
    }

    final scored = <(MemoryEntry, int)>[];
    for (final entry in remaining) {
      final score = relevanceScore(entry.content, queryTokens);
      if (score > 0) scored.add((entry, score));
    }
    if (scored.isEmpty) {
      picked.addAll(remaining.take(budget));
      return picked;
    }
    scored.sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      if (byScore != 0) return byScore;
      return _recencyCompare(a.$1, b.$1);
    });
    picked.addAll(scored.take(budget).map((e) => e.$1));
    if (picked.length < maxItems) {
      final chosenIds = picked.map((e) => e.id).toSet();
      picked.addAll(
        remaining.where((e) => !chosenIds.contains(e.id)).take(
              maxItems - picked.length,
            ),
      );
    }
    return picked;
  }

  /// Token-overlap score of [content] against [queryTokens]: how many of the
  /// content's tokens also occur in the query. 0 means no overlap.
  static int relevanceScore(String content, Set<String> queryTokens) {
    if (content.isEmpty || queryTokens.isEmpty) return 0;
    var hits = 0;
    for (final token in MemoryTokenizer.tokenize(content)) {
      if (queryTokens.contains(token)) hits++;
    }
    return hits;
  }

  /// Union of [MemoryTokenizer.tokenize] over each line of [queryText],
  /// deduplicated and capped at [maxQueryTokens].
  static Set<String> tokensForQuery(String? queryText) {
    final text = (queryText ?? '').trim();
    if (text.isEmpty) return const <String>{};
    final tokens = <String>{};
    for (final line in text.split('\n')) {
      for (final token in MemoryTokenizer.tokenize(line)) {
        tokens.add(token);
        if (tokens.length >= maxQueryTokens) return tokens;
      }
    }
    return tokens;
  }

  static int _recencyCompare(MemoryEntry a, MemoryEntry b) {
    final byUpdated = b.updatedAt.compareTo(a.updatedAt);
    if (byUpdated != 0) return byUpdated;
    return a.id.compareTo(b.id);
  }
}
