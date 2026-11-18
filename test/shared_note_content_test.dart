import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/utils/shared_note_content.dart';

void main() {
  group('SharedNoteContent', () {
    test('keeps ordinary text and URLs unchanged', () {
      const content = SharedNoteContent(
        'Напомни купить молоко: https://example.com/a?x=1&y=два',
      );

      expect(
        content.text,
        'Напомни купить молоко: https://example.com/a?x=1&y=два',
      );
    });
  });

  group('appendSharedNoteContent', () {
    test('keeps existing formatting and checklist operations unchanged', () {
      const body = '''[
        {"insert":"Bold"},
        {"insert":"\\n","attributes":{"block":"cl","checked":true}}
      ]''';

      final result = appendSharedNoteContent(
        body,
        const SharedNoteContent('https://example.com/next'),
      );

      expect(jsonDecode(result), [
        {'insert': 'Bold'},
        {
          'insert': '\n',
          'attributes': {'block': 'cl', 'checked': true},
        },
        {'insert': 'https://example.com/next\n'},
      ]);
    });

    test('creates a valid Delta for an empty or malformed body', () {
      for (final body in ['', 'not json', '{"insert":"not a list"}']) {
        final result = appendSharedNoteContent(
          body,
          const SharedNoteContent('Новая запись'),
        );

        expect(jsonDecode(result), [
          {'insert': 'Новая запись\n'},
        ]);
      }
    });

    test('adds each fragment exactly once across repeated appends', () {
      final first = appendSharedNoteContent(
        '',
        const SharedNoteContent('Первый фрагмент'),
      );
      final second = appendSharedNoteContent(
        first,
        const SharedNoteContent('Второй фрагмент'),
      );

      expect(jsonDecode(second), [
        {'insert': 'Первый фрагмент\n'},
        {'insert': 'Второй фрагмент\n'},
      ]);
    });
  });
}
