import 'package:todo_app/database/app_database.dart';

/// How many taps a counter habit needs before its day counts as done.
///
/// A counter is meaningless below one, but `targetValue` can hold anything: it
/// is null when no target was set, and rows saved while `TrackingMode.value` was
/// a number with a target in halves may still carry a fraction — so a habit could
/// arrive here asking to be tapped 0.4 times. Rounded, and never below one.
int counterTarget(Task task) {
  final rounded = task.targetValue?.round() ?? 0;
  return rounded < 1 ? 1 : rounded;
}
