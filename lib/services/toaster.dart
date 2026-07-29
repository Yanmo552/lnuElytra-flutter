import 'package:flutter/foundation.dart';

import 'log_store.dart';

/// Visual style of a toast, mapped to color and icon in the UI layer.
enum ToastType { info, success, error }

/// Data for a single toast: id (for key and removal), text content, style, and
/// display duration before auto-dismiss.
class ToastData {
  ToastData(this.id, this.message, this.type, this.duration);

  final int id;
  final String message;
  final ToastType type;
  final Duration duration;
}

/// Queue-free toast notifier.
///
/// Unlike [ScaffoldMessenger] (which shows one snackbar at a time; new ones must wait),
/// toasts here appear immediately and *stack*. Suited for rapid feedback during course grabbing,
/// avoiding a series of results queued behind a 4-second delay.
///
/// Each toast is also written to [logStore] at the corresponding level —
/// info/success → INFO, error → ERROR — so nothing is lost after the toast disappears.
///
/// Driven from anywhere via the [toaster] singleton; [ToastOverlay] (mounted once in `MyApp`)
/// handles rendering. Call sites need no [BuildContext].
class Toaster extends ChangeNotifier {
  final List<ToastData> _toasts = [];
  List<ToastData>? _toastsCache;
  int _seq = 0;

  /// Maximum concurrent toasts; the oldest is dropped when exceeded, preventing spam.
  static const int maxVisible = 4;

  static const Duration _defaultDuration = Duration(milliseconds: 1800);
  static const Duration _errorDuration = Duration(milliseconds: 2800);

  List<ToastData> get toasts => _toastsCache ??= List.unmodifiable(_toasts);

  /// Shows a toast. Returns immediately — no blocking, no queuing.
  /// Also writes to [logStore] at the corresponding level.
  void show(
    String message, {
    ToastType type = ToastType.info,
    Duration? duration,
  }) {
    switch (type) {
      case ToastType.error:
        logStore.error(message, target: 'toast');
      case ToastType.success:
      case ToastType.info:
        logStore.info(message, target: 'toast');
    }
    _toasts.add(ToastData(_seq++, message, type, duration ?? _defaultDuration));
    if (_toasts.length > maxVisible) _toasts.removeAt(0);
    _toastsCache = null;
    notifyListeners();
  }

  void info(String message) => show(message);
  void success(String message) => show(message, type: ToastType.success);
  void error(String message) =>
      show(message, type: ToastType.error, duration: _errorDuration);

  /// Called by a toast entry after its exit animation completes,
  /// when the entry is no longer visible, to safely remove its data.
  void remove(int id) {
    _toasts.removeWhere((t) => t.id == id);
    _toastsCache = null;
    notifyListeners();
  }
}

/// Global toast singleton.
final toaster = Toaster();
