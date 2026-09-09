import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

import '../models/school.dart';
import '../services/auto_start.dart';
import '../services/log_store.dart';
import '../src/rust/third_party/lnu_elytra/flutter.dart';

/// 批量多开：为主窗口的每个账号 spawn 一个独立子进程窗口
class MultiSpawn {
  /// 服务器留空时回落默认学校（丽江师范）
  static String resolveServer(String server) {
    final s = server.trim();
    if (s.isNotEmpty) return s;
    return (schoolById('lijiang') ?? kPresetSchools.first).server;
  }

  /// 启动一个独立窗口（自动登录 + 自动开始监控）
  static Future<bool> spawnWindow({
    required String username,
    required String password,
    String server = '',
    String tab = '',
    required List<String> courses,
    int intervalMs = 200,
    int maxSlots = 0,
    bool parallel = true,
    bool autoRun = true,
  }) async {
    try {
      final exe = Platform.resolvedExecutable;
      final dir = File(exe).parent.path;
      final payload = AutoStartRequest.payload(
        username,
        password,
        resolveServer(server),
        tab,
        courses,
        intervalMs: intervalMs,
        maxSlots: maxSlots,
        parallel: parallel,
        autoRun: autoRun,
      );
      final proc = await Process.start(
        exe,
        ['--auto', payload],
        workingDirectory: dir,
        mode: ProcessStartMode.detached,
      );
      unawaited(proc.stdout.drain<void>().catchError((_) {}));
      unawaited(proc.stderr.drain<void>().catchError((_) {}));
      logStore.info('已启动窗口: $username（${courses.length} 门课）');
      return true;
    } catch (e) {
      logStore.error('启动窗口失败: $username, $e');
      return false;
    }
  }

  /// 预验证登录：返回 null 表示成功，否则返回失败原因
  static Future<String?> validateLoginError({
    required String server,
    required String username,
    required String password,
  }) async {
    try {
      final client = await FClient.newWithBase(backend: resolveServer(server));
      await client.login(username: username, password: password);
      await client.checkLogin();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// 把登录异常转成用户能看懂的一句话
  static String describeLoginError(String raw) {
    final r = raw.toLowerCase();
    if (r.contains('loginfailed')) return '账号或密码错误';
    if (r.contains('captcha') || r.contains('验证码')) return '密码错误触发验证码';
    if (r.contains('timeout') || r.contains('timed out')) return '网络超时';
    if (r.contains('connect') || r.contains('refused')) return '连不上服务器';
    return raw.length > 60 ? raw.substring(0, 60) : raw;
  }

  /// 从粘贴的表格文本解析账号行
  ///
  /// 支持带表头（学号/账号、密码、志愿一/志愿二/...、服务器、标签 任意顺序）：
  ///   志愿类列按列顺序合并为课程（顺序 = 志愿顺序），其他列忽略（如"微信名"）。
  /// 不带表头时按位置解析：第1列学号、第2列密码、其后非 URL/标签的列为课程。
  /// 每行格式: 学号<TAB>密码<TAB>课程1,课程2[<TAB>服务器<TAB>标签]
  static List<Map<String, String>> parseRows(String text) {
    // Markdown 表格（| a | b |）也支持：先转成 TSV
    final firstLine = text.split(RegExp(r'[\r\n]+')).firstWhere(
      (l) => l.trim().isNotEmpty,
      orElse: () => '',
    );
    if (firstLine.trim().startsWith('|')) {
      final sb = StringBuffer();
      for (final line in text.split(RegExp(r'[\r\n]+'))) {
        final t = line.trim();
        if (t.isEmpty) continue;
        if (!t.startsWith('|') || !t.endsWith('|')) continue;
        final inner = t.substring(1, t.length - 1);
        // 跳过分隔行（|---|----|）
        if (RegExp(r'^[\s|:\-]+$').hasMatch(inner)) continue;
        final cells = inner.split('|').map((c) => c.trim()).toList();
        sb.writeln(cells.join('\t'));
      }
      text = sb.toString();
    }
    var grid = _tsvParse(text);
    // 安全网：有些来源（非 Excel 剪贴板）多行单元格不带引号，
    // 会把一行拆成"续行"（首列为空）。把续行合并回上一行的最后一个单元格。
    final fixed = <List<String>>[];
    for (final cols in grid) {
      if (cols.isEmpty || cols.every((c) => c.trim().isEmpty)) {
        fixed.add(cols);
        continue;
      }
      if (cols[0].trim().isEmpty && fixed.isNotEmpty) {
        final prev = fixed.last;
        if (prev.isNotEmpty) {
          prev[prev.length - 1] = '${prev.last}\n${cols[0]}';
          if (cols.length > 1) prev.addAll(cols.sublist(1));
          continue;
        }
      }
      fixed.add(cols);
    }
    grid = fixed;
    for (var i = 0; i < grid.length; i++) {
      var cols = grid[i];
      if (cols.length < 3) {
        cols = grid[i].join(' ').split(RegExp(r'\s{2,}'));
      }
      grid[i] = cols.map(_cleanCell).toList();
    }
    return parseGrid(grid);
  }

  /// 直接解析 Excel 文件（.xlsx），完全绕开剪贴板格式问题
  static List<Map<String, String>> parseXlsxBytes(Uint8List bytes) {
    final decoder = SpreadsheetDecoder.decodeBytes(bytes);
    for (final table in decoder.tables.values) {
      final grid = <List<String>>[];
      for (final row in table.rows) {
        grid.add(row.map(_cellToString).toList());
      }
      final rows = parseGrid(grid);
      if (rows.isNotEmpty) return rows;
    }
    return [];
  }

  /// 把已清洗的二维表格解析成账号行
  ///
  /// 支持带表头（学号/账号、密码、志愿一/志愿二/...、服务器、标签 任意顺序）：
  ///   志愿类列按列顺序合并为课程（顺序 = 志愿顺序），其他列忽略（如"微信名"）。
  /// 不带表头时按位置解析：第1列学号、第2列密码、其后非 URL/标签的列为课程。
  static List<Map<String, String>> parseGrid(List<List<String>> grid) {
    if (grid.isEmpty) return [];

    // ---- 表头检测 ----
    int userCol = 0;
    int pwCol = 1;
    final courseCols = <int>[];
    int? serverCol;
    int? tabCol;
    final header = grid.first;
    final hasHeader = _looksLikeHeader(header);
    if (hasHeader) {
      for (var i = 0; i < header.length; i++) {
        final h = header[i].toLowerCase();
        if (h.contains('密码') || h.contains('pass')) {
          pwCol = i;
        } else if (h.contains('学号') || h.contains('账号') || h.contains('用户名') || h.contains('user')) {
          userCol = i;
        } else if (h.contains('志愿') || h.contains('课程') || h.contains('course')) {
          courseCols.add(i);
        } else if (h.contains('服务器') || h.contains('server')) {
          serverCol = i;
        } else if (h.contains('标签') || h.contains('板块') || h.contains('tab')) {
          tabCol = i;
        }
      }
      grid.removeAt(0);
    }

    final rows = <Map<String, String>>[];
    for (final cols in grid) {
      final username = userCol < cols.length ? cols[userCol] : '';
      final password = pwCol < cols.length ? cols[pwCol] : '';
      if (!_isAccount(username) || password.isEmpty) continue;

      final courses = <String>[];
      var server = '';
      var tab = '';

      if (hasHeader && courseCols.isNotEmpty) {
        for (final i in courseCols) {
          if (i >= cols.length) continue;
          final c = _cleanCourse(cols[i]);
          if (c.isNotEmpty && !courses.contains(c)) courses.add(c);
        }
        final sv = serverCol;
        final tv = tabCol;
        if (sv != null && sv < cols.length) server = cols[sv];
        if (tv != null && tv < cols.length) tab = cols[tv];
      } else {
        for (var i = 2; i < cols.length; i++) {
          final c = cols[i];
          if (c.isEmpty) continue;
          if (c.startsWith('http')) {
            server = c;
            continue;
          }
          if (_isKnownTab(c)) {
            tab = c;
            continue;
          }
          final cleaned = _cleanCourse(c);
          if (cleaned.isNotEmpty) {
            for (final part in cleaned.split(',')) {
              final p = part.trim();
              if (p.isNotEmpty && !courses.contains(p)) courses.add(p);
            }
          }
        }
      }

      if (courses.isEmpty) continue;
      rows.add({
        'username': username,
        'password': password,
        'courses': courses.join(','),
        'server': server,
        'tab': tab,
      });
    }
    return rows;
  }

  // ---------- helpers ----------

  /// 带引号感知的 TSV 解析：
  /// Excel 多行单元格粘贴为纯文本时会被双引号包裹（内部换行保留），
  /// 直接按行 split 会拆断这种行。这里逐字符解析，引号内的 Tab/换行视为内容。
  static List<List<String>> _tsvParse(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    var i = 0;

    void endField() {
      row.add(buf.toString());
      buf.clear();
    }

    void endRow() {
      endField();
      if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
      row = <String>[];
    }

    while (i < text.length) {
      final ch = text[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            buf.write('"');
            i += 2;
          } else {
            inQuotes = false;
            i++;
          }
        } else {
          buf.write(ch);
          i++;
        }
        continue;
      }
      if (ch == '"' && buf.isEmpty) {
        inQuotes = true;
        i++;
      } else if (ch == '\t') {
        endField();
        i++;
      } else if (ch == '\r') {
        if (i + 1 < text.length && text[i + 1] == '\n') i++;
        endRow();
        i++;
      } else if (ch == '\n') {
        endRow();
        i++;
      } else {
        buf.write(ch);
        i++;
      }
    }
    endRow();
    return rows;
  }

  static final _unicodeSpace = RegExp(
    '[\u00a0\u2002-\u200b\u202f\u205f\u3000]',
  );

  /// Excel 单元格值 → 字符串（整数去掉小数点，如 300020 不变成 300020.0）
  static String _cellToString(Object? v) {
    if (v == null) return '';
    if (v is double) {
      final d = v;
      if (d == d.roundToDouble()) return d.toInt().toString();
      return d.toString();
    }
    return v.toString().trim();
  }

  /// 单元格基础清洗：unicode 空格→普通空格，合并空白，去首尾
  static String _cleanCell(String s) {
    return s.replaceAll(_unicodeSpace, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 密码清洗：去掉所有空白（表格里常混入全角/半角空格）
  static String cleanPassword(String s) {
    return s.replaceAll(RegExp(r'\s'), '');
  }

  /// 课程清洗：取第一行、去前导 '-'、截断【】备注、去空白
  static String _cleanCourse(String s) {
    var c = _cleanCell(s);
    if (c.isEmpty) return '';
    if (c.contains('\n')) c = c.split('\n').first.trim();
    c = c.replaceAll(RegExp(r'\s'), '');
    c = c.startsWith('-') ? c.substring(1) : c;
    final bracket = c.indexOf('【');
    if (bracket >= 0) c = c.substring(0, bracket);
    return c.trim();
  }

  static bool _isAccount(String s) {
    // 学号：6-20 位数字/字母（排除"演示不要填"等说明行）
    return RegExp(r'^[0-9A-Za-z]{6,20}$').hasMatch(s);
  }

  static bool _looksLikeHeader(List<String> cols) {
    if (cols.isEmpty) return false;
    final first = cols[0].toLowerCase();
    return (first.contains('学号') || first.contains('账号') || first.contains('用户名')) ||
        first.contains('user') || first.contains('username');
  }

  static bool _isKnownTab(String s) {
    for (final school in kPresetSchools) {
      for (final t in school.tabs) {
        if (t.name == s || t.id == s) return true;
      }
    }
    return false;
  }
}
