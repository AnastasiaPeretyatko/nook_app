/// Matching notes against what was typed into the diary's search box.
///
/// Pure text work — no widgets, no database. The diary already holds every note
/// in one list and its tabs are a filter over it; a search is the same kind of
/// filter, applied on top of whichever tab is open. So nothing here queries
/// anything: it is given a string and answers questions about it.
library;

/// The query cut into terms, lower-cased.
///
/// Several words mean **all of them, in any order**: "молоко хлеб" finds the
/// note that mentions bread first. Whole-phrase matching would miss it, and
/// any-of matching would drown the answer in notes that only say "хлеб".
List<String> searchTerms(String query) => [
  for (final term in query.toLowerCase().trim().split(RegExp(r'\s+')))
    if (term.isNotEmpty) term,
];

/// True when every one of [terms] appears somewhere in [text]. No terms is not
/// a search, and everything passes.
bool matchesTerms(String text, List<String> terms) {
  if (terms.isEmpty) return true;
  final haystack = text.toLowerCase();
  return terms.every(haystack.contains);
}

/// Where the terms sit inside [text] — every occurrence, in order, with
/// overlapping ones merged into one span so that a search for "за метка" cannot
/// paint the same letters twice.
List<(int, int)> matchRanges(String text, List<String> terms) {
  if (terms.isEmpty) return const [];

  final haystack = text.toLowerCase();
  final found = <(int, int)>[];
  for (final term in terms) {
    var at = haystack.indexOf(term);
    while (at != -1) {
      found.add((at, at + term.length));
      at = haystack.indexOf(term, at + term.length);
    }
  }
  found.sort((a, b) => a.$1.compareTo(b.$1));

  final merged = <(int, int)>[];
  for (final range in found) {
    final last = merged.isEmpty ? null : merged.last;
    if (last != null && range.$1 <= last.$2) {
      merged
        ..removeLast()
        ..add((last.$1, range.$2 > last.$2 ? range.$2 : last.$2));
    } else {
      merged.add(range);
    }
  }
  return merged;
}

/// [text] wound forward to the first term, so a card shows the line the note was
/// found by rather than its opening words — a match in the seventh paragraph
/// tells the reader nothing if the card is still showing the first.
///
/// Keeps [radius] characters of run-up, backed off to a word boundary, and marks
/// the cut with an ellipsis. Text that matches near its start is left alone.
String excerptAround(String text, List<String> terms, {int radius = 40}) {
  if (terms.isEmpty) return text;

  final haystack = text.toLowerCase();
  var first = -1;
  for (final term in terms) {
    final at = haystack.indexOf(term);
    if (at != -1 && (first == -1 || at < first)) first = at;
  }
  if (first <= radius) return text;

  var start = first - radius;
  final boundary = text.lastIndexOf(' ', start);
  if (boundary > 0) start = boundary + 1;
  return '…${text.substring(start)}';
}
