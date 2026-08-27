import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_app/auth/auth_repository.dart';

/// Who is signed in, live.
///
/// `Stream.value(null)` when there is no repository — Supabase did not come up,
/// or this is a widget test — so every reader gets an answer rather than an
/// error. Plain `StreamProvider`, the same shape the database providers use; a
/// `Notifier` would imply the app owns the session, and it does not.
final authUserProvider = StreamProvider<User?>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  if (repo == null) return Stream.value(null);
  return repo.userChanges();
});

/// The signed-in user, or null. What the screens read.
///
/// Falls back to the session restored at start-up while the stream has yet to
/// emit: `onAuthStateChange` does deliver the restored session, but not in the
/// first frame, and without the fallback the settings row would flash
/// "не вошли" on every launch.
final currentUserProvider = Provider<User?>(
  (ref) =>
      ref.watch(authUserProvider).valueOrNull ??
      ref.watch(authRepositoryProvider)?.currentUser,
);
