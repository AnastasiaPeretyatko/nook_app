import 'dart:convert';

/// Text received from a share target before it is added to a diary note.
///
/// The value is deliberately kept verbatim: URLs, whitespace, and non-ASCII
/// characters are content, not presentation for this boundary to reinterpret.
class SharedNoteContent {
  const SharedNoteContent(this.text);

  final String text;
}

/// Appends [content] to the JSON-encoded Parchment Delta in [body].
///
/// A usable Delta always ends in a paragraph break. Invalid or absent stored
/// bodies are treated as empty documents, so receiving shared content never
/// prevents a note from opening. Existing operations are decoded and encoded
/// without modifying them; only the required break and the new operation are
/// added.
String appendSharedNoteContent(String? body, SharedNoteContent content) {
  final operations = _decodeDelta(body);
  if (operations.isNotEmpty && !_endsWithParagraphBreak(operations)) {
    operations.add({'insert': '\n'});
  }
  operations.add({'insert': '${content.text}\n'});
  return jsonEncode(operations);
}

List<dynamic> _decodeDelta(String? body) {
  if (body == null || body.trim().isEmpty) return [];

  try {
    final decoded = jsonDecode(body);
    if (decoded is! List || !decoded.every(_isDeltaOperation)) return [];
    return List<dynamic>.from(decoded);
  } on FormatException {
    return [];
  }
}

bool _isDeltaOperation(dynamic operation) {
  if (operation is! Map || !operation.containsKey('insert')) return false;
  final insert = operation['insert'];
  final attributes = operation['attributes'];
  return (insert is String || insert is Map) &&
      (attributes == null || attributes is Map);
}

bool _endsWithParagraphBreak(List<dynamic> operations) {
  final insert = (operations.last as Map)['insert'];
  return insert is String && insert.endsWith('\n');
}
