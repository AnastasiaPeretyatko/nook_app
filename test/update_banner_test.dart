import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/update/app_update.dart';
import 'package:todo_app/update/providers.dart';
import 'package:todo_app/widgets/update_banner.dart';

class _Fixed extends UpdateNotifier {
  _Fixed(this._state);

  final UpdateState _state;

  @override
  UpdateState build() => _state;
}

UpdateInfo _info(String changelog) => UpdateInfo(
  versionCode: 6,
  versionName: '2.0.3',
  url: 'https://example.com/app.apk',
  changelog: changelog,
);

Future<void> _pump(WidgetTester tester, String changelog) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      updateProvider.overrideWith(
        () => _Fixed(UpdateState(info: _info(changelog))),
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(bottomNavigationBar: UpdateBanner()),
    ),
  ),
);

/// The release notes in the update strip: three lines, and the rest on demand.
void main() {
  final long = [for (var i = 1; i <= 12; i++) 'Пункт $i обновления'].join('\n');

  testWidgets('a short note shows whole, with nothing to expand', (
    tester,
  ) async {
    await _pump(tester, 'Исправили ошибки');

    expect(find.text('Доступно обновление 2.0.3'), findsOneWidget);
    expect(find.text('Исправили ошибки'), findsOneWidget);
    expect(find.text('Подробнее'), findsNothing);
  });

  testWidgets('a long note is cut, "Подробнее" opens all of it, "Свернуть" '
      'closes it', (tester) async {
    await _pump(tester, long);

    expect(find.text('Подробнее'), findsOneWidget);
    expect(tester.widget<Text>(find.text(long)).maxLines, 3);

    await tester.tap(find.text('Подробнее'));
    await tester.pump();
    expect(tester.widget<Text>(find.text(long)).maxLines, isNull);
    expect(find.text('Свернуть'), findsOneWidget);

    await tester.tap(find.text('Свернуть'));
    await tester.pump();
    expect(tester.widget<Text>(find.text(long)).maxLines, 3);
  });
}
