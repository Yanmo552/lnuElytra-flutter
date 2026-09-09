import 'dart:io';

import '../services/auto_start.dart';
import '../services/log_store.dart';

/// 批量多开：为主窗口的每个账号 spawn 一个独立子进程窗口
class MultiSpawn {
  /// 启动一个独立窗口（自动登录 + 自动开始监控）
  static Future<bool> spawnWindow({
    required String username,
    required String password,
    String server = '',
    String tab = '',
    required List<String> courses,
    int intervalMs = 200,
    int maxSlots = 0,
  }) async {
    try {
      final exe = Platform.resolvedExecutable;
      final dir = File(exe).parent.path;
      final payload = AutoStartRequest.payload(
        username,
        password,
        server,
        tab,
        courses,
        intervalMs: intervalMs,
        maxSlots: maxSlots,
      );
      final proc = await Process.start(
        exe,
        ['--auto', payload],
        workingDirectory: dir,
        mode: ProcessStartMode.detached,
      );
      proc.stdout.drain<void>().catchError((_) {});
      proc.stderr.drain<void>().catchError((_) {});
      logStore.info('已启动窗口: $username（${courses.length} 门课）');
      return true;
    } catch (e) {
      logStore.error('启动窗口失败: $username, $e');
      return false;
    }
  }

  /// 从粘贴的表格文本解析账号行（每行: 学号<TAB>密码<TAB>课程1,课程2[<TAB>服务器<TAB>标签]）
  static List<Map<String, String>> parseRows(String text) {
    final rows = <Map<String, String>>[];
    for (final rawLine in text.split(RegExp(r'[\r\n]+'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      var cols = line.split('\t');
      if (cols.length < 3) {
        // 无 Tab 分隔时尝试用 2+ 空格分隔
        cols = line.split(RegExp(r'\s{2,}'));
      }
      if (cols.length < 3) continue;
      final username = cols[0].trim();
      final password = cols[1].trim();
      final courses = cols[2]
          .split(RegExp(r'[,，;；]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (username.isEmpty || password.isEmpty || courses.isEmpty) continue;
      rows.add({
        'username': username,
        'password': password,
        'courses': courses.join(','),
        'server': cols.length > 3 ? cols[3].trim() : '',
        'tab': cols.length > 4 ? cols[4].trim() : '',
      });
    }
    return rows;
  }
}