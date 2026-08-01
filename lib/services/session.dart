import 'package:flutter/foundation.dart';

import '../models/school.dart';
import '../src/rust/third_party/lnu_elytra.dart';
import '../src/rust/third_party/lnu_elytra/flutter.dart';

/// 单个用户会话：持有已登录的 [FClient] 与登录状态。
///
/// 仅内存保存，重启后需重新登录。
class AppSession extends ChangeNotifier {
  /// 登录用户名（学号/账号）。
  String? username;

  /// 当前学校配置（登录时选定）。
  School? school;

  /// 目标标签页下标；-1 = 自动遍历所有标签（仅多标签学校有效）。
  int tabIndex = -1;

  /// 登录成功后的 Cookie，用于会话失效时自动重登。
  String? savedCookie;

  /// 客户端，登录时绑定；未登录为 null。
  FClient? _client;

  /// 是否已成功 init。
  bool inited = false;

  Future<void>? _initFuture;

  bool get isLoggedIn => username != null;
  FClient? get client => _client;

  /// 绑定一个已登录的客户端。
  void attachClient(String username, FClient client, {School? school}) {
    this.username = username;
    _client = client;
    this.school = school ?? this.school;
    inited = false;
    _initFuture = null;
    savedCookie = null;
    notifyListeners();
  }

  /// 清除客户端与所有登录状态。
  void logout() {
    _client = null;
    username = null;
    school = null;
    inited = false;
    _initFuture = null;
    savedCookie = null;
    notifyListeners();
  }

  /// 运行 init()（同一客户端最多执行一次；失败可重试）。
  Future<void> ensureInit() {
    if (inited) return Future.value();
    return _initFuture ??= () async {
      try {
        final c = _client;
        if (c == null) throw StateError('未登录');
        await c.init();
        inited = true;
        notifyListeners();
      } catch (_) {
        _initFuture = null;
        rethrow;
      }
    }();
  }

  /// 强制重新 init（选课开放前轮询用）。
  Future<void> reinit() {
    inited = false;
    _initFuture = null;
    return ensureInit();
  }

  /// 切换选课标签页（多标签学校）。
  Future<void> switchTab(String xkkzId) async {
    await ensureInit();
    final c = _client;
    if (c == null) throw StateError('未登录');
    await c.switchTab(xkkzId: xkkzId);
  }

  /// 搜索课程（先确保 init）。
  Future<Course> fetchCourses(String q) async {
    await ensureInit();
    final c = _client;
    if (c == null) throw StateError('未登录');
    return c.fetchCourses(q: q);
  }

  /// 提交选课请求。
  Future<SelectCourseResponse> selectCourse({
    required String courseId,
    required String courseDoId,
  }) async {
    await ensureInit();
    final c = _client;
    if (c == null) throw StateError('未登录');
    return c.selectCourse(courseId: courseId, courseDoId: courseDoId);
  }

  /// 子教学班选课 V1（通用端点）。
  Future<SelectCourseResponse> selectCourseSubclass({
    required String courseId,
    required String courseDoId,
    required String kcmc,
    required String xkkzId,
  }) async {
    await ensureInit();
    final c = _client;
    if (c == null) throw StateError('未登录');
    return c.selectCourseSubclass(
      courseId: courseId,
      courseDoId: courseDoId,
      kcmc: kcmc,
      xkkzId: xkkzId,
    );
  }

  /// 子教学班选课 V2（丽江师范专用端点）。
  Future<SelectCourseResponse> selectCourseSubclassV2({
    required String jxbId,
    required String doJxbId,
    required String jxbzls,
  }) async {
    await ensureInit();
    final c = _client;
    if (c == null) throw StateError('未登录');
    return c.selectCourseSubclassV2(
      jxbId: jxbId,
      doJxbId: doJxbId,
      jxbzls: jxbzls,
    );
  }

  /// 获取子教学班 ID 列表。
  Future<List<String>> fetchSubclassIds(String doJxbId) async {
    await ensureInit();
    final c = _client;
    if (c == null) throw StateError('未登录');
    return c.fetchSubclassIds(doJxbId: doJxbId);
  }

  /// 校验会话是否仍有效。
  Future<String> verifyLogin() async {
    final c = _client;
    if (c == null) throw StateError('未登录');
    return c.checkLogin();
  }

  /// 读取当前会话 Cookie。
  Future<String?> cookies() async {
    final c = _client;
    if (c == null) return null;
    return c.cookies();
  }

  /// 会话失效时自动重登：优先用保存的 Cookie，失败则退出登录。
  /// 返回是否恢复成功。
  Future<bool> relogin() async {
    final s = school;
    final ck = savedCookie;
    if (s == null || ck == null || ck.isEmpty) {
      logout();
      return false;
    }
    try {
      final c = await FClient.newWithBase(backend: s.server);
      await c.insertCookies(cookies: ck);
      await c.init();
      attachClient(username ?? 'Cookie', c, school: s);
      savedCookie = ck;
      return true;
    } catch (_) {
      logout();
      return false;
    }
  }
}

/// 全局会话单例。
final session = AppSession();
