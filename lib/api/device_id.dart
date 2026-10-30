import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _key = 'device_id';

/// What the server accepts as a phone's name (`X-Device-Id`, `?device=`).
final _valid = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// This phone's name for the server: a random id made on the first run and
/// never changed. The server uses it to not ring the phone that wrote a change
/// itself — it never identifies a person.
String deviceIdIn(SharedPreferences prefs) {
  final stored = prefs.getString(_key);
  if (stored != null && _valid.hasMatch(stored)) return stored;
  final id = const Uuid().v4();
  // The cached value is updated at once; the write to disk may finish later.
  prefs.setString(_key, id);
  return id;
}
