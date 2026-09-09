import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/auto_start.dart';
import '../../../services/log_store.dart';
import '../../../services/preset_store.dart';
import '../../../services/session.dart';
import '../../../src/rust/third_party/lnu_elytra.dart';
import '../../../src/rust/third_party/lnu_elytra/flutter.dart';

/// 抢课策略：并行 / 按志愿顺序
enum GrabStrategy { parallel, sequential }

/// 单门预设课程的运行状态
enum PresetStatus { pending, running, success, giveUp, failed }

class _PresetTask {
  _PresetTask(this.name);
  final String name;
  PresetStatus status = PresetStatus.pending;
  String note = '';
  int attempts = 0;
}

class _TaskNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// 自动抢课页：预设课程（按添加顺序 = 志愿顺序）+ 监控循环
class AutoGrabTab extends StatefulWidget {
  const AutoGrabTab({super.key});

  @override
  State<AutoGrabTab> createState() => _AutoGrabTabState();
}

class _AutoGrabTabState extends State<AutoGrabTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  static const _kButtonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(8)),
  );
  static final _kAddStyle = FilledButton.styleFrom(
    padding: EdgeInsets.zero,
    shape: _kButtonShape,
  );
  static final _kFilledStyle = FilledButton.styleFrom(shape: _kButtonShape);
  static final _kOutlinedStyle = OutlinedButton.styleFrom(shape: _kButtonShape);

  final _inputCtrl = TextEditingController();
  final _maxSlotsCtrl = TextEditingController();
  final _intervalCtrl = TextEditingController();
  final _taskNotifier = _TaskNotifier();
  final List<_PresetTask> _tasks = [];

  GrabStrategy _strategy = GrabStrategy.parallel;
  int _maxSlots = 0; // 0 = 全部预设
  int _intervalMs = 200;
  int _tabIndex = -1; // -1 = 自动遍历

  bool _running = false;
  bool _cancelRequested = false;
  bool _optionsExpanded = true;

  @override
  void initState() {
    super.initState();
    _syncTasksFromStore();
    _maxSlots = presetStore.maxSlots;
    _intervalMs = presetStore.intervalMs;
    _strategy = presetStore.parallel
        ? GrabStrategy.parallel
        : GrabStrategy.sequential;
    _tabIndex = presetStore.tabIndex;
    _intervalCtrl.text = '$_intervalMs';
    _maxSlotsCtrl.text = '$_maxSlots';

    // 子窗口模式（--auto）：登录可能在工作台挂载之后才完成，
    // 监听预设/自动启动标志的变化，随时补课并自动开始监控。
    presetStore.addListener(_onPresetsChanged);
    autoRunPending.addListener(_onAutoRunChanged);
    _maybeAutoStart();
  }

  @override
  void dispose() {
    presetStore.removeListener(_onPresetsChanged);
    autoRunPending.removeListener(_onAutoRunChanged);
    _inputCtrl.dispose();
    _maxSlotsCtrl.dispose();
    _intervalCtrl.dispose();
    _taskNotifier.dispose();
    super.dispose();
  }

  /// 预设课程变化（子窗口自动登录写入、或用户手动增删）时同步任务列表
  void _onPresetsChanged() {
    _syncTasksFromStore();
    _maybeAutoStart();
  }

  void _onAutoRunChanged() {
    _maybeAutoStart();
  }

  /// 子窗口模式：登录完成 + 有预设 + 未运行 → 自动开始监控
  void _maybeAutoStart() {
    if (autoRunPending.value && presetStore.courses.isNotEmpty && !_running) {
      autoRunPending.value = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_running) _start();
      });
    }
  }

  /// 把 presetStore 里的课程同步到界面任务列表（幂等，运行中不动）
  void _syncTasksFromStore() {
    if (_running) return;
    final names = presetStore.courses;
    _tasks.removeWhere((t) => !names.contains(t.name));
    for (final n in names) {
      if (!_tasks.any((t) => t.name == n)) {
        _tasks.add(_PresetTask(n));
      }
    }
    if (mounted) setState(() {});
  }

  // ---------- 预设课程管理 ----------

  void _addPreset() {
    final name = _inputCtrl.text.trim();
    if (name.isEmpty) return;
    if (_tasks.any((t) => t.name == name)) {
      _inputCtrl.clear();
      return;
    }
    setState(() {
      _tasks.add(_PresetTask(name));
      _inputCtrl.clear();
    });
    presetStore.addCourse(name);
    logStore.info('已添加: $name');
  }

  void _removeAt(int i) {
    if (_running) return;
    setState(() => _tasks.removeAt(i));
    presetStore.removeCourseAt(i);
  }

  void _move(int i, int delta) {
    if (_running) return;
    final j = i + delta;
    if (j < 0 || j >= _tasks.length) return;
    setState(() {
      final t = _tasks.removeAt(i);
      _tasks.insert(j, t);
    });
    presetStore.moveCourse(i, j);
  }

  // ---------- 监控循环 ----------

  Future<void> _start() async {
    if (_tasks.isEmpty || _running) return;
    session.tabIndex = _tabIndex;
    presetStore.setTabIndex(_tabIndex);

    setState(() {
      _running = true;
      _cancelRequested = false;
      for (final t in _tasks) {
        t.status = PresetStatus.pending;
        t.note = '';
        t.attempts = 0;
      }
    });

    final strategy = _strategy;
    final interval = _intervalMs;
    final maxSlots = _maxSlots;

    logStore.info(
      '开始监控，间隔 ${interval}ms，预设 ${_tasks.length} 门课'
      '，最多选 ${maxSlots == 0 ? _tasks.length : maxSlots} 门，'
      '策略=${strategy == GrabStrategy.parallel ? "并行" : "顺序"}',
    );

    // 1) 等 init 成功（= 选课开放）
    final open = await _waitOpen();
    if (!open || !mounted || _cancelRequested) {
      _finishRun();
      return;
    }

    // 2) 抢课循环
    while (!_cancelRequested) {
      final remaining =
          _tasks
              .where(
                (t) =>
                    t.status != PresetStatus.success &&
                    t.status != PresetStatus.giveUp,
              )
              .toList();
      if (remaining.isEmpty) {
        logStore.info('全部预设课程已成功/放弃');
        break;
      }

      final targets = (maxSlots > 0 && remaining.length > maxSlots)
          ? remaining.sublist(0, maxSlots)
          : remaining;

      if (strategy == GrabStrategy.parallel) {
        await Future.wait(targets.map((t) => _grabOne(t)));
      } else {
        for (final t in targets) {
          if (_cancelRequested) break;
          await _grabOne(t);
        }
      }

      if (_cancelRequested) break;
      final still = _tasks.any(
        (t) =>
            t.status != PresetStatus.success &&
            t.status != PresetStatus.giveUp,
      );
      if (!still) break;
      await _delay(interval);
    }

    _finishRun();
  }

  void _finishRun() {
    if (mounted) {
      setState(() {
        _running = false;
        _cancelRequested = false;
        for (final t in _tasks) {
          if (t.status != PresetStatus.success &&
              t.status != PresetStatus.giveUp) {
            t.status = PresetStatus.pending;
            t.note = '';
          }
        }
      });
    }
    logStore.info('监控已停止（成功 ${_successCount()}/${_tasks.length} 门）');
  }

  int _successCount() =>
      _tasks.where((t) => t.status == PresetStatus.success).length;

  void _cancel() {
    if (!_running) return;
    setState(() => _cancelRequested = true);
    for (final t in _tasks) {
      if (t.status == PresetStatus.running) {
        t.note = '取消中...';
      }
    }
    _taskNotifier.notify();
  }

  Future<bool> _waitOpen() async {
    logStore.info('正在检测选课开放状态（init）...');
    while (!_cancelRequested) {
      try {
        await session.reinit();
        logStore.info('=== init 成功，选课已开放 ===');
        return true;
      } on FError catch (e) {
        if (e.kind == FErrorKind.notyetStarted) {
          logStore.info('选课未开放，等待开放中...');
          await _delay(1000);
          continue;
        }
        if (e.kind == FErrorKind.loginFailed ||
            e.kind == FErrorKind.cookieError) {
          logStore.error('登录失效，尝试自动重登...');
          if (await session.relogin()) {
            logStore.info('自动重登成功，继续等待开放');
            await _delay(1000);
            continue;
          }
          logStore.error('自动重登失败，停止监控');
          return false;
        }
        logStore.error('init 异常: ${e.error}，继续等待');
        await _delay(1000);
        continue;
      } catch (e) {
        logStore.error('init 异常: $e，继续等待');
        await _delay(1000);
        continue;
      }
    }
    return false;
  }

  Future<void> _delay(int ms) async {
    if (ms <= 0) return;
    await Future.delayed(Duration(milliseconds: ms));
  }

  // ---------- 抢一门课 ----------

  Future<void> _grabOne(_PresetTask t) async {
    if (_cancelRequested || !mounted) return;
    _update(t, PresetStatus.running, '查询教学班...');
    t.attempts++;

    try {
      final course = await _resolve(t.name);
      if (course == null) {
        _update(t, PresetStatus.failed, '未找到课程（第 ${t.attempts} 次，重试中）');
        return;
      }

      final jxb = _pickExactJxb(course, t.name);
      if (jxb == null) {
        _update(t, PresetStatus.failed, '无可用教学班（第 ${t.attempts} 次，重试中）');
        return;
      }

      logStore.info(
        '抢课: ${course.kcmc.isEmpty ? t.name : course.kcmc}'
        '（${jxb.jxbmc.isEmpty ? jxb.doId : jxb.jxbmc}）',
      );

      final resp = await session.selectCourse(
        courseId: course.kchId,
        courseDoId: jxb.doId,
      );

      final msg = resp.msg ?? '';
      if (resp.flag == '1') {
        _update(t, PresetStatus.success, '✅ 选课成功！');
        logStore.info('✅ 选课成功: ${course.kcmc.isEmpty ? t.name : course.kcmc}');
        return;
      }

      // 需要先选子教学班（如应急救护培训）
      if (msg.contains('子教学班') || msg.contains('子班')) {
        logStore.info('$t.name 需要选择子教学班，尝试子班选课...');
        final ok = await _trySubclass(course, jxb, t);
        if (ok) {
          _update(t, PresetStatus.success, '✅ 子班选课成功！');
          return;
        }
        _update(t, PresetStatus.failed, '子班选课失败（第 ${t.attempts} 次，重试中）');
        return;
      }

      if (msg.contains('超过')) {
        _update(t, PresetStatus.giveUp, '已达选课上限：$msg');
        logStore.warn('$t.name 已达上限: $msg');
        return;
      }

      _update(t, PresetStatus.failed, '$msg（第 ${t.attempts} 次，重试中）');
    } on FError catch (e) {
      logStore.error('抢课异常: ${t.name}, ${e.error}');
      if (e.kind == FErrorKind.loginFailed || e.kind == FErrorKind.cookieError) {
        logStore.error('登录失效，尝试自动重登...');
        if (await session.relogin()) {
          _update(t, PresetStatus.failed, '已自动重登，重试中');
        } else {
          logStore.error('自动重登失败，停止监控');
          _update(t, PresetStatus.failed, '登录失效，已停止');
          _cancelRequested = true;
        }
        return;
      }
      _update(t, PresetStatus.failed, '错误：${e.error}（重试中）');
    } catch (e) {
      logStore.error('抢课异常: ${t.name}, $e');
      _update(t, PresetStatus.failed, '错误：$e（重试中）');
    }
  }

  /// 子教学班选课：V2（丽江专用端点）→ V1（通用）
  Future<bool> _trySubclass(Course course, Jxb jxb, _PresetTask t) async {
    try {
      final r = await session.selectCourseSubclassV2(
        jxbId: jxb.jxbId,
        doJxbId: jxb.doId,
        jxbzls: '1',
      );
      if (r.flag == '1') return true;
      logStore.info('子班V2: ${r.msg}');
    } catch (e) {
      logStore.info('子班V2-err: $e');
    }
    try {
      final ids = await session.fetchSubclassIds(jxb.doId);
      if (ids.isNotEmpty) {
        final combined = '${jxb.doId},${ids.first}';
        final r = await session.selectCourseSubclass(
          courseId: course.kchId,
          courseDoId: combined,
          kcmc: course.kcmc,
          xkkzId: course.xkkzId,
        );
        if (r.flag == '1') return true;
        logStore.info('子班V1: ${r.msg}');
      }
    } catch (e) {
      logStore.info('子班V1-err: $e');
    }
    return false;
  }

  // ---------- 解析课程（支持多标签学校） ----------

  Future<Course?> _fetchOne(String q) async {
    try {
      final c = await session.fetchCourses(q);
      if (c.jxb.isNotEmpty) return c;
    } catch (_) {}
    return null;
  }

  String _stripSuffix(String name) =>
      name.replaceFirst(RegExp(r'-\d{1,4}$'), '');

  String? _courseNumber(String name) {
    final m = RegExp(r'(\d{6,9})-\d{1,4}$').firstMatch(name);
    return m?.group(1);
  }

  List<String> _candidates(String preset) {
    final out = <String>[preset];
    final stripped = _stripSuffix(preset);
    if (stripped.isNotEmpty && stripped != preset) out.add(stripped);
    final cn = _courseNumber(preset);
    if (cn != null && !out.contains(cn)) out.add(cn);
    return out;
  }

  Future<Course?> _resolve(String preset) async {
    final school = session.school;
    final candidates = _candidates(preset);

    if (school == null || !school.hasTabs) {
      for (final q in candidates) {
        final c = await _fetchOne(q);
        if (c != null) return c;
      }
      return null;
    }

    // 多标签学校
    if (_tabIndex >= 0 && _tabIndex < school.tabs.length) {
      try {
        await session.switchTab(school.tabs[_tabIndex].id);
      } catch (_) {}
      for (final q in candidates) {
        final c = await _fetchOne(q);
        if (c != null) return c;
      }
      return null;
    }

    // 自动遍历所有标签
    for (final tab in school.tabs) {
      try {
        await session.switchTab(tab.id);
      } catch (_) {
        continue;
      }
      for (final q in candidates) {
        final c = await _fetchOne(q);
        if (c != null) {
          logStore.info('在标签 [${tab.name}] 找到: $preset');
          return c;
        }
      }
    }
    return null;
  }

  Jxb? _pickExactJxb(Course course, String preset) {
    if (course.jxb.isEmpty) return null;
    final m = RegExp(r'-(\d{1,4})$').firstMatch(preset);
    final suffix = m?.group(1);
    if (suffix != null) {
      for (final j in course.jxb) {
        if (j.jxbmc.endsWith('-$suffix') ||
            j.jxbmc.contains('-$suffix') ||
            j.doId.endsWith(suffix)) {
          return j;
        }
      }
    }
    return course.jxb.first;
  }

  void _update(_PresetTask t, PresetStatus status, String note) {
    t.status = status;
    t.note = note;
    if (mounted) _taskNotifier.notify();
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Column(
      children: [
        _buildControls(),
        const Divider(height: 1),
        Expanded(
          child: ListenableBuilder(
            listenable: _taskNotifier,
            builder: (context, _) => _buildList(),
          ),
        ),
      ],
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildInputRow(),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                onPressed: _running
                    ? null
                    : () => setState(
                        () => _optionsExpanded = !_optionsExpanded,
                      ),
                icon: Icon(
                  _optionsExpanded ? Icons.expand_less : Icons.expand_more,
                ),
                tooltip: _optionsExpanded ? '收起选项' : '展开选项',
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '最多选 ${_maxSlots == 0 ? "全部" : _maxSlots} 门'
                  ' · ${_strategy == GrabStrategy.parallel ? "并行" : "按志愿顺序"}'
                  ' · 间隔 ${_intervalMs}ms'
                  ' · ${_tabLabel()}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          if (_optionsExpanded) ...[
            const SizedBox(height: 8),
            _buildOptionsPanel(),
          ],
          const SizedBox(height: 12),
          _buildActionButtons(),
        ],
      ),
    );
  }

  String _tabLabel() {
    final school = session.school;
    if (school == null || !school.hasTabs) return '无标签';
    if (_tabIndex == -1) return '标签:自动遍历';
    if (_tabIndex >= 0 && _tabIndex < school.tabs.length) {
      return '标签:${school.tabs[_tabIndex].name}';
    }
    return '标签:自动遍历';
  }

  Widget _buildInputRow() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _inputCtrl,
            enabled: !_running,
            decoration: const InputDecoration(
              labelText: '添加预设课程（按添加顺序 = 志愿顺序）',
              hintText: '例：大学体育3（瑜伽）-0001 或 影视鉴赏-0007',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.add_task),
            ),
            onSubmitted: (_) {
              if (!_running) _addPreset();
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 56,
          width: 56,
          child: FilledButton(
            onPressed: _running ? null : _addPreset,
            style: _kAddStyle,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  Widget _buildOptionsPanel() {
    return Column(
      children: [
        Row(
          children: [
            const Text('最多选(门)：'),
            const SizedBox(width: 8),
            SizedBox(
              width: 90,
              child: TextField(
                enabled: !_running,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  hintText: '0=全部',
                ),
                controller: _maxSlotsCtrl,
                onChanged: (v) {
                  final val = int.tryParse(v);
                  if (val != null && val >= 0) {
                    setState(() => _maxSlots = val);
                    presetStore.setMaxSlots(val);
                  }
                },
              ),
            ),
            const SizedBox(width: 16),
            const Text('轮询间隔(ms)：'),
            const SizedBox(width: 8),
            SizedBox(
              width: 90,
              child: TextField(
                enabled: !_running,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                controller: _intervalCtrl,
                onChanged: (v) {
                  final val = int.tryParse(v);
                  if (val != null && val >= 0) {
                    setState(() => _intervalMs = val);
                    presetStore.setIntervalMs(val);
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('策略：'),
            const SizedBox(width: 8),
            Expanded(
              child: SegmentedButton<GrabStrategy>(
                segments: const [
                  ButtonSegment(value: GrabStrategy.parallel, label: Text('并行')),
                  ButtonSegment(
                    value: GrabStrategy.sequential,
                    label: Text('按志愿顺序'),
                  ),
                ],
                selected: {_strategy},
                onSelectionChanged: _running
                    ? null
                    : (s) {
                        setState(() => _strategy = s.first);
                        presetStore.setParallel(
                          s.first == GrabStrategy.parallel,
                        );
                      },
              ),
            ),
          ],
        ),
        if (session.school != null && session.school!.hasTabs) ...[
          const SizedBox(height: 12),
          _buildTabSelector(),
        ],
      ],
    );
  }

  Widget _buildTabSelector() {
    final school = session.school!;
    final items = <DropdownMenuItem<int>>[
      const DropdownMenuItem(value: -1, child: Text('自动遍历所有标签')),
      for (var i = 0; i < school.tabs.length; i++)
        DropdownMenuItem(value: i, child: Text(school.tabs[i].name)),
    ];
    return Row(
      children: [
        const Text('目标标签：'),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<int>(
            initialValue: _tabIndex,
            isDense: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
            items: items,
            onChanged: _running
                ? null
                : (v) {
                    setState(() => _tabIndex = v ?? -1);
                    presetStore.setTabIndex(v ?? -1);
                    session.tabIndex = v ?? -1;
                  },
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: (_running || _tasks.isEmpty) ? null : _start,
            style: _kFilledStyle,
            icon: _running
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_running ? '监控中...' : '开始监控'),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: (_running && !_cancelRequested) ? _cancel : null,
            style: _kOutlinedStyle,
            icon: const Icon(Icons.stop),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('停止'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildList() {
    if (_tasks.isEmpty) {
      return Center(
        child: Text(
          '暂无预设课程\n请先添加课程，按志愿顺序排列',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _tasks.length,
      itemBuilder: (context, i) {
        final t = _tasks[i];
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 14,
            child: Text('${i + 1}'),
          ),
          title: Text(t.name),
          subtitle: Text(
            t.note.isEmpty ? _statusText(t.status) : t.note,
            style: TextStyle(color: _statusColor(t.status)),
          ),
          trailing: _running
              ? Icon(
                  _statusIcon(t.status),
                  color: _statusColor(t.status),
                  size: 20,
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_upward, size: 18),
                      onPressed: () => _move(i, -1),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_downward, size: 18),
                      onPressed: () => _move(i, 1),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => _removeAt(i),
                    ),
                  ],
                ),
        );
      },
    );
  }

  String _statusText(PresetStatus s) => switch (s) {
        PresetStatus.pending => '等待',
        PresetStatus.running => '抢课中...',
        PresetStatus.success => '✅ 已成功',
        PresetStatus.giveUp => '已放弃',
        PresetStatus.failed => '重试中',
      };

  Color _statusColor(PresetStatus s) => switch (s) {
        PresetStatus.success => Colors.green,
        PresetStatus.giveUp => Colors.orange,
        PresetStatus.running => Colors.blue,
        PresetStatus.failed => Colors.redAccent,
        PresetStatus.pending => Colors.grey,
      };

  IconData _statusIcon(PresetStatus s) => switch (s) {
        PresetStatus.success => Icons.check_circle,
        PresetStatus.giveUp => Icons.flag,
        PresetStatus.running => Icons.autorenew,
        PresetStatus.failed => Icons.error_outline,
        PresetStatus.pending => Icons.schedule,
      };
}
