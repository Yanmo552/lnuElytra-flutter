import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/log_store.dart';
import '../services/toaster.dart';
import '../src/rust/api/logging.dart';

/// Improved log panel with a light theme and adjustable width.
class ImprovedLogPanel extends StatefulWidget {
  /// When true (default), renders a draggable divider on the left so the panel
  /// can sit side-by-side with another component (login form, workspace, etc.).
  /// Set to false when the panel fills the entire screen (e.g. a mobile tab).
  final bool showDivider;

  const ImprovedLogPanel({super.key, this.showDivider = true});

  @override
  State<ImprovedLogPanel> createState() => _ImprovedLogPanelState();
}

class _ImprovedLogPanelState extends State<ImprovedLogPanel> {
  static const double _minWidth = 280;
  static const double _maxWidth = 600;
  static const double _defaultWidth = 350;

  double _width = _defaultWidth;
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.showDivider) {
      return const _LogPanelContent();
    }
    return Row(
      children: [
        _buildDragHandle(),
        SizedBox(width: _width, child: const _LogPanelContent()),
      ],
    );
  }

  Widget _buildDragHandle() {
    final theme = Theme.of(context);
    final lineColor = _hovering
        ? theme.colorScheme.primary
        : theme.dividerColor;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onHorizontalDragUpdate: (details) {
          setState(() {
            _width = (_width - details.delta.dx).clamp(_minWidth, _maxWidth);
          });
        },
        child: Container(
          width: 8,
          color: theme.colorScheme.surface,
          child: Center(
            child: Container(
              width: 2,
              decoration: BoxDecoration(
                color: lineColor,
                borderRadius: const BorderRadius.all(Radius.circular(1)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LogPanelContent extends StatefulWidget {
  const _LogPanelContent();

  @override
  State<_LogPanelContent> createState() => _LogPanelContentState();
}

class _LogPanelContentState extends State<_LogPanelContent> {
  static String _fileName() {
    final now = DateTime.now();
    final ts =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
    return 'lnu_elytra_$ts.log';
  }

  Future<void> _copyToClipboard() async {
    final text = logStore.exportAll();
    if (text.isEmpty) {
      toaster.info('暂无日志可复制');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    toaster.success('已复制 ${logStore.totalCount} 条日志到剪贴板');
  }

  Future<void> _exportToFile() async {
    final text = logStore.exportAll();
    if (text.isEmpty) {
      toaster.info('暂无日志可导出');
      return;
    }
    final name = _fileName();
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$name');
      await file.writeAsString(text);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } else {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出日志',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: ['log', 'txt'],
      );
      if (path == null) return;
      await File(path).writeAsString(text);
      toaster.success('日志已导出到 $path');
    }
  }

  Future<void> _shareLogs() async {
    final text = logStore.exportAll();
    if (text.isEmpty) {
      toaster.info('暂无日志可分享');
      return;
    }
    final dir = await getTemporaryDirectory();
    final name = _fileName();
    final file = File('${dir.path}/$name');
    await file.writeAsString(text);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          _buildHeader(context, theme),
          Divider(height: 1, color: theme.dividerColor),
          const Expanded(child: _LogListView()),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    final iconColor = theme.colorScheme.onSurfaceVariant;
    const iconSize = 20.0;
    const padding = EdgeInsets.zero;
    const constraints = BoxConstraints(minWidth: 32, minHeight: 32);

    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.terminal, color: theme.colorScheme.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                '日志面板',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '复制到剪贴板',
                icon: Icon(Icons.copy, color: iconColor, size: iconSize),
                onPressed: _copyToClipboard,
                padding: padding,
                constraints: constraints,
              ),
              IconButton(
                tooltip: '导出到文件',
                icon: Icon(Icons.save_alt, color: iconColor, size: iconSize),
                onPressed: _exportToFile,
                padding: padding,
                constraints: constraints,
              ),
              IconButton(
                tooltip: '分享',
                icon: Icon(Icons.share, color: iconColor, size: iconSize),
                onPressed: _shareLogs,
                padding: padding,
                constraints: constraints,
              ),
              IconButton(
                tooltip: '清空',
                icon: Icon(
                  Icons.delete_outline,
                  color: iconColor,
                  size: iconSize,
                ),
                onPressed: logStore.clear,
                padding: padding,
                constraints: constraints,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              _LevelSelector(),
              SizedBox(width: 8),
              Expanded(child: _SearchBox()),
              SizedBox(width: 8),
              _LogCounter(),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchBox extends StatefulWidget {
  const _SearchBox();

  @override
  State<_SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<_SearchBox> {
  static const _kBorderRadius4 = BorderRadius.all(Radius.circular(4));
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 32,
      child: TextField(
        controller: _controller,
        decoration: InputDecoration(
          hintText: '搜索...',
          hintStyle: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          prefixIcon: Icon(
            Icons.search,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          border: OutlineInputBorder(
            borderRadius: _kBorderRadius4,
            borderSide: BorderSide(color: theme.dividerColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: _kBorderRadius4,
            borderSide: BorderSide(color: theme.dividerColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: _kBorderRadius4,
            borderSide: BorderSide(color: theme.colorScheme.primary),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          isDense: true,
        ),
        style: const TextStyle(fontSize: 12),
        onChanged: (value) {
          logStore.setSearchQuery(value);
        },
      ),
    );
  }
}

class _LogListView extends StatefulWidget {
  const _LogListView();

  @override
  State<_LogListView> createState() => _LogListViewState();
}

class _LogListViewState extends State<_LogListView> {
  final ScrollController _scroll = ScrollController();
  final Map<Object, String> _tsCache = {};
  bool _autoScroll = true;
  bool _scrollScheduled = false;

  static const List<String> _kMonoFallback = [
    'Cascadia Mono',
    'Consolas',
    'SF Mono',
    'Menlo',
    'DejaVu Sans Mono',
    'Roboto Mono',
    'monospace',
  ];

  static const TextStyle _kBaseStyle = TextStyle(
    fontFamilyFallback: _kMonoFallback,
    fontSize: 12,
    height: 1.4,
  );
  static const TextStyle _kTimeStyle = TextStyle(color: Color(0xFF757575));
  static const TextStyle _kTargetStyle = TextStyle(color: Color(0xFF9E9E9E));
  static const TextStyle _kMessageStyle = TextStyle(color: Color(0xFF424242));

  static const List<TextStyle> _kLevelStyles = [
    TextStyle(color: Color(0xFF9E9E9E), fontWeight: FontWeight.w600),
    TextStyle(color: Color(0xFF2196F3), fontWeight: FontWeight.w600),
    TextStyle(color: Color(0xFF4CAF50), fontWeight: FontWeight.w600),
    TextStyle(color: Color(0xFFFF9800), fontWeight: FontWeight.w600),
    TextStyle(color: Color(0xFFF44336), fontWeight: FontWeight.w600),
  ];

  static final List<String> _kLevelLabels = [
    for (final n in kLevelNames) '${n.padRight(5)} ',
  ];

  @override
  void initState() {
    super.initState();
    logStore.addListener(_onLogs);
  }

  void _onLogs() {
    if (!_autoScroll || !_scroll.hasClients || _scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    logStore.removeListener(_onLogs);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: logStore,
            builder: (context, _) {
              final entries = logStore.visible;
              if (entries.isEmpty) {
                _tsCache.clear();
                return Center(
                  child: Text(
                    '暂无日志',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                );
              }
              return Scrollbar(
                controller: _scroll,
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (context, i) => _logLine(entries[i]),
                ),
              );
            },
          ),
        ),
        Positioned(right: 12, bottom: 12, child: _autoScrollToggle()),
      ],
    );
  }

  Widget _autoScrollToggle() {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
      shape: const CircleBorder(),
      elevation: 2,
      child: IconButton(
        tooltip: _autoScroll ? '自动滚动开' : '自动滚动关',
        icon: Icon(
          _autoScroll ? Icons.vertical_align_bottom : Icons.lock_outline,
          color: _autoScroll
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
          size: 18,
        ),
        onPressed: () {
          setState(() => _autoScroll = !_autoScroll);
          if (_autoScroll) _onLogs();
        },
      ),
    );
  }

  String _formatTs(Object timeMillis) {
    return _tsCache.putIfAbsent(timeMillis, () {
      final time = DateTime.fromMillisecondsSinceEpoch(millisOf(timeMillis));
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
    });
  }

  Widget _logLine(LogEntry e) {
    final ts = _formatTs(e.timeMillis);
    final lvl = e.level.clamp(0, 4);
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Text.rich(
          TextSpan(
            style: _kBaseStyle,
            children: [
              TextSpan(text: '$ts ', style: _kTimeStyle),
              TextSpan(text: _kLevelLabels[lvl], style: _kLevelStyles[lvl]),
              TextSpan(text: '${e.target}  ', style: _kTargetStyle),
              TextSpan(text: e.message, style: _kMessageStyle),
            ],
          ),
        ),
      ),
    );
  }
}

class _LevelSelector extends StatefulWidget {
  const _LevelSelector();

  @override
  State<_LevelSelector> createState() => _LevelSelectorState();
}

class _LevelSelectorState extends State<_LevelSelector> {
  static const _kBorderRadius4 = BorderRadius.all(Radius.circular(4));
  static const Map<int, Color> _kLevelColors = {
    0: Color(0xFF9E9E9E), // TRACE
    1: Color(0xFF2196F3), // DEBUG
    2: Color(0xFF4CAF50), // INFO
    3: Color(0xFFFF9800), // WARN
    4: Color(0xFFF44336), // ERROR
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final level = logStore.minLevel;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '等级',
          style: TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 4),
        PopupMenuButton<int>(
          initialValue: level,
          onSelected: (v) {
            setState(() {});
            logStore.setMinLevel(v);
          },
          offset: const Offset(0, 36),
          constraints: const BoxConstraints(minWidth: 100),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(color: theme.dividerColor),
              borderRadius: _kBorderRadius4,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  kLevelNames[level],
                  style: TextStyle(
                    color: _kLevelColors[level],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.arrow_drop_down,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
          itemBuilder: (context) => [
            for (int i = 0; i < kLevelNames.length; i++)
              PopupMenuItem(
                value: i,
                height: 36,
                child: Text(
                  kLevelNames[i],
                  style: TextStyle(
                    color: _kLevelColors[i],
                    fontSize: 13,
                    fontWeight: i == level ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _LogCounter extends StatelessWidget {
  const _LogCounter();

  static const _kRadius = BorderRadius.all(Radius.circular(12));
  static const _kStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w500);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: logStore,
      builder: (context, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: _kRadius,
        ),
        child: Text(
          '${logStore.visible.length}/${logStore.totalCount}',
          style: _kStyle.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
