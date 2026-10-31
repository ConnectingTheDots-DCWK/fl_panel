import 'dart:async';

import 'package:flutter/gestures.dart' show PointerEnterEvent, PointerExitEvent;
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/widgets.dart';

import 'chrome.dart';

/// A chip's or a header's title: ellipsised, and — when the host passed a
/// [PanelTitleScroll] — scrolled to show the rest while the pointer rests on
/// it.
///
/// **Nothing is paid at rest.** An ordinary `Text` under a `MouseRegion`; the
/// title is shaped once, when the delay runs out, to learn whether it
/// overflows at all, and the controller is made on first use. With no
/// [scroll] there is no region either, and the chip is what it always was.
///
/// Leftward in a left-to-right line and rightward in the other, so the end of
/// the title is what comes into view; leaving puts it back at rest at once,
/// since a title easing home under a pointer that has gone is motion nobody
/// is watching.
class ScrollingTitle extends StatefulWidget {
  const ScrollingTitle(
    this.text, {
    super.key,
    this.style,
    required this.scroll,
  });

  final String text;
  final TextStyle? style;
  final PanelTitleScroll? scroll;

  @override
  State<ScrollingTitle> createState() => _ScrollingTitleState();
}

class _ScrollingTitleState extends State<ScrollingTitle>
    with SingleTickerProviderStateMixin {
  Timer? _wait;
  AnimationController? _controller;
  Animation<double>? _travel;

  /// How far the text runs past its box; zero at rest.
  double _overflow = 0;

  @override
  void didUpdateWidget(ScrollingTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A rename under the pointer: the measurement is of the old name.
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.scroll != widget.scroll) {
      _rest();
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _enter(PointerEnterEvent _) {
    _wait?.cancel();
    if (widget.scroll == null) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    _wait = Timer(widget.scroll!.delay, _start);
  }

  void _start() {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final painter = TextPainter(
      text: TextSpan(
        text: widget.text,
        style: DefaultTextStyle.of(context).style.merge(widget.style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final overflow = painter.width - box.size.width;
    painter.dispose();
    if (overflow < 1) return;

    final out = overflow / widget.scroll!.speed;
    final back = out / 3;
    final hold = widget.scroll!.hold.inMilliseconds / 1000;
    final controller = _controller ??= AnimationController(vsync: this);
    controller.duration = Duration(
      milliseconds: ((out + back + hold * 2) * 1000).round(),
    );
    _travel = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(tween: Tween<double>(begin: 0, end: 1), weight: out),
      TweenSequenceItem(tween: ConstantTween<double>(1), weight: hold),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1,
          end: 0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: back,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(0), weight: hold),
    ]).animate(controller);
    setState(() => _overflow = overflow);
    controller.repeat();
  }

  void _exit(PointerExitEvent _) => _rest();

  void _rest() {
    _wait?.cancel();
    _wait = null;
    _controller?.stop();
    _controller?.value = 0;
    if (_overflow != 0 && mounted) setState(() => _overflow = 0);
  }

  @override
  Widget build(BuildContext context) {
    final travel = _travel;
    final moving = _overflow > 0 && travel != null;
    Widget label = Text(
      widget.text,
      style: widget.style,
      maxLines: 1,
      softWrap: false,
      overflow: moving ? TextOverflow.visible : TextOverflow.ellipsis,
    );
    if (moving) {
      // Leftward in a left-to-right line and rightward in the other, so the
      // end of the name is what comes into view either way.
      final sign = Directionality.of(context) == TextDirection.rtl ? 1 : -1;
      label = ClipRect(
        child: OverflowBox(
          alignment: AlignmentDirectional.centerStart,
          maxWidth: double.infinity,
          fit: OverflowBoxFit.deferToChild,
          child: AnimatedBuilder(
            animation: travel,
            builder: (_, child) => Transform.translate(
              offset: Offset(sign * _overflow * travel.value, 0),
              child: child,
            ),
            child: label,
          ),
        ),
      );
    }
    if (widget.scroll == null) return label;
    return MouseRegion(onEnter: _enter, onExit: _exit, child: label);
  }
}
