import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import '../src/rust/api/logging.dart';

/// Names for the integer log levels emitted by the Rust side.
/// 0=Trace, 1=Debug, 2=Info, 3=Warn, 4=Error.
const List<String> kLevelNames = ['TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR'];

/// Default minimum level shown by the log panel: TRACE.
const int kDefaultMinLevel = 0;

int millisOf(Object v) => v is BigInt ? v.toInt() : v as int;

/// Buffers tracing events streamed from Rust and provides level filtering.
class LogStore extends ChangeNotifier {
  static const int maxEntries = 5000;

  final Queue<LogEntry> _entries = Queue();
  StreamSubscription<LogEntry>? _sub;

  /// Minimum display level; entries below this level are hidden (not discarded).
  int minLevel = kDefaultMinLevel;

  /// Current search keyword; entries whose message and target both lack
  /// this substring (case-insensitive) are hidden. Empty means no filtering.
  String searchQuery = '';
  String _searchQueryLower = '';

  List<LogEntry>? _visibleCache;
  bool _notifyScheduled = false;

  /// Subscribes to the Rust tracing stream. Safe to call once.
  void start() {
    _sub ??= createLogStream().listen((e) {
      _entries.add(e);
      while (_entries.length > maxEntries) {
        _entries.removeFirst();
      }
      _scheduleNotify();
    });
  }

  /// Appends a Dart-side log entry, consistent with the Rust stream buffering.
  /// [level] uses the same scale as [LogEntry.level]
  /// (0=Trace .. 4=Error); defaults to INFO.
  void write(
    String message, {
    int level = 2,
    String target = 'dart',
    DateTime? time,
  }) {
    final millis = (time ?? DateTime.now()).millisecondsSinceEpoch;
    _entries.add(
      LogEntry(
        timeMillis: PlatformInt64Util.from(millis),
        level: level,
        target: target,
        message: message,
      ),
    );
    while (_entries.length > maxEntries) {
      _entries.removeFirst();
    }
    _scheduleNotify();
  }

  /// Convenience wrappers around [write] for common levels.
  void trace(String message, {String target = 'dart'}) =>
      write(message, level: 0, target: target);
  void debug(String message, {String target = 'dart'}) =>
      write(message, level: 1, target: target);
  void info(String message, {String target = 'dart'}) =>
      write(message, level: 2, target: target);
  void warn(String message, {String target = 'dart'}) =>
      write(message, level: 3, target: target);
  void error(String message, {String target = 'dart'}) =>
      write(message, level: 4, target: target);

  List<LogEntry> get visible {
    final cached = _visibleCache;
    if (cached != null) return cached;
    final q = _searchQueryLower;
    final result = _entries
        .where((e) {
          if (e.level < minLevel) return false;
          if (q.isEmpty) return true;
          return e.message.toLowerCase().contains(q) ||
              e.target.toLowerCase().contains(q);
        })
        .toList(growable: false);
    _visibleCache = result;
    return result;
  }

  int get totalCount => _entries.length;

  void setMinLevel(int level) {
    minLevel = level;
    _visibleCache = null;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    searchQuery = query;
    _searchQueryLower = query.toLowerCase();
    _visibleCache = null;
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    _visibleCache = null;
    notifyListeners();
  }

  /// Renders all buffered entries as plain text, ignoring level and search filters.
  String exportAll() {
    final buf = StringBuffer();
    for (final e in _entries) {
      final t = DateTime.fromMillisecondsSinceEpoch(millisOf(e.timeMillis));
      final level = (e.level >= 0 && e.level < kLevelNames.length)
          ? kLevelNames[e.level]
          : e.level.toString();
      buf.writeln(
        '${t.toIso8601String()}  ${level.padRight(5)}  ${e.target}  ${e.message}',
      );
    }
    return buf.toString();
  }

  // Coalesces dense log events into one rebuild per microtask.
  void _scheduleNotify() {
    _visibleCache = null;
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    Future.microtask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Global log singleton.
final logStore = LogStore();
