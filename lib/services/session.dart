import 'package:flutter/foundation.dart';

import '../src/rust/third_party/lnu_elytra.dart';
import '../src/rust/third_party/lnu_elytra/flutter.dart';

/// Single user session: holds the logged-in [FClient] and login state.
///
/// Not persisted — the client and login state exist only in memory;
/// the user must log in again after a restart.
class AppSession extends ChangeNotifier {
  /// Username used for login (student ID / account name).
  String? username;

  /// Client, bound on login. `null` before login and after logout.
  FClient? _client;

  /// Whether `init()` has completed successfully for the current client.
  bool inited = false;

  /// In-flight `init()`, so concurrent callers share the same invocation.
  Future<void>? _initFuture;

  bool get isLoggedIn => username != null;
  FClient? get client => _client;

  /// Binds a newly built, logged-in client for [username].
  void attachClient(String username, FClient client) {
    this.username = username;
    _client = client;
    inited = false;
    _initFuture = null;
    notifyListeners();
  }

  /// Discards the client and all login state.
  void logout() {
    _client = null;
    username = null;
    inited = false;
    _initFuture = null;
    notifyListeners();
  }

  /// Runs `init()` at most once for the current client.
  ///
  /// Only course-selection paths need it, so it runs lazily before those calls
  /// (see [fetchCourses] / [selectCourse]). On failure the cached Future is
  /// cleared so subsequent calls can retry.
  Future<void> ensureInit() {
    if (inited) return Future.value();
    return _initFuture ??= () async {
      try {
        final c = _client;
        if (c == null) throw StateError('not logged in');
        await c.init();
        inited = true;
        notifyListeners();
      } catch (_) {
        _initFuture = null;
        rethrow;
      }
    }();
  }

  /// Forces a re-run of `init()`.
  ///
  /// Clears the cached init state and calls [ensureInit] again,
  /// for manual triggering when the course-selection context expires or needs resetting.
  Future<void> reinit() {
    inited = false;
    _initFuture = null;
    return ensureInit();
  }

  /// Searches courses, running [ensureInit] first.
  Future<Course> fetchCourses(String q) async {
    await ensureInit();
    final c = _client;
    if (c == null) throw StateError('not logged in');
    return c.fetchCourses(q: q);
  }

  /// Submits a course-selection request, running [ensureInit] first.
  Future<SelectCourseResponse> selectCourse({
    required String courseId,
    required String courseDoId,
  }) async {
    await ensureInit();
    final c = _client;
    if (c == null) throw StateError('not logged in');
    return c.selectCourse(courseId: courseId, courseDoId: courseDoId);
  }

  /// Verifies whether the current session is still valid by calling `checkLogin`.
  Future<String> verifyLogin() async {
    final c = _client;
    if (c == null) throw StateError('not logged in');
    return c.checkLogin();
  }
}

/// Global session singleton.
final session = AppSession();
