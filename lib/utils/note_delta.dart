/// Reading and rewriting a note's body without going through the editor.
///
/// The body is a Parchment (Quill.js) Delta, stored JSON-encoded: a list of
/// operations. This works on that decoded list, so nothing here depends on
/// Fleather — a list screen can read a note's text without building an editor.
library;

/// The note's text with the formatting dropped — what a list row shows as a
/// preview. Embedded pictures contribute nothing, not even a placeholder
/// character.
String deltaPlainText(List<dynamic> operations) {
  final text = StringBuffer();
  for (final operation in operations) {
    if (operation is! Map) continue;
    final inserted = operation['insert'];
    if (inserted is String) text.write(inserted);
  }
  return text.toString();
}
