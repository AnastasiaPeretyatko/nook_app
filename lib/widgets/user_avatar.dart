import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_app/auth/user_profile.dart';
import 'package:todo_app/utils/task_colors.dart';
import 'package:todo_app/utils/task_palette.dart';

/// The signed-in user's picture, with their initial underneath it.
///
/// The letter is not a placeholder that gets replaced — it is *always* drawn,
/// and the picture is laid over it. That is what makes this work in an
/// offline-first app: a user who signed up with an email and a password has no
/// picture at all, and one who signed in with Google has a picture that lives
/// on a CDN and is simply not there with the network off. Both cases end up as
/// the letter, with no spinner, no broken-image glyph and no flash between
/// states.
///
/// Nothing is cached to disk — Flutter's image cache is in memory and dies with
/// the process — so the picture reappears on the first launch that has a
/// connection. Caching it properly would mean another dependency, and a letter
/// is not a bad thing to look at.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.user,
    required this.surface,
    this.size = 44,
  });

  final User user;

  /// What the avatar sits on. The tint is mixed against it, which is what keeps
  /// the dark theme right without a second set of colours.
  final Color surface;

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final url = user.avatarUrl;

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: taskBadgeSurface(theme, accent, surface),
        shape: BoxShape.circle,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Text(
              user.avatarInitial,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: size * 0.42,
                fontWeight: FontWeight.w700,
                color: inkOn(surface, accent),
              ),
            ),
          ),
          if (url != null)
            Image.network(
              url,
              fit: BoxFit.cover,
              // A failure is the ordinary offline case, so it must be silent:
              // nothing is drawn and the letter below simply stays visible.
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
              // Same reasoning while it loads — no spinner over a 44px circle.
              frameBuilder: (_, child, frame, wasSynchronouslyLoaded) =>
                  wasSynchronouslyLoaded || frame != null
                  ? child
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}
