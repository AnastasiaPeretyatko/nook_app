import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/push/push_tap.dart';

void main() {
  test('a tap without a group is ignored', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(pushTapProvider.notifier).report(null);

    expect(container.read(pushTapProvider), isNull);
  });

  test('two taps on the same group are two distinct states', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final seen = <PushTap?>[];
    container.listen(pushTapProvider, (_, tap) => seen.add(tap));

    container.read(pushTapProvider.notifier)
      ..report('group-1')
      ..report('group-1');

    expect(seen.map((tap) => tap?.groupUid), ['group-1', 'group-1']);
    expect(seen[0], isNot(seen[1]));
  });
}
