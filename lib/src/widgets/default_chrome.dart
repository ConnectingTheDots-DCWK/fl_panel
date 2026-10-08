import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../model/geometry.dart';
import '../model/tab.dart';
import 'chrome.dart';
import 'panel_theme.dart';

/// The built-in chrome: the three [PanelTabStyle]s, a header for single
/// panels, a hairline divider that lights up under the pointer, a shaded
/// drop preview.
class DefaultPanelChrome extends PanelChrome {
  const DefaultPanelChrome();

  @override
  Widget buildStrip(BuildContext context, StripScope scope) =>
      TabStrip(scope: scope);

  @override
  Widget buildHeader(BuildContext context, HeaderScope scope) =>
      PanelHeader(scope: scope);

  @override
  Widget buildDivider(BuildContext context, DividerScope scope) =>
      DividerHandle(scope: scope);

  @override
  Widget buildDropPreview(BuildContext context, PanelTheme theme) =>
      DecoratedBox(
        decoration: BoxDecoration(
          color: theme.dropPreviewColor,
          border: Border.all(color: theme.dropPreviewBorderColor!, width: 2),
        ),
      );
}

/// The strip above a tab group.
///
/// Chips share the width equally between `tabMinWidth` and `tabMaxWidth`;
/// past the point where they would have to shrink below the minimum the row
/// scrolls instead. The scroll is never a pointer drag — a drag on a strip
/// already means "move this tab" — so the wheel moves it, and so does a
/// reveal: activating a tab, or `PanelController.focus`, brings the chip into
/// view. Dragging the strip's background moves the whole group.
class TabStrip extends StatefulWidget {
  const TabStrip({super.key, required this.scope});

  final StripScope scope;

  @override
  State<TabStrip> createState() => _TabStripState();
}

class _TabStripState extends State<TabStrip> {
  int? _handledReveal;

  /// The shown tab as of the last layout, by id rather than by index: a
  /// reorder moves the active chip without changing which tab it is, and a
  /// strip that scrolled to it on every reorder would scroll mid-drag.
  String? _lastActive;

  /// The tab ids in the order last drawn. When the next build holds the same
  /// tabs in another order, the chips slide to their new slots.
  List<String> _lastOrder = const [];

  /// The width of every chip and the gap between them, as laid out last;
  /// what a reveal scrolls by.
  double _chipWidth = 0;
  double _gap = 0;
  double _viewport = 0;

  StripScope get scope => widget.scope;
  PanelTheme get theme => scope.theme;
  PanelTabStyleSpec get spec => theme.spec;

  @override
  Widget build(BuildContext context) {
    final group = scope.group;
    final style = theme.tabStyle;
    final trailing = scope.decorations.stripTrailing?.call(context, group);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) =>
          scope.callbacks.onDragLeafStart(group.id, d.globalPosition),
      onPanUpdate: (d) => scope.callbacks.onDragUpdate(d.globalPosition),
      onPanEnd: (_) => scope.callbacks.onDragEnd(),
      onPanCancel: scope.callbacks.onDragCancel,
      // A chip's own detector wins over this one for a click on a chip, so
      // this is the background only.
      onSecondaryTapUp: (d) =>
          scope.callbacks.onStripSecondaryTap(group.id, d.globalPosition),
      child: scope.stripSlot(
        Container(
          height: scope.theme.stripHeight,
          color: theme.stripColor,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The hairline between strip and content. Attached chips are
              // full height and the active one paints over it, which is what
              // joins that tab to its content; the blended floor has no line.
              if (style != PanelTabStyle.blended)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 1,
                  child: ColoredBox(color: theme.dividerColor!),
                ),
              Padding(
                padding: spec.inset,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: LayoutBuilder(builder: _buildChips)),
                    ?trailing,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChips(BuildContext context, BoxConstraints constraints) {
    final group = scope.group;
    final n = group.tabs.length;
    final width = constraints.maxWidth;
    _gap = spec.gap;
    _viewport = width;
    // An empty persistent group has no chips to size; the width still has
    // to be a number for the reveal arithmetic.
    final natural = n == 0 ? theme.tabMinWidth : (width - _gap * (n - 1)) / n;
    _chipWidth = natural.clamp(theme.tabMinWidth, theme.tabMaxWidth);
    _scheduleReveal();
    final order = [for (final tab in group.tabs) tab.id];
    // Only a pure reorder slides: a tab opened or closed changes every
    // chip's width as well as its slot, and the arithmetic below would
    // slide them from places they never were.
    final slide =
        order.length == _lastOrder.length &&
        order.toSet().containsAll(_lastOrder);
    _lastOrder = order;

    final chips = <Widget>[];
    for (var i = 0; i < n; i++) {
      final tab = group.tabs[i];
      final active = i == group.active;
      // A separator sits between two inactive neighbours only; beside the
      // active chip its own edge does the work.
      final nextActive = i + 1 == group.active;
      if (i > 0 && _gap > 0) chips.add(SizedBox(width: _gap));
      final Widget chip = TabChip(
        tab: tab,
        active: active,
        focused: scope.focused,
        separatorAfter: i < n - 1 && !active && !nextActive,
        title: scope.titleOf(tab),
        theme: theme,
        callbacks: scope.callbacks,
        decorations: scope.decorations,
      );
      chips.add(
        // Keyed by tab, so a reorder moves each chip's element — and the
        // pan recognizer of the chip being dragged — with its tab.
        _SlidingChip(
          key: ValueKey('fl_panel.chip.${tab.id}'),
          slot: i,
          step: _chipWidth + _gap,
          slide: slide,
          child: SizedBox(
            width: _chipWidth,
            child: scope.tabSlot(
              i,
              scope.decorations.wrapTab?.call(context, tab, chip) ?? chip,
            ),
          ),
        ),
      );
    }

    return Listener(
      onPointerSignal: _onWheel,
      child: SingleChildScrollView(
        controller: scope.scrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: chips,
        ),
      ),
    );
  }

  void _onWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final position = scope.scrollController.position;
    if (position.maxScrollExtent <= 0) return;
    // A vertical wheel over a horizontal strip scrolls it, as browsers do; a
    // trackpad's horizontal delta counts as itself.
    final delta = event.scrollDelta.dx != 0
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    position.jumpTo(
      (position.pixels + delta).clamp(0.0, position.maxScrollExtent),
    );
  }

  /// Brings a chip into view after this frame: the one a reveal asks for,
  /// or the newly active one. Done from layout because the offset depends on
  /// the chip width just computed.
  void _scheduleReveal() {
    final group = scope.group;
    final reveal = scope.reveal;
    int? index;
    if (reveal != null && reveal.nonce != _handledReveal) {
      _handledReveal = reveal.nonce;
      final i = group.indexOf(reveal.tabId);
      if (i >= 0) index = i;
    }
    final active = group.activeTab?.id;
    if (index == null && active != null && _lastActive != active) {
      index = group.active;
    }
    _lastActive = active;
    if (index == null) return;
    final target = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scope.scrollController.hasClients) return;
      final position = scope.scrollController.position;
      if (position.maxScrollExtent <= 0) return;
      final start = target * (_chipWidth + _gap);
      final end = start + _chipWidth;
      final current = position.pixels;
      double? to;
      if (start < current) {
        to = start;
      } else if (end > current + _viewport) {
        to = end - _viewport;
      }
      if (to == null) return;
      position.animateTo(
        to.clamp(0.0, position.maxScrollExtent),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }
}

/// A chip that slides to a new [slot] rather than jumping there.
///
/// Painted offset only: `transformHitTests` is off, so the drop hit-test
/// sees every chip at the slot it has already taken. Measured against where
/// the chips are drawn mid-slide, the slot under the pointer would move
/// under it and the order would oscillate.
class _SlidingChip extends StatefulWidget {
  const _SlidingChip({
    super.key,
    required this.slot,
    required this.step,
    required this.slide,
    required this.child,
  });

  final int slot;

  /// One chip and one gap: how far apart neighbouring slots are.
  final double step;
  final bool slide;
  final Widget child;

  @override
  State<_SlidingChip> createState() => _SlidingChipState();
}

class _SlidingChipState extends State<_SlidingChip>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
  );

  /// Where the slide starts, relative to the slot: the old slot, plus
  /// whatever was left of a slide still under way.
  double _from = 0;

  double get _offset => _from * (1 - Curves.easeOut.transform(_motion.value));

  @override
  void didUpdateWidget(_SlidingChip old) {
    super.didUpdateWidget(old);
    if (!widget.slide || old.slot == widget.slot) return;
    _from = (old.slot - widget.slot) * widget.step + _offset;
    _motion.forward(from: 0);
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  // Always a Transform, even at rest: a wrapper that came and went would
  // remount the chip, and with it the recognizer carrying the drag.
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _motion,
    builder: (context, child) => Transform.translate(
      offset: Offset(_offset, 0),
      transformHitTests: false,
      child: child,
    ),
    child: widget.child,
  );
}

class TabChip extends StatefulWidget {
  const TabChip({
    super.key,
    required this.tab,
    required this.active,
    required this.focused,
    required this.separatorAfter,
    required this.title,
    required this.theme,
    required this.callbacks,
    required this.decorations,
  });

  final PanelTab tab;
  final bool active;

  /// Whether the group is the window's focused one; the active chip of an
  /// unfocused group shows a muted accent.
  final bool focused;
  final bool separatorAfter;
  final String title;
  final PanelTheme theme;
  final ChromeCallbacks callbacks;
  final PanelDecorations decorations;

  @override
  State<TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<TabChip> {
  bool _hover = false;

  PanelTheme get theme => widget.theme;
  PanelTabStyleSpec get spec => theme.spec;

  @override
  Widget build(BuildContext context) {
    final callbacks = widget.callbacks;
    final tab = widget.tab;
    final leading = widget.decorations.tabLeading?.call(context, tab);
    final trailing = widget.decorations.tabTrailing?.call(context, tab);
    final label = Row(
      children: [
        if (leading != null) ...[leading, const SizedBox(width: 6)],
        Expanded(
          child: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: widget.active ? theme.activeTextStyle : theme.textStyle,
          ),
        ),
        if (trailing != null)
          trailing
        else if (widget.decorations.showCloseButtons && tab.closable)
          CloseGlyph(
            colour: theme.iconColor!,
            onTap: () => callbacks.onClose(tab.id),
          ),
      ],
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => callbacks.onActivate(tab.id),
        onTertiaryTapUp: (_) => callbacks.onClose(tab.id),
        onSecondaryTapUp: (d) =>
            callbacks.onTabSecondaryTap(tab.id, d.globalPosition),
        onPanStart: (d) => callbacks.onDragTabStart(tab.id, d.globalPosition),
        onPanUpdate: (d) => callbacks.onDragUpdate(d.globalPosition),
        onPanEnd: (_) => callbacks.onDragEnd(),
        onPanCancel: callbacks.onDragCancel,
        child: switch (theme.tabStyle) {
          PanelTabStyle.attached => _attached(label),
          PanelTabStyle.blended => _blended(label),
          PanelTabStyle.floating => _floating(label),
        },
      ),
    );
  }

  Color get _indicator =>
      widget.focused ? theme.indicatorColor! : theme.unfocusedIndicatorColor!;

  Color? get _fill => widget.active
      ? theme.activeTabColor
      : _hover
      ? theme.hoverTabColor
      : theme.tabColor;

  Widget _attached(Widget label) => Container(
    padding: const EdgeInsets.only(left: 12, right: 4),
    decoration: BoxDecoration(
      color: _fill,
      border: Border(
        right: BorderSide(color: theme.dividerColor!, width: 1),
        top: BorderSide(
          color: widget.active ? _indicator : Colors.transparent,
          width: spec.indicator,
        ),
      ),
    ),
    child: label,
  );

  Widget _blended(Widget label) => CustomPaint(
    painter: BlendedChipPainter(
      fill: widget.active
          ? theme.activeTabColor
          : (_hover ? theme.hoverTabColor : null),
      outline: widget.active ? _indicator : null,
      separator: widget.separatorAfter ? theme.dividerColor : null,
      radius: spec.radius,
      shoulder: spec.shoulder,
    ),
    child: Padding(
      padding: EdgeInsets.only(left: spec.shoulder + 8, right: spec.shoulder),
      child: label,
    ),
  );

  Widget _floating(Widget label) => Container(
    padding: const EdgeInsets.only(left: 10, right: 2),
    decoration: BoxDecoration(
      color: _fill,
      borderRadius: BorderRadius.circular(spec.radius),
      border: widget.active && widget.focused
          ? Border.all(color: _indicator, width: 1)
          : null,
    ),
    child: label,
  );
}

/// The Chrome shape: a chip whose sides flare out through a quarter circle
/// of [shoulder] to meet the strip floor, with [radius] at the top corners.
/// The bottom edge is left open so an active chip and the content below it
/// are one surface.
class BlendedChipPainter extends CustomPainter {
  const BlendedChipPainter({
    required this.fill,
    required this.outline,
    required this.separator,
    required this.radius,
    required this.shoulder,
  });

  final Color? fill;
  final Color? outline;
  final Color? separator;
  final double radius;
  final double shoulder;

  @override
  void paint(Canvas canvas, Size size) {
    if (fill != null) {
      final path = shape(size);
      canvas.drawPath(path, Paint()..color = fill!);
      if (outline != null) {
        canvas.drawPath(
          path,
          Paint()
            ..color = outline!
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }
    if (separator != null) {
      final inset = size.height * 0.25;
      canvas.drawLine(
        Offset(size.width - 0.5, inset),
        Offset(size.width - 0.5, size.height - inset),
        Paint()
          ..color = separator!
          ..strokeWidth = 1,
      );
    }
  }

  /// The open path, bottom-left to bottom-right, in screen coordinates
  /// (angles clockwise from +x, +y down).
  Path shape(Size size) {
    final w = size.width;
    final h = size.height;
    final s = math.min(shoulder, h / 2);
    final r = math.min(radius, (w - 2 * s) / 2);
    return Path()
      ..moveTo(0, h)
      // Left shoulder: the lower-right quarter of a circle centred on the
      // floor at x = 0, so the wall leaves the floor tangentially.
      ..arcTo(
        Rect.fromCircle(center: Offset(0, h - s), radius: s),
        math.pi / 2,
        -math.pi / 2,
        false,
      )
      ..lineTo(s, r)
      ..arcTo(
        Rect.fromCircle(center: Offset(s + r, r), radius: r),
        math.pi,
        math.pi / 2,
        false,
      )
      ..lineTo(w - s - r, 0)
      ..arcTo(
        Rect.fromCircle(center: Offset(w - s - r, r), radius: r),
        -math.pi / 2,
        math.pi / 2,
        false,
      )
      ..lineTo(w - s, h - s)
      ..arcTo(
        Rect.fromCircle(center: Offset(w, h - s), radius: s),
        math.pi,
        -math.pi / 2,
        false,
      );
  }

  @override
  bool shouldRepaint(BlendedChipPainter old) =>
      old.fill != fill ||
      old.outline != outline ||
      old.separator != separator ||
      old.radius != radius ||
      old.shoulder != shoulder;
}

/// The header above a single panel: the title, whatever the host adds, a
/// close glyph, and the handle by which the panel is dragged.
class PanelHeader extends StatelessWidget {
  const PanelHeader({super.key, required this.scope});

  final HeaderScope scope;

  @override
  Widget build(BuildContext context) {
    final theme = scope.theme;
    final panel = scope.panel;
    final trailing = scope.decorations.headerTrailing?.call(context, panel);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) =>
          scope.callbacks.onDragLeafStart(panel.id, d.globalPosition),
      onPanUpdate: (d) => scope.callbacks.onDragUpdate(d.globalPosition),
      onPanEnd: (_) => scope.callbacks.onDragEnd(),
      onPanCancel: scope.callbacks.onDragCancel,
      onSecondaryTapUp: (d) =>
          scope.callbacks.onHeaderSecondaryTap(panel.id, d.globalPosition),
      child: Container(
        height: theme.headerHeight,
        padding: const EdgeInsets.only(left: 12, right: 4),
        decoration: BoxDecoration(
          color: theme.headerColor,
          border: Border(
            bottom: BorderSide(
              color: scope.focused
                  ? theme.indicatorColor!
                  : theme.dividerColor!,
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                scope.titleOf(panel.tab),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: theme.activeTextStyle,
              ),
            ),
            ?trailing,
            if (scope.decorations.showCloseButtons && panel.tab.closable)
              CloseGlyph(
                colour: theme.iconColor!,
                onTap: () => scope.callbacks.onCloseLeaf(panel.id),
              ),
          ],
        ),
      ),
    );
  }
}

/// The × on a chip or a header. Not an `InkWell`: the chrome must not
/// require a `Material` ancestor a host that is not Material would lack.
class CloseGlyph extends StatelessWidget {
  const CloseGlyph({super.key, required this.colour, required this.onTap});

  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(Icons.close, size: 14, color: colour),
        ),
      ),
    );
  }
}

/// The handle between two split children.
class DividerHandle extends StatefulWidget {
  const DividerHandle({super.key, required this.scope});

  final DividerScope scope;

  @override
  State<DividerHandle> createState() => _DividerHandleState();
}

class _DividerHandleState extends State<DividerHandle> {
  bool _hover = false;
  bool _dragging = false;

  bool get _horizontal => widget.scope.geometry.axis == PanelAxis.horizontal;

  @override
  Widget build(BuildContext context) {
    final theme = widget.scope.theme;
    final lit = _hover || _dragging;
    final horizontal = _horizontal;
    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Deliver the slop distance too: a divider that lags the pointer by
        // twenty pixels on every grab feels broken.
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragUpdate: horizontal
            ? (d) => widget.scope.onDrag(d.delta.dx)
            : null,
        onVerticalDragUpdate: horizontal
            ? null
            : (d) => widget.scope.onDrag(d.delta.dy),
        onHorizontalDragStart: horizontal
            ? (_) => setState(() => _dragging = true)
            : null,
        onVerticalDragStart: horizontal
            ? null
            : (_) => setState(() => _dragging = true),
        onHorizontalDragEnd: horizontal ? (_) => _settle() : null,
        onVerticalDragEnd: horizontal ? null : (_) => _settle(),
        onHorizontalDragCancel: horizontal ? _settle : null,
        onVerticalDragCancel: horizontal ? null : _settle,
        onSecondaryTapUp: (d) => widget.scope.onSecondaryTap(d.globalPosition),
        child: Center(
          child: Container(
            width: horizontal ? 1 : null,
            height: horizontal ? null : 1,
            color: lit ? theme.dividerHoverColor : theme.dividerColor,
          ),
        ),
      ),
    );
  }

  void _settle() {
    if (mounted) setState(() => _dragging = false);
    widget.scope.onSettle();
  }
}
