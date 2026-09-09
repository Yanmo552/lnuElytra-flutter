import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/school.dart';
import '../../services/log_store.dart';
import '../../services/multi_spawn.dart';
import '../../services/session.dart';
import '../../services/toaster.dart';
import '../../src/rust/third_party/lnu_elytra/flutter.dart';

/// 登录页：选择学校 + 账密/Cookie 登录
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

enum _LoginMode { password, cookie }

class _LoginPageState extends State<LoginPage> {
  _LoginMode _mode = _LoginMode.password;

  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _cookieCtrl = TextEditingController();

  bool _busy = false;
  String? _error;

  School _selectedSchool = kPresetSchools.first;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _cookieCtrl.dispose();
    super.dispose();
  }

  /// 批量多开：粘贴账号表格（每行: 学号<TAB>密码<TAB>课程1,课程2[<TAB>服务器<TAB>标签]），
  /// 每个账号启动一个独立窗口自动登录抢课
  Future<void> _openMultiSpawn() async {
    final ctrl = TextEditingController();
    final serverCtrl = TextEditingController(text: _selectedSchool.server);
    final intervalCtrl = TextEditingController(text: '200');
    final maxCtrl = TextEditingController(text: '0');
    var parallel = true;
    var autoRun = true;
    var validateFirst = true;
    var importStatus = '选择 Excel 文件导入，或直接粘贴表格文本（每行: 学号<TAB>密码<TAB>课程1,课程2）';
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('批量多开'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.upload_file, size: 18),
                        label: const Text('选择 Excel 文件'),
                        onPressed: () async {
                          try {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: const ['xlsx'],
                              dialogTitle: '选择抢课表格（.xlsx）',
                            );
                            final path = result?.files.single.path;
                            if (path == null) return;
                            final bytes = await File(path).readAsBytes();
                            final parsed = MultiSpawn.parseXlsxBytes(bytes);
                            if (parsed.isEmpty) {
                              importStatus = '文件里没有解析到有效账号（需要学号/密码/课程列）';
                            } else {
                              ctrl.text = parsed
                                  .map((r) =>
                                      '${r['username']}\t${r['password']}\t${r['courses']}')
                                  .join('\n');
                              importStatus = '已导入 ${parsed.length} 个账号（下方可编辑）';
                            }
                          } catch (e) {
                            importStatus = '读取失败: $e';
                          }
                          setDialogState(() {});
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          importStatus,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(ctx).colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrl,
                  maxLines: 9,
                  decoration: const InputDecoration(
                    hintText: '学号\t密码\t课程1,课程2,...\t服务器\t标签\n'
                        '例：\n'
                        '202543401056\t密码1\t大学体育3（瑜伽）-0001,美术鉴赏-0007\n'
                        '202530412016\t密码2\t影视鉴赏-0007\t\t通识选修课',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: serverCtrl,
                        decoration: const InputDecoration(
                          labelText: '默认服务器（行内留空时使用）',
                          hintText: '留空 = 丽江师范；已按上方所选学校预填',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: intervalCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '轮询间隔(ms)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: maxCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '每窗口最多选几门(0=全部)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<bool>(
                        initialValue: parallel,
                        decoration: const InputDecoration(
                          labelText: '抢课规则',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: true,
                            child: Text('并行抢课（同时发）'),
                          ),
                          DropdownMenuItem(
                            value: false,
                            child: Text('按志愿顺序（一门一门来）'),
                          ),
                        ],
                        onChanged: (v) => parallel = v ?? true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<bool>(
                        initialValue: autoRun,
                        decoration: const InputDecoration(
                          labelText: '启动模式',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: true,
                            child: Text('立即开始抢课'),
                          ),
                          DropdownMenuItem(
                            value: false,
                            child: Text('仅填好预设，不开始'),
                          ),
                        ],
                        onChanged: (v) => autoRun = v ?? true,
                      ),
                    ),
                  ],
                ),
                CheckboxListTile(
                  value: validateFirst,
                  onChanged: (v) => validateFirst = v ?? true,
                  title: const Text('启动前先验证登录（只启动能登录的账号）'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('启动窗口'),
          ),
        ],
        ),
      ),
    );
    if (ok != true) return;

    final rows = MultiSpawn.parseRows(ctrl.text);
    if (rows.isEmpty) {
      toaster.error('没有解析到有效行，格式：学号<TAB>密码<TAB>课程1,课程2');
      return;
    }
    // 解析预览：让用户确认学号/课程对应关系无误后再启动
    final confirmed = await _confirmBatch(rows);
    if (confirmed != true) return;
    final defaultServer = serverCtrl.text.trim();
    final intervalMs = int.tryParse(intervalCtrl.text.trim()) ?? 200;
    final maxSlots = int.tryParse(maxCtrl.text.trim()) ?? 0;
    if (intervalMs < 50) {
      toaster.error('轮询间隔不能小于 50ms');
      return;
    }

    // 可选：先逐个验证登录，只保留能登录的账号
    final valid = <Map<String, String>>[];
    final failedUsers = <String>[];
    if (validateFirst) {
      await _validateRows(rows, defaultServer, valid, failedUsers);
      logStore.info(
        '登录验证完成: 可用 ${valid.length}/${rows.length}，失败: ${failedUsers.join(', ')}',
      );
    } else {
      valid.addAll(rows);
    }
    if (valid.isEmpty) {
      toaster.error('没有能登录的账号（失败: ${failedUsers.join(', ')}）');
      return;
    }

    var okCount = 0;
    for (final row in valid) {
      final server = row['server']!.isEmpty ? defaultServer : row['server']!;
      final courses = row['courses']!.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      final done = await MultiSpawn.spawnWindow(
        username: row['username']!,
        password: row['password']!,
        server: server,
        tab: row['tab'] ?? '',
        courses: courses,
        intervalMs: intervalMs,
        maxSlots: maxSlots,
        parallel: parallel,
        autoRun: autoRun,
      );
      if (done) okCount++;
    }
    logStore.info('批量多开: 成功启动 $okCount/${valid.length} 个窗口');
    if (okCount > 0) {
      toaster.success(
        '已启动 $okCount 个抢课窗口${failedUsers.isEmpty ? '' : '，${failedUsers.length} 个账号无法登录已跳过'}',
      );
    } else {
      toaster.error('窗口启动失败，请检查 exe 路径权限');
    }
  }

  /// 解析预览确认框：列出每个账号解析出的课程（最多显示前 8 个）
  Future<bool?> _confirmBatch(List<Map<String, String>> rows) {
    const maxShow = 8;
    final preview = rows
        .take(maxShow)
        .map((r) => '${r['username']} → ${r['courses']}')
        .join('\n');
    final more = rows.length > maxShow ? '\n... 共 ${rows.length} 个账号' : '';
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('确认解析结果（${rows.length} 个账号）'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: SelectableText(
              '$preview$more\n\n课程按志愿顺序排列，确认无误后启动。',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认启动'),
          ),
        ],
      ),
    );
  }

  /// 逐个验证登录，弹窗显示进度；可登录的行放进 [valid]，失败学号放进 [failed]
  Future<void> _validateRows(
    List<Map<String, String>> rows,
    String defaultServer,
    List<Map<String, String>> valid,
    List<String> failed,
  ) async {
    if (!mounted) return;
    final progress = ValueNotifier<String>('准备验证...');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('验证登录中'),
        content: SizedBox(
          width: 360,
          child: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: progress,
                  builder: (_, v, _) => Text(v),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    try {
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        progress.value = '验证 ${i + 1}/${rows.length}: ${row['username']}';
        final server = row['server']!.isEmpty ? defaultServer : row['server']!;
        final loginOk = await MultiSpawn.validateLogin(
          server: server,
          username: row['username']!,
          password: row['password']!,
        );
        if (loginOk) {
          valid.add(row);
        } else {
          failed.add(row['username']!);
        }
      }
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final isPassword = _mode == _LoginMode.password;

      if (isPassword && _userCtrl.text.trim().isEmpty) {
        throw const _Invalid('请输入账号');
      }
      if (isPassword && _passCtrl.text.isEmpty) {
        throw const _Invalid('请输入密码');
      }
      if (!isPassword && _cookieCtrl.text.trim().isEmpty) {
        throw const _Invalid('请输入 Cookie');
      }

      final server = _selectedSchool.server;
      final client = await FClient.newWithBase(backend: server);

      if (isPassword) {
        await client.login(
          username: _userCtrl.text.trim(),
          password: _passCtrl.text,
        );
      } else {
        await client.insertCookies(cookies: _cookieCtrl.text.trim());
      }

      final accountInfo = await client.checkLogin();
      if (!mounted) return;

      final confirmed = await _confirmAccount(accountInfo);
      if (confirmed == true) {
        final username = isPassword ? _userCtrl.text.trim() : accountInfo;
        session.attachClient(username, client, school: _selectedSchool);

        // 保存 Cookie 供会话失效时自动重登
        try {
          final ck = await client.cookies();
          if (ck != null && ck.isNotEmpty) session.savedCookie = ck;
        } catch (_) {}

        if (mounted) {
          setState(() => _error = null);
        }
      } else {
        if (mounted) {
          setState(() => _error = '已取消登录');
        }
      }
    } on FError catch (e) {
      if (mounted) setState(() => _error = _describe(e));
    } on _Invalid catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '登录失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmAccount(String account) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('确认登录账号'),
        content: Text('检测到账号：\n\n$account\n\n确认登录此账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  String _describe(FError e) {
    final kind = switch (e.kind) {
      FErrorKind.loginFailed => '登录失败',
      FErrorKind.notyetStarted => '选课未开放',
      FErrorKind.cookieError => 'Cookie 无效',
      FErrorKind.reqwest => '网络错误',
      _ => '${e.kind}',
    };
    return '错误（$kind）：${e.error}';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: _SchoolSelector(
                  selectedSchool: _selectedSchool,
                  onChanged: (s) => setState(() => _selectedSchool = s),
                  busy: _busy,
                ),
              ),
              const SizedBox(height: 16),
              SegmentedButton<_LoginMode>(
                segments: const [
                  ButtonSegment(
                    value: _LoginMode.password,
                    label: Text('账密登录'),
                    icon: Icon(Icons.password),
                  ),
                  ButtonSegment(
                    value: _LoginMode.cookie,
                    label: Text('Cookie 登录'),
                    icon: Icon(Icons.cookie),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: _busy
                    ? null
                    : (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(height: 16),
              if (_mode == _LoginMode.password) ...[
                TextField(
                  controller: _userCtrl,
                  enabled: !_busy,
                  maxLines: 1,
                  decoration: const InputDecoration(
                    labelText: '学号 / 账号',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passCtrl,
                  enabled: !_busy,
                  maxLines: 1,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '密码',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) {
                    if (!_busy) _submit();
                  },
                ),
              ] else ...[
                TextField(
                  controller: _cookieCtrl,
                  enabled: !_busy,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Cookie',
                    hintText: 'JSESSIONID=...; zstack_cookie=...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('登录'),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _openMultiSpawn,
                icon: const Icon(Icons.grid_view, size: 18),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text('批量多开（粘贴账号表格）'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Invalid implements Exception {
  final String message;
  const _Invalid(this.message);
}

/// 学校选择器：预设学校列表 + 自定义入口
class _SchoolSelector extends StatelessWidget {
  const _SchoolSelector({
    required this.selectedSchool,
    required this.onChanged,
    required this.busy,
  });

  final School selectedSchool;
  final ValueChanged<School> onChanged;
  final bool busy;

  Future<void> _pick(BuildContext context) async {
    final selected = await showMenu<School?>(
      context: context,
      position: _menuPosition(context),
      items: [
        for (final s in kPresetSchools)
          PopupMenuItem<School?>(
            value: s,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: _SchoolRow(
              name: s.name,
              server: s.server,
              selected: s.server == selectedSchool.server,
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<School?>(
          value: null,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 18),
              SizedBox(width: 12),
              Text('自定义学校…'),
            ],
          ),
        ),
      ],
    );

    if (!context.mounted) return;

    if (selected != null) {
      onChanged(selected);
    } else {
      final custom = await _showCustomDialog(context);
      if (custom != null) onChanged(custom);
    }
  }

  RelativeRect _menuPosition(BuildContext context) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final box = context.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    return RelativeRect.fromLTRB(
      topLeft.dx,
      topLeft.dy + box.size.height,
      overlay.size.width - topLeft.dx - box.size.width,
      0,
    );
  }

  /// 自定义学校：服务器地址 + 可选标签（每行 标签名=xkkz_id）
  Future<School?> _showCustomDialog(BuildContext context) async {
    final urlCtrl = TextEditingController(text: selectedSchool.server);
    final tabsCtrl = TextEditingController();
    try {
      final url = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('自定义学校'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: urlCtrl,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: '服务器地址',
                    hintText: 'http://jw.lingnan.edu.cn 或 .../jwglxt',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tabsCtrl,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: '标签页（可选，每行：中文名=xkkz_id）',
                    hintText: '例：通识选修课=54FB211AA25206F3E06370D2A8C08E99\n留空表示无需切换标签',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, urlCtrl.text.trim()),
              child: const Text('确认'),
            ),
          ],
        ),
      );

      if (url == null || url.isEmpty) return null;

      final tabs = <SchoolTab>[];
      for (final line in tabsCtrl.text.split('\n')) {
        final s = line.trim();
        if (s.isEmpty) continue;
        final eq = s.indexOf('=');
        if (eq > 0 && eq < s.length - 1) {
          tabs.add(SchoolTab(s.substring(eq + 1).trim(), s.substring(0, eq).trim()));
        }
      }
      return customSchool(url, tabs: tabs);
    } finally {
      urlCtrl.dispose();
      tabsCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextButton.icon(
      onPressed: busy ? null : () => _pick(context),
      icon: const Icon(Icons.school_outlined, size: 16),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              '${selectedSchool.name} · ${selectedSchool.server}',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
          const Icon(Icons.arrow_drop_down, size: 18),
        ],
      ),
    );
  }
}

/// 学校行：显示名称和服务器地址
class _SchoolRow extends StatelessWidget {
  const _SchoolRow({
    required this.name,
    required this.server,
    required this.selected,
  });

  final String name;
  final String server;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          selected ? Icons.check_circle : Icons.circle_outlined,
          size: 18,
          color: selected ? theme.colorScheme.primary : null,
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name),
            Text(
              server,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
