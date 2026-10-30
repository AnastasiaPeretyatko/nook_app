/// The signed-in account, as the server describes it (`user` in BACKEND_PLAN.md
/// §4.1). The screens know a name, a picture and an address, and where they
/// came from is the repository's business.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    this.displayName,
    this.avatarUrl,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['id'] as String,
    email: json['email'] as String,
    displayName: _text(json['displayName']),
    avatarUrl: _text(json['avatarUrl']),
  );

  final String id;
  final String email;

  /// Null until the user (or Google, once at sign-up) has given one. A sign-up
  /// with an email and a password has none, and that is an ordinary answer.
  final String? displayName;

  /// An `https` URL, or null. Public, but still a network fetch, so whatever
  /// draws it needs a fallback.
  final String? avatarUrl;

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'displayName': displayName,
    'avatarUrl': avatarUrl,
  };

  /// The single letter drawn in place of a picture: from the name, else from
  /// the address, else a neutral dash rather than a stray glyph.
  String get avatarInitial {
    final trimmed = (displayName ?? email).trim();
    if (trimmed.isEmpty) return '—';
    // Through `runes` rather than `substring(0, 1)`: a code point outside the
    // basic plane is two code units, and slicing it would draw half of one.
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  /// A string with something in it, or null: the server sends `null`, but a
  /// cached copy or a wrong type must read as "absent" rather than throw.
  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  bool operator ==(Object other) =>
      other is AuthUser &&
      other.id == id &&
      other.email == email &&
      other.displayName == displayName &&
      other.avatarUrl == avatarUrl;

  @override
  int get hashCode => Object.hash(id, email, displayName, avatarUrl);
}
