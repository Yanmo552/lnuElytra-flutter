import 'package:flutter/foundation.dart';

/// 预设课程全局存储（跨窗口布局切换不丢失）
///
/// 窗口拖过 800px 断点时 ResponsiveShell 会在桌面/移动两套布局树之间切换，
/// AutoGrabTab 的 State 会被销毁重建。把课程列表和设置放在这里，
/// 重建后 initState 重新载入即可恢复。
class PresetStore extends ChangeNotifier {
  /// 预设课程（添加顺序 = 志愿顺序）
  final List<String> courses = [];

  /// 最多选几门（0 = 全部预设）
  int maxSlots = 0;

  /// 抢课轮询间隔（毫秒）
  int intervalMs = 200;

  /// 是否并行抢课
  bool parallel = true;

  /// 目标标签页下标（-1 = 自动遍历所有标签）
  int tabIndex = -1;

  bool addCourse(String name) {
    if (name.isEmpty || courses.contains(name)) return false;
    courses.add(name);
    notifyListeners();
    return true;
  }

  void removeCourseAt(int index) {
    if (index < 0 || index >= courses.length) return;
    courses.removeAt(index);
    notifyListeners();
  }

  void moveCourse(int from, int to) {
    if (from < 0 || from >= courses.length) return;
    if (to < 0 || to >= courses.length) return;
    final c = courses.removeAt(from);
    courses.insert(to, c);
    notifyListeners();
  }

  void setMaxSlots(int v) {
    if (v < 0 || v == maxSlots) return;
    maxSlots = v;
    notifyListeners();
  }

  void setIntervalMs(int v) {
    if (v < 0 || v == intervalMs) return;
    intervalMs = v;
    notifyListeners();
  }

  void setParallel(bool v) {
    if (v == parallel) return;
    parallel = v;
    notifyListeners();
  }

  void setTabIndex(int v) {
    if (v == tabIndex) return;
    tabIndex = v;
    notifyListeners();
  }
}

/// 全局单例
final presetStore = PresetStore();