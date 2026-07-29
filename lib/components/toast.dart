import 'dart:async';

import 'package:flutter/material.dart';

import '../services/toaster.dart';

/// Floating Toast overlay. Mount once at the top of the widget tree (see `MyApp`);
/// listens to [toaster] and stacks Toasts below the top edge, above all routes
/// and dialogs.
class ToastOverlay extends StatelessWidget {
  const ToastOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: AnimatedBuilder(
                animation: toaster,
                builder: (context, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final t in toaster.toasts)
                      _ToastItem(key: ValueKey(t.id), data: t),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A single Toast. Manages its own lifecycle: plays an enter animation on mount,
/// auto-dismisses after [ToastData.duration], and removes data only after the
/// exit animation completes — so the list reflows smoothly when shrinking.
class _ToastItem extends StatefulWidget {
  const _ToastItem({super.key, required this.data});

  final ToastData data;

  @override
  State<_ToastItem> createState() => _ToastItemState();
}

class _ToastItemState extends State<_ToastItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  late final CurvedAnimation _curve;
  late final Animation<Offset> _slide;
  Timer? _timer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _curve = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _slide = Tween(
      begin: const Offset(0, -0.25),
      end: Offset.zero,
    ).animate(_curve);
    _ctrl.forward();
    _timer = Timer(widget.data.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (_leaving) return;
    _leaving = true;
    _timer?.cancel();
    if (mounted) await _ctrl.reverse();
    toaster.remove(widget.data.id);
  }

  @override
  void dispose() {
    _curve.dispose();
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _curve,
      child: FadeTransition(
        opacity: _curve,
        child: SlideTransition(
          position: _slide,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _bubble(context),
          ),
        ),
      ),
    );
  }

  Widget _bubble(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg, IconData icon) = switch (widget.data.type) {
      ToastType.success => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.check_circle_outline,
      ),
      ToastType.error => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.error_outline,
      ),
      ToastType.info => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        Icons.info_outline,
      ),
    };
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Material(
          color: bg,
          elevation: 3,
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _dismiss,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: fg),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      widget.data.message,
                      style: TextStyle(color: fg, fontSize: 13.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
