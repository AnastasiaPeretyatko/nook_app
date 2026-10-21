import 'package:supabase_flutter/supabase_flutter.dart';

/// The name and the picture a provider hands over with the session.
///
/// Nothing here is fetched: `userMetadata` rides along inside the session, so
/// reading it costs no request and works with the network off. It is a
/// free-form map, though — Google fills `full_name` and `avatar_url` and
/// repeats them as `name` and `picture`, while a user who signed up with an
/// email and a password has **none** of the four. Both getters are written for
/// that: any of the spellings will do, and null is an ordinary answer, not a
/// failure.
extension UserProfile on User {
  /// The name to greet the user by, or null when the provider gave none.
  String? get displayName =>
      _metaString('full_name') ??
      _metaString('name') ??
      _metaString('preferred_username');

  /// Where the user's picture lives, or null. An `https` URL on Google's CDN —
  /// public, but still a network fetch, so whatever draws it needs a fallback.
  String? get avatarUrl => _metaString('avatar_url') ?? _metaString('picture');

  /// The single letter drawn in place of a picture: from the name, else from
  /// the address, else a neutral dash rather than a stray glyph.
  String get avatarInitial {
    final source = displayName ?? email ?? '';
    final trimmed = source.trim();
    if (trimmed.isEmpty) return '—';
    // Through `runes` rather than `substring(0, 1)`: a code point outside the
    // basic plane is two code units, and slicing it would draw half of one.
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  /// A metadata value, but only when it is a string with something in it.
  /// The map is `Map<String, dynamic>` and the server is free to put anything
  /// in it, so a wrong type has to read as "absent" rather than throw.
  String? _metaString(String key) {
    final value = userMetadata?[key];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
