import 'package:flutter/foundation.dart';

/// 子窗口自动登录请求（由批量多开主窗口通过 --auto 参数传入）
class AutoStartRequest {
  AutoStartRequest({
    required this.username,
    required this.password,
    required this.server,
    required this.tab,
    required this.courses,
    this.intervalMs = 200,
    this.maxSlots = 0,
  });

  final String username;
  final String password;
  final String server; // 服务器 URL（空 = 默认丽江师范）
  final String tab; // 标签（中文名或 xkkz_id，空 = 自动遍历）
  final List<String> courses; // 预设课程（顺序 = 志愿顺序）
  final int intervalMs;
  final int maxSlots;

  /// 命令行格式: --auto 学号|密码|服务器|标签|间隔ms|最多选|课程1,课程2,...
  static AutoStartRequest? parse(List<String> args) {
    final i = args.indexOf('--auto');
    if (i < 0 || i + 1 >= args.length) return null;
    final parts = args[i + 1].split('|');
    if (parts.length < 7) return null;
    final username = parts[0].trim();
    final password = parts[1];
    final server = parts[2].trim();
    final tab = parts[3].trim();
    final interval = int.tryParse(parts[4].trim()) ?? 200;
    final maxSlots = int.tryParse(parts[5].trim()) ?? 0;
    final courses = parts[6]
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (username.isEmpty || password.isEmpty || courses.isEmpty) return null;
    return AutoStartRequest(
      username: username,
      password: password,
      server: server,
      tab: tab,
      courses: courses,
      intervalMs: interval,
      maxSlots: maxSlots,
    );
  }

  /// 构造传给子进程的 payload
  static String payload(
    String username,
    String password,
    String server,
    String tab,
    List<String> courses, {
    int intervalMs = 200,
    int maxSlots = 0,
  }) {
    return '$username|$password|$server|$tab|$intervalMs|$maxSlots|${courses.join(',')}';
  }
}

/// 当前进程的自动启动请求（解析一次后置 null）
AutoStartRequest? autoStart;

/// 子进程登录完成后，通知 AutoGrabTab 自动开始监控
final ValueNotifier<bool> autoRunPending = ValueNotifier(false);