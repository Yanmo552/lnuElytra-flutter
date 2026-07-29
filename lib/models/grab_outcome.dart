import '../src/rust/third_party/lnu_elytra.dart';

/// Classification of [SelectCourseResponse] for the auto-grab loop.
enum GrabOutcome {
  /// Course selected successfully (or already selected): stop trying this keyword.
  success,

  /// Hard limit reached: give up on this keyword.
  giveUp,

  /// Transient state (not open / rate limited / error): keep retrying.
  retry,
}

GrabOutcome classifyResponse(SelectCourseResponse r) {
  if (r.flag == '1') return GrabOutcome.success;
  final msg = r.msg ?? '';
  // "Only one class can be selected per course, cannot select again!" -> already has a class, treat as success.
  if (msg.contains('只能选一个教学班')) return GrabOutcome.success;
  // "Exceeds the maximum course limit for PE electives this semester" -> hard limit.
  if (msg.contains('超过')) return GrabOutcome.giveUp;
  // "Sorry, course selection is not open!" / "Selection frequency too high, retry later!" / other -> retry.
  return GrabOutcome.retry;
}
