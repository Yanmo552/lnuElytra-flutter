import 'package:flutter/material.dart';

import '../../models/endpoint.dart';
import '../../services/session.dart';
import '../../src/rust/third_party/lnu_elytra/flutter.dart';

/// Login page with an endpoint selector.
///
/// Collects credentials, builds a new client for the selected endpoint and
/// logs in, then attaches it to the global [session] upon confirmation.
/// No data is persisted.
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

  // Currently selected endpoint
  Endpoint _selectedEndpoint = kPresetEndpoints.first;

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

      // Validate input — username is only required for password login.
      if (isPassword && _userCtrl.text.trim().isEmpty) {
        throw const _Invalid('请输入账号');
      }
      if (isPassword) {
        if (_passCtrl.text.isEmpty) {
          throw const _Invalid('请输入密码');
        }
      } else {
        if (_cookieCtrl.text.trim().isEmpty) {
          throw const _Invalid('请输入 Cookie');
        }
      }

      // Build a new client for the selected endpoint and log in.
      final client = await FClient.newWithBase(backend: _selectedEndpoint.url);

      if (isPassword) {
        await client.login(
          username: _userCtrl.text.trim(),
          password: _passCtrl.text,
        );
      } else {
        await client.insertCookies(cookies: _cookieCtrl.text.trim());
      }

      // Verify and retrieve account info
      final accountInfo = await client.checkLogin();
      if (!mounted) return;

      final confirmed = await _confirmAccount(accountInfo);

      if (confirmed == true) {
        // Attach the client to the global session.
        // For cookie login, the username comes from the server response.
        final username = isPassword ? _userCtrl.text.trim() : accountInfo;
        session.attachClient(username, client);

        if (mounted) {
          setState(() => _error = null);
        }
      } else {
        // User cancelled
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
    return '错误（${e.kind}）：${e.error}';
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
              // Endpoint selector
              Align(
                alignment: Alignment.centerLeft,
                child: _EndpointSelector(
                  selectedEndpoint: _selectedEndpoint,
                  onChanged: (ep) => setState(() => _selectedEndpoint = ep),
                  busy: _busy,
                ),
              ),
              const SizedBox(height: 12),

              // Login mode selector
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

              // Input fields
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
                  maxLines: 1,
                  decoration: const InputDecoration(
                    labelText: 'Cookie',
                    hintText: 'JSESSIONID=...; X-LB=...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // Error message
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

              // Login button
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

/// Endpoint selector: tapping opens a preset list with a custom entry, showing the actual URL.
class _EndpointSelector extends StatelessWidget {
  const _EndpointSelector({
    required this.selectedEndpoint,
    required this.onChanged,
    required this.busy,
  });

  final Endpoint selectedEndpoint;
  final ValueChanged<Endpoint> onChanged;
  final bool busy;

  Future<void> _pick(BuildContext context) async {
    final selected = await showMenu<Endpoint?>(
      context: context,
      position: _menuPosition(context),
      items: [
        for (final ep in kPresetEndpoints)
          PopupMenuItem<Endpoint?>(
            value: ep,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: _PresetRow(
              label: ep.label,
              url: ep.url,
              selected: ep.url == selectedEndpoint.url,
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<Endpoint?>(
          value: null,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 18),
              SizedBox(width: 12),
              Text('自定义…'),
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

  Future<Endpoint?> _showCustomDialog(BuildContext context) async {
    final controller = TextEditingController(text: selectedEndpoint.url);
    try {
      final url = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('自定义地址'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '服务器地址',
              hintText: 'http://jw.lingnan.edu.cn',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('确认'),
            ),
          ],
        ),
      );

      if (url == null || url.isEmpty) return null;
      return Endpoint('自定义', url);
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextButton.icon(
      onPressed: busy ? null : () => _pick(context),
      icon: const Icon(Icons.dns_outlined, size: 16),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              '正在访问：${selectedEndpoint.url}',
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

/// Preset row: displays the label and actual URL.
class _PresetRow extends StatelessWidget {
  const _PresetRow({
    required this.label,
    required this.url,
    required this.selected,
  });

  final String label;
  final String url;
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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              Text(
                url,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
