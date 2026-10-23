import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/update/app_update.dart';
import 'package:todo_app/update/providers.dart';
import 'package:todo_app/widgets/update_banner.dart';

class _Fixed extends UpdateNotifier {
  _Fixed(this._state);

  final UpdateState _state;
  int installs = 0;

  @override
  UpdateState build() => _state;

  @override
  void install() {
    installs++;
    state = UpdateState(info: _state.info, percent: 40);
  }
}

const _info = UpdateInfo(
  versionCode: 6,
  versionName: '1.1.1',
  url: 'https://example.com/app.apk',
  changelog: 'Исправили ошибки\nСинхронизация стала надёжнее',
);

late _Fixed _notifier;

Future<void> _pump(WidgetTester tester, UpdateState state) {
  _notifier = _Fixed(state);
  return tester.pumpWidget(
    ProviderScope(
      overrides: [updateProvider.overrideWith(() => _notifier)],
      child: const MaterialApp(
        home: Scaffold(bottomNavigationBar: UpdateBanner()),
      ),
    ),
  );
}

/// The update strip is a thin line with an arrow; the notes and the button live
/// on the page it opens.
void main() {
  testWidgets('no update, no strip', (tester) async {
    await _pump(tester, const UpdateState());

    expect(find.text('Доступно обновление'), findsNothing);
  });

  testWidgets('the strip only says there is an update', (tester) async {
    await _pump(tester, const UpdateState(info: _info));

    expect(find.text('Доступно обновление'), findsOneWidget);
    expect(
      find.text('Исправили ошибки\nСинхронизация стала надёжнее'),
      findsNothing,
    );
    expect(find.text('Обновить'), findsNothing);
  });

  testWidgets('a tap opens the page with the version and the notes', (
    tester,
  ) async {
    await _pump(tester, const UpdateState(info: _info));

    await tester.tap(find.text('Доступно обновление'));
    await tester.pumpAndSettle();

    expect(find.text('Доступное обновление v1.1.1'), findsOneWidget);
    expect(find.text('Что нового:'), findsOneWidget);
    expect(
      find.text('Исправили ошибки\nСинхронизация стала надёжнее'),
      findsOneWidget,
    );
    expect(find.text('Обновить'), findsOneWidget);
  });

  testWidgets('the button gives way to the progress once pressed', (
    tester,
  ) async {
    await _pump(tester, const UpdateState(info: _info));
    await tester.tap(find.text('Доступно обновление'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Обновить'));
    await tester.pump();

    expect(_notifier.installs, 1);
    expect(find.text('Обновить'), findsNothing);
    expect(find.text('Загрузка 40%'), findsOneWidget);
  });

  testWidgets('a failure shows its reason and offers another try', (
    tester,
  ) async {
    await _pump(
      tester,
      const UpdateState(info: _info, error: 'Не удалось скачать'),
    );
    await tester.tap(find.text('Не удалось обновить'));
    await tester.pumpAndSettle();

    expect(find.text('Не удалось скачать'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
  });
}
