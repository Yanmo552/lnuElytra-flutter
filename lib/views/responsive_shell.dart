import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../components/log_panel.dart';
import '../models/school.dart';
import '../services/auto_start.dart';
import '../services/log_store.dart';
import '../services/preset_store.dart';
import '../services/session.dart';
import '../services/toaster.dart';
import '../src/rust/third_party/lnu_elytra/flutter.dart';
import 'home/grab_workspace.dart';
import 'login/login_page.dart';

/// Responsive layout breakpoint: below this value is mobile, at or above is desktop.
const double kResponsiveBreakpoint = 800;

/// Main responsive shell.
///
/// Shows [LoginPage] when the user is not logged in; after login, shows the
/// course-grabbing workspace and real-time log panel:
/// side-by-side layout on desktop, bottom tab layout on mobile.
class ResponsiveShell extends StatefulWidget {
  const ResponsiveShell({super.key});

  @override
  State<ResponsiveShell> createState() => _ResponsiveShellState();
}

class _ResponsiveShellState extends State<ResponsiveShell> {
  int _mobileTabIndex = 0;
  bool _checkingLogin = false;

  @override
  void initState() {
    super.initState();
    final req = autoStart;
    autoStart = null;
    if (req != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _processAutoStart(req));
    }
  }

  Future<void> _processAutoStart(AutoStartRequest req) async {
    try {
            final school = req.server.isEmpty
          ? schoolById('lijiang') ?? kPresetSchools.first
          : (schoolByServer(req.server) ?? customSchool(req.server));
      final client = await FClient.newWithBase(backend: school.server);
      await client.login(username: req.username, password: req.password);
      await client.checkLogin();

      session.attachClient(req.username, client, school: school);
      try {
        final ck = await client.cookies();
        if (ck != null && ck.isNotEmpty) session.savedCookie = ck;
      } catch (_) {}

      final tabIdx = _resolveTabIndex(school, req.tab);
      presetStore.setTabIndex(tabIdx);
      session.tabIndex = tabIdx;
      presetStore.setIntervalMs(req.intervalMs);
      presetStore.setMaxSlots(req.maxSlots);
      presetStore.setParallel(req.parallel);
      for (final c in req.courses) {
        presetStore.addCourse(c);
      }

      logStore.info('自动登录成功: ${req.username}，预设 ${req.courses.length} 门课');
      if (req.autoRun) {
        autoRunPending.value = true;
      } else {
        logStore.info('启动模式: 仅填好预设，不自动开始');
      }
    } catch (e) {
      logStore.error('自动登录失败: ' + req.username + ', $e');
      if (mounted) toaster.error('自动登录失败: $e');
    }
  }

  int _resolveTabIndex(School school, String tabText) {
    final t = tabText.trim();
    if (t.isEmpty || !school.hasTabs) return -1;
    for (var i = 0; i < school.tabs.length; i++) {
      final tab = school.tabs[i];
      if (tab.id == t ||
          tab.name == t ||
          tab.name.contains(t) ||
          t.contains(tab.name)) {
        return i;
      }
    }
    return -1;
  }

  Future<void> _checkLogin() async {
    setState(() => _checkingLogin = true);
    try {
      final info = await session.verifyLogin();
      try {
        await session.reinit();
        if (!mounted) return;
        toaster.success('登录有效，已重新初始化，账号：$info');
      } on FError catch (e) {
        if (!mounted) return;
        toaster.error('登录有效，但 init 执行失败：${e.error}（可能是选课未开放）');
      } catch (e) {
        if (!mounted) return;
        toaster.error('登录有效，但 init 执行失败：$e');
      }
    } catch (e) {
      if (!mounted) return;
      toaster.error('登录已失效，正在退出：$e');
      // Session expired — clear it so the shell switches back to the login page.
      session.logout();
    } finally {
      if (mounted) setState(() => _checkingLogin = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= kResponsiveBreakpoint;
            if (!session.isLoggedIn) {
              return isWide
                  ? _buildDesktopLoginLayout()
                  : _buildMobileLoginLayout();
            }
            return isWide ? _buildDesktopLayout() : _buildMobileLayout();
          },
        );
      },
    );
  }

  // ── Desktop login: login form + log panel side by side ──
  Widget _buildDesktopLoginLayout() {
    return const Scaffold(
      body: Row(
        children: [
          Expanded(child: LoginPage()),
          ImprovedLogPanel(),
        ],
      ),
    );
  }

  // ── Mobile login: bottom tabs to switch between login form and log panel ──
  Widget _buildMobileLoginLayout() {
    return Scaffold(
      body: IndexedStack(
        index: _mobileTabIndex,
        children: [
          const LoginPage(),
          const ImprovedLogPanel(showDivider: false),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _mobileTabIndex,
        onTap: (index) => setState(() => _mobileTabIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.login), label: '登录'),
          BottomNavigationBarItem(icon: Icon(Icons.terminal), label: '日志面板'),
        ],
      ),
    );
  }

  // Desktop layout: top bar + main area + log panel (side by side)
  Widget _buildDesktopLayout() {
    return Scaffold(
      body: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                _buildDesktopAppBar(),
                const Expanded(child: GrabWorkspace()),
              ],
            ),
          ),
          const ImprovedLogPanel(),
        ],
      ),
    );
  }

  // Mobile layout: top bar + main area + bottom tabs to switch to log
  Widget _buildMobileLayout() {
    return Scaffold(
      appBar: _buildMobileAppBar(),
      body: IndexedStack(
        index: _mobileTabIndex,
        children: [const GrabWorkspace(), _buildMobileLogScreen()],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _mobileTabIndex,
        onTap: (index) => setState(() => _mobileTabIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.rocket_launch),
            label: '抢课任务',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.terminal), label: '日志面板'),
        ],
      ),
    );
  }

  Widget _buildDesktopAppBar() {
    final theme = Theme.of(context);
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              session.username ?? '未登录',
              style: theme.textTheme.titleMedium,
            ),
          ),
          ..._buildActions(),
        ],
      ),
    );
  }

  AppBar _buildMobileAppBar() {
    return AppBar(
      title: Text(session.username ?? '未登录'),
      actions: _buildActions(),
    );
  }

  Future<void> _launch(String url) async {
    try {
      if (!await launchUrl(Uri.parse(url))) {
        toaster.error('无法打开链接');
      }
    } catch (_) {
      toaster.error('无法打开链接');
    }
  }

  List<Widget> _buildActions() {
    return [
      IconButton(
        icon: _checkingLogin
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh),
        tooltip: '刷新',
        onPressed: _checkingLogin ? null : _checkLogin,
      ),
      IconButton(
        icon: const Icon(Icons.help_outline),
        tooltip: '帮助',
        onPressed: () => _launch('https://lnu-elytra.mcitem.net/'),
      ),
      IconButton(
        icon: const Icon(Icons.code),
        tooltip: 'GitHub',
        onPressed: () => _launch('https://github.com/mcitem/lnuElytra'),
      ),
      IconButton(
        icon: const Icon(Icons.logout),
        tooltip: '退出登录',
        onPressed: () => session.logout(),
      ),
    ];
  }

  Widget _buildMobileLogScreen() {
    return const ImprovedLogPanel(showDivider: false);
  }
}

