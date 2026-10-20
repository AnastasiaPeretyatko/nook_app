import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:todo_app/main.dart';
import 'package:todo_app/widgets/app_dialogs.dart';

/// The dialogs and sheets of the "Иней" design: what they answer, not how they
/// look — that was checked by eye against `DialogConfirm.dc.html` and friends.
void main() {
  Future<void> open(
    WidgetTester tester,
    Future<void> Function(BuildContext context) body,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(const Color(0xFF5B6DCB), Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => body(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('confirm', () {
    Future<bool?> ask(WidgetTester tester, Future<void> Function() tap) async {
      bool? answer;
      await open(tester, (context) async {
        answer = await showConfirmDialog(
          context,
          icon: DialogIcons.delete,
          title: 'Удалить задачу?',
          body: 'Отменить это не получится.',
          action: 'Удалить',
        );
      });
      expect(find.text('Удалить задачу?'), findsOneWidget);
      expect(find.text('Отменить это не получится.'), findsOneWidget);
      await tap();
      await tester.pumpAndSettle();
      return answer;
    }

    testWidgets('the main button says yes', (tester) async {
      final answer = await ask(tester, () => tester.tap(find.text('Удалить')));
      expect(answer, isTrue);
    });

    testWidgets('the other button says no', (tester) async {
      final answer = await ask(tester, () => tester.tap(find.text('Отмена')));
      expect(answer, isFalse);
    });

    testWidgets('closing it by tapping outside says no', (tester) async {
      final answer = await ask(tester, () => tester.tapAt(const Offset(5, 5)));
      expect(answer, isFalse);
    });
  });

  group('text prompt', () {
    Future<String?> prompt(
      WidgetTester tester,
      Future<void> Function() act, {
      String initial = '',
    }) async {
      String? answer = 'unset';
      await open(tester, (context) async {
        answer = await showTextPromptDialog(
          context,
          title: 'Новая группа',
          hint: 'Например, Семья',
          action: 'Создать',
          initial: initial,
        );
      });
      await act();
      await tester.pumpAndSettle();
      return answer;
    }

    testWidgets('gives back what was typed, trimmed', (tester) async {
      final answer = await prompt(tester, () async {
        await tester.enterText(find.byType(TextField), '  Семья ');
        await tester.tap(find.text('Создать'));
      });
      expect(answer, 'Семья');
    });

    testWidgets('an empty line is nothing', (tester) async {
      final answer = await prompt(tester, () async {
        await tester.enterText(find.byType(TextField), '   ');
        await tester.tap(find.text('Создать'));
      });
      expect(answer, isNull);
    });

    testWidgets('cancel is nothing even with text in the field', (
      tester,
    ) async {
      final answer = await prompt(tester, () async {
        await tester.enterText(find.byType(TextField), 'Семья');
        await tester.tap(find.text('Отмена'));
      });
      expect(answer, isNull);
    });

    testWidgets('starts from the given text', (tester) async {
      final answer = await prompt(
        tester,
        () => tester.tap(find.text('Создать')),
        initial: 'Дача',
      );
      expect(answer, 'Дача');
    });
  });

  testWidgets('the actions sheet answers with the row tapped', (tester) async {
    String? answer;
    await open(tester, (context) async {
      answer = await showActionsSheet<String>(
        context,
        title: 'Семья',
        actions: const [
          SheetAction(
            icon: LucideIcons.pencil,
            label: 'Переименовать',
            value: 'rename',
          ),
          SheetAction(
            icon: LucideIcons.trash_2,
            label: 'Удалить группу',
            value: 'delete',
            destructive: true,
          ),
        ],
      );
    });
    expect(find.text('Семья'), findsOneWidget);

    await tester.tap(find.text('Удалить группу'));
    await tester.pumpAndSettle();

    expect(answer, 'delete');
  });

  group('the options sheet', () {
    Future<(String?,)?> pick(WidgetTester tester, String label) async {
      (String?,)? answer;
      var called = false;
      await open(tester, (context) async {
        answer = await showOptionsSheet<String?>(
          context,
          title: 'Группа',
          options: const [(null, 'Личная задача'), ('g1', 'Семья')],
          selected: null,
        );
        called = true;
      });
      if (label.isNotEmpty) {
        await tester.tap(find.text(label));
      } else {
        await tester.tapAt(const Offset(5, 5));
      }
      await tester.pumpAndSettle();
      expect(called, isTrue);
      return answer;
    }

    testWidgets('picking an option answers with it', (tester) async {
      expect(await pick(tester, 'Семья'), ('g1',));
    });

    testWidgets('picking the null option is not the same as closing', (
      tester,
    ) async {
      expect(await pick(tester, 'Личная задача'), (null,));
    });

    testWidgets('closing the sheet answers nothing', (tester) async {
      expect(await pick(tester, ''), isNull);
    });
  });
}
