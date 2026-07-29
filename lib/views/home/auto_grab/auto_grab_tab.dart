import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/grab_outcome.dart';
import '../../../services/log_store.dart';
import '../../../services/session.dart';
import '../../../src/rust/third_party/lnu_elytra.dart';
import '../../../src/rust/third_party/lnu_elytra/flutter.dart';

/// Processing strategy for the keyword list.
enum GrabStrategy { parallel, sequential }

/// Runtime status of a single keyword.
enum KeywordStatus { pending, running, success, giveUp, failed }

class _KeywordTask {
  _KeywordTask(this.keyword, {this.teacherFilter, this.timeFilter});

  final String keyword;
  final String? teacherFilter;
  final String? timeFilter;
  KeywordStatus status = KeywordStatus.pending;
  String note = '';
  int attempts = 0;

  bool get hasFilters =>
      (teacherFilter != null && teacherFilter!.isNotEmpty) ||
      (timeFilter != null && timeFilter!.isNotEmpty);
}

class _TaskNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// Auto course-grabbing tab with a collapsible strategy panel.
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
  final _teacherFilterCtrl = TextEditingController();
  final _timeFilterCtrl = TextEditingController();
  final _retryIntervalCtrl = TextEditingController();
  final _taskNotifier = _TaskNotifier();
  final List<_KeywordTask> _tasks = [];

  GrabStrategy _strategy = GrabStrategy.parallel;
  int _retryIntervalMs = 100;

  bool _running = false;
  bool _cancelRequested = false;
  bool _strategyExpanded = true;

  @override
  void initState() {
    super.initState();
    _retryIntervalCtrl.text = '$_retryIntervalMs';
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _teacherFilterCtrl.dispose();
    _timeFilterCtrl.dispose();
    _retryIntervalCtrl.dispose();
    _taskNotifier.dispose();
    super.dispose();
  }

  void _addKeyword() {
    final kw = _inputCtrl.text.trim();
    if (kw.isEmpty) return;
    if (_tasks.any((t) => t.keyword == kw)) {
      _inputCtrl.clear();
      return;
    }
    final tf = _teacherFilterCtrl.text.trim();
    final st = _timeFilterCtrl.text.trim();
    setState(() {
      _tasks.add(
        _KeywordTask(
          kw,
          teacherFilter: tf.isEmpty ? null : tf,
          timeFilter: st.isEmpty ? null : st,
        ),
      );
      _inputCtrl.clear();
    });
  }

  void _removeAt(int i) {
    if (_running) return;
    setState(() => _tasks.removeAt(i));
  }

  Future<void> _start() async {
    if (_tasks.isEmpty || _running) return;

    setState(() {
      _running = true;
      _cancelRequested = false;
      _strategyExpanded = false;
      for (final t in _tasks) {
        t.status = KeywordStatus.pending;
        t.note = '';
        t.attempts = 0;
      }
    });

    await _runLoop();

    if (mounted) {
      setState(() {
        _running = false;
        _cancelRequested = false;
        for (final t in _tasks) {
          if (!_isSettled(t)) {
            t.status = KeywordStatus.pending;
            t.note = '';
          }
        }
      });
    }
  }

  void _cancel() {
    if (!_running) return;
    setState(() {
      _cancelRequested = true;
      for (final t in _tasks) {
        if (!_isSettled(t)) {
          t.status = KeywordStatus.pending;
          t.note = '';
        }
      }
    });
  }

  bool _isSettled(_KeywordTask t) =>
      t.status == KeywordStatus.success || t.status == KeywordStatus.giveUp;

  Future<void> _runLoop() async {
    while (!_cancelRequested) {
      final remaining = _tasks.where((t) => !_isSettled(t)).toList();
      if (remaining.isEmpty) break;

      if (_strategy == GrabStrategy.parallel) {
        await Future.wait(remaining.map((t) => _attempt(t)));
      } else {
        for (final t in remaining) {
          if (_cancelRequested) break;
          await _attempt(t);
          while (!_cancelRequested && !_isSettled(t)) {
            await _delay();
            if (_cancelRequested) break;
            await _attempt(t);
          }
        }
      }

      if (_cancelRequested) break;
      final stillRemaining = _tasks.any((t) => !_isSettled(t));
      if (!stillRemaining) break;
      await _delay();
    }
  }

  Future<void> _delay() async {
    if (_retryIntervalMs <= 0) return;
    await Future.delayed(Duration(milliseconds: _retryIntervalMs));
  }

  /// Match teaching classes against filter criteria.
  ///
  /// Prefers classes matching both teacher info (jsxx) and schedule (sksj)
  /// filters; falls back to jxb[0] if nothing matches.
  List<Jxb> _matchJxbs(Course course, _KeywordTask t) {
    if (course.jxb.isEmpty) return [];

    final tf = t.teacherFilter ?? '';
    final st = t.timeFilter ?? '';

    if (tf.isEmpty && st.isEmpty) return course.jxb;

    final matched = course.jxb.where((jxb) {
      final teacherOk = tf.isEmpty || jxb.jsxx.contains(tf);
      final timeOk = st.isEmpty || jxb.sksj.contains(st);
      return teacherOk && timeOk;
    }).toList();

    if (matched.isEmpty) return [course.jxb.first];
    return matched;
  }

  Future<void> _attempt(_KeywordTask t) async {
    if (_cancelRequested || !mounted) return;
    _update(t, KeywordStatus.running, '查询中...');
    t.attempts++;

    try {
      final course = await session.fetchCourses(t.keyword);
      logStore.info(
        'Course fetched: keyword="${t.keyword}", kchId=${course.kchId}, jxb_count=${course.jxb.length}',
      );

      final jxbs = _matchJxbs(course, t);
      if (jxbs.isEmpty) {
        _update(t, KeywordStatus.running, '暂无教学班，重试中（第 ${t.attempts} 次）');
        return;
      }

      final usedFallback =
          t.hasFilters &&
          jxbs.length == 1 &&
          course.jxb.length > 1 &&
          identical(jxbs.first, course.jxb.first);

      bool succeeded = false;
      for (final jxb in jxbs) {
        if (_cancelRequested) return;
        final outcome = await _tryJxbReturnOutcome(t, course, jxb);
        if (outcome == GrabOutcome.success) {
          succeeded = true;
          break;
        }
        if (outcome == GrabOutcome.giveUp) {
          _update(
            t,
            KeywordStatus.giveUp,
            '${jxb.jsxx} - 无法选择（第 ${t.attempts} 次）',
          );
          return;
        }
      }
      if (!succeeded && !_isSettled(t)) {
        final label = usedFallback
            ? '未匹配到筛选条件，回退首个教学班'
            : '匹配 ${jxbs.length} 个教学班';
        _update(t, KeywordStatus.running, '$label，重试中（第 ${t.attempts} 次）');
      }
    } on FError catch (e) {
      logStore.error('Auto-grab error: keyword="${t.keyword}", ${e.error}');
      if (e.kind == FErrorKind.loginFailed) {
        logStore.error('检测到登录失效，正在退出登录...');
        _cancelRequested = true;
        session.logout();
        return;
      }
      _update(t, KeywordStatus.failed, '错误：${e.error}（第 ${t.attempts} 次，将重试）');
    } catch (e) {
      logStore.error('Exception during grab: keyword="${t.keyword}", error=$e');
      _update(t, KeywordStatus.failed, '错误：$e（第 ${t.attempts} 次，将重试）');
    }
  }

  Future<GrabOutcome> _tryJxbReturnOutcome(
    _KeywordTask t,
    Course course,
    Jxb jxb,
  ) async {
    try {
      final resp = await session.selectCourse(
        courseId: course.kchId,
        courseDoId: jxb.doId,
      );
      logStore.info(
        'SelectCourseResponse: keyword="${t.keyword}", jxbId=${jxb.jxbId}, flag=${resp.flag}, msg=${resp.msg}',
      );
      final outcome = classifyResponse(resp);
      if (outcome == GrabOutcome.success) {
        final msg = resp.flag == '1' ? '选课成功' : (resp.msg ?? '未知结果');
        _update(t, KeywordStatus.success, '${jxb.jsxx} - $msg');
      }
      return outcome;
    } on FError catch (e) {
      if (e.kind == FErrorKind.loginFailed) {
        logStore.error('检测到登录失效，正在退出登录...');
        _cancelRequested = true;
        session.logout();
      } else {
        logStore.error(
          'SelectCourse error: keyword="${t.keyword}", jxbId=${jxb.jxbId}, ${e.error}',
        );
      }
      return GrabOutcome.retry;
    } catch (e) {
      logStore.error(
        'SelectCourse exception: keyword="${t.keyword}", jxbId=${jxb.jxbId}, error=$e',
      );
      return GrabOutcome.retry;
    }
  }

  void _update(_KeywordTask t, KeywordStatus status, String note) {
    t.status = status;
    t.note = note;
    if (mounted) _taskNotifier.notify();
  }

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
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 300),
            sizeCurve: Curves.easeInOut,
            crossFadeState: _strategyExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildInputRow(),
                const SizedBox(height: 12),
                _buildFilterSection(),
                const SizedBox(height: 16),
                _buildStrategyPanel(),
              ],
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
          TextButton.icon(
            onPressed: _running
                ? null
                : () => setState(() => _strategyExpanded = !_strategyExpanded),
            icon: Icon(
              _strategyExpanded ? Icons.expand_less : Icons.expand_more,
            ),
            label: Text(_strategyExpanded ? '收起' : '展开'),
          ),
          const SizedBox(height: 12),
          _buildActionButtons(),
          if (_running)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '任务运行中',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInputRow() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _inputCtrl,
            enabled: !_running,
            decoration: const InputDecoration(
              labelText: '输入课程号或精确教学班',
              hintText: '建议使用精确教学班',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.add_task),
            ),
            onSubmitted: (_) {
              if (!_running) _addKeyword();
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 56,
          width: 56,
          child: FilledButton(
            onPressed: _running ? null : _addKeyword,
            style: _kAddStyle,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterSection() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.tune,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              '筛选条件',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _teacherFilterCtrl,
                enabled: !_running,
                decoration: const InputDecoration(
                  labelText: '教师（jsxx）',
                  hintText: '可选，如：张三',
                  border: OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: Icon(Icons.person_outline, size: 20),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _timeFilterCtrl,
                enabled: !_running,
                decoration: const InputDecoration(
                  labelText: '时间（sksj）',
                  hintText: '可选，如：星期四第9-10节{9-16周}',
                  border: OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: Icon(Icons.schedule, size: 20),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStrategyPanel() {
    return Column(
      children: [
        _buildKeywordStrategySelector(),
        const SizedBox(height: 12),
        _buildRetryIntervalInput(),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildKeywordStrategySelector() {
    return Row(
      children: [
        const Text('课程策略：'),
        const SizedBox(width: 8),
        Expanded(
          child: SegmentedButton<GrabStrategy>(
            segments: const [
              ButtonSegment(value: GrabStrategy.parallel, label: Text('并行')),
              ButtonSegment(value: GrabStrategy.sequential, label: Text('按顺序')),
            ],
            selected: {_strategy},
            onSelectionChanged: _running
                ? null
                : (s) => setState(() => _strategy = s.first),
          ),
        ),
      ],
    );
  }

  Widget _buildRetryIntervalInput() {
    return Row(
      children: [
        const Text('重试间隔(ms)：'),
        const SizedBox(width: 8),
        SizedBox(
          width: 120,
          child: TextField(
            enabled: !_running,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            controller: _retryIntervalCtrl,
            onChanged: (v) {
              final val = int.tryParse(v);
              if (val != null && val >= 0) {
                setState(() => _retryIntervalMs = val);
              }
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
              child: Text(_running ? '抢课中...' : '启动任务'),
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
              child: Text(_cancelRequested ? '停止中...' : '取消任务'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildList() {
    if (_tasks.isEmpty) {
      return const Center(
        child: Text('添加一个或多个关键字，然后启动任务', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _tasks.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => _buildTaskTile(i, _tasks[i]),
    );
  }

  Widget _buildTaskTile(int i, _KeywordTask t) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _buildStatusIcon(t.status),
      title: Text(t.keyword),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (t.hasFilters) _buildFilterChips(t),
          if (t.note.isNotEmpty) Text(t.note),
        ],
      ),
      trailing: _running
          ? null
          : IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: '移除',
              onPressed: () => _removeAt(i),
            ),
    );
  }

  Widget _buildFilterChips(_KeywordTask t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 2,
        children: [
          if (t.teacherFilter != null)
            _chip(Icons.person_outline, t.teacherFilter!),
          if (t.timeFilter != null) _chip(Icons.schedule, t.timeFilter!),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Chip(
      avatar: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.only(right: 4),
    );
  }

  Widget _buildStatusIcon(KeywordStatus s) {
    switch (s) {
      case KeywordStatus.pending:
        return const Icon(Icons.schedule, color: Colors.grey);
      case KeywordStatus.running:
        return const SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case KeywordStatus.success:
        return const Icon(Icons.check_circle, color: Colors.green);
      case KeywordStatus.giveUp:
        return const Icon(Icons.do_not_disturb_on, color: Colors.redAccent);
      case KeywordStatus.failed:
        return const Icon(Icons.error_outline, color: Colors.orange);
    }
  }
}
