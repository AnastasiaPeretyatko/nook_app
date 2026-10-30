import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/api/device_id.dart';

void main() {
  test('made once, then the same every time', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final first = deviceIdIn(prefs);
    expect(first, matches(RegExp(r'^[A-Za-z0-9_-]{1,64}$')));
    expect(deviceIdIn(prefs), first);
    expect(prefs.getString('device_id'), first);
  });

  test('an id kept from before is not replaced', () async {
    SharedPreferences.setMockInitialValues({'device_id': 'kept-1'});
    final prefs = await SharedPreferences.getInstance();
    expect(deviceIdIn(prefs), 'kept-1');
  });

  test('a stored value the server would refuse is replaced', () async {
    SharedPreferences.setMockInitialValues({'device_id': 'has space!'});
    final prefs = await SharedPreferences.getInstance();
    expect(deviceIdIn(prefs), isNot('has space!'));
  });
}
