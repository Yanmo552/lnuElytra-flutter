import 'package:flutter/material.dart';

import '../../models/school.dart';
import '../../services/session.dart';
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
