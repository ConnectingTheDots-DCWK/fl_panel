import 'package:flutter/widgets.dart';

import '../controller/panel_controller.dart';
import '../layout/solver.dart';
import '../model/node.dart';
import '../model/tab.dart';
import 'panel_theme.dart';

/// What a chip in a strip is, for the drop hit-test. The host walks the hit
/// path for these and turns "over the left half of the third chip of group
/// G" into an insertion index. Custom chrome never constructs one: it wraps
/// each chip with [StripScope.tabSlot], which does.
final class TabSlot {
  const TabSlot(this.leafId, this.index);
  final String leafId;
  final int index;
}

/// The strip's background past the last chip: a drop here appends. Applied by
/// [StripScope.stripSlot].
final class StripSlot {
  const StripSlot(this.leafId, this.count);
  final String leafId;
  final int count;
}

/// The verbs the chrome hands back to the host. One object rather than a
/// handful of closures so a strip's inputs compare cheaply; the host builds
/// it once per (controller, window).
final class ChromeCallbacks {
  const ChromeCallbacks({
    required this.onActivate,
    required this.onClose,
    required this.onCloseLeaf,
    required this.onFocusLeaf,
    required this.onDragTabStart,
    required this.onDragLeafStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
    required this.onTabSecondaryTap,
    required this.onStripSecondaryTap,
    required this.onHeaderSecondaryTap,
  });

  final void Function(String tabId) onActivate;
  final void Function(String tabId) onClose;
  final void Function(String leafId) onCloseLeaf;
  final void Function(String leafId) onFocusLeaf;
  final void Function(String tabId, Offset global) onDragTabStart;
  final void Function(String leafId, Offset global) onDragLeafStart;
  final void Function(Offset global) onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDragCancel;
  final void Function(String tabId, Offset global) onTabSecondaryTap;

  /// A right click on a strip's background or a header, past the chips.
  final void Function(String leafId, Offset global) onStripSecondaryTap;
  final void Function(String leafId, Offset global) onHeaderSecondaryTap;
}

/// The hooks an application hangs on the default chrome without replacing
/// it: an icon before a title, a dirty dot instead of the close glyph, a
/// button at the end of a strip. A right click is `PanelHost.contextMenus`'s.
final class PanelDecorations {
  const PanelDecorations({
    this.tabLeading,
    this.tabTrailing,
    this.wrapTab,
    this.stripTrailing,
    this.headerTrailing,
    this.showCloseButtons = true,
  });

  /// Before a tab's title.
  final Widget? Function(BuildContext context, PanelTab tab)? tabLeading;

  /// After a tab's title. When it returns a widget, that takes the close
  /// glyph's place — the way an unsaved dot does — and the tab still closes
  /// by middle click or by the controller.
  final Widget? Function(BuildContext context, PanelTab tab)? tabTrailing;

  /// Around a whole chip — a tooltip, a spotlight target, a badge overlay.
  /// Inside the drop slot, so the chip stays a drop target whatever wraps it.
  final Widget Function(BuildContext context, PanelTab tab, Widget chip)?
  wrapTab;

  /// At the end of a strip, outside the scrolling chips.
  final Widget? Function(BuildContext context, TabGroup group)? stripTrailing;

  /// At the end of a single panel's header, before the close glyph.
  final Widget? Function(BuildContext context, SinglePanel panel)?
  headerTrailing;

  final bool showCloseButtons;
}

/// What every piece of chrome is given.
sealed class ChromeScope {
  const ChromeScope({
    required this.windowId,
    required this.theme,
    required this.callbacks,
    required this.decorations,
    required this.titleOf,
    required this.focused,
  });

  final String windowId;

  /// Resolved: every colour filled in.
  final PanelTheme theme;
  final ChromeCallbacks callbacks;
  final PanelDecorations decorations;
  final String Function(PanelTab tab) titleOf;

  /// Whether this leaf is the window's focused one.
  final bool focused;
}

/// What a strip is given. [tabSlot] and [stripSlot] are the contract: chips
/// wrapped in them are drop targets, chips not wrapped in them are not.
final class StripScope extends ChromeScope {
  const StripScope({
    required super.windowId,
    required super.theme,
    required super.callbacks,
    required super.decorations,
    required super.titleOf,
    required super.focused,
    required this.group,
    required this.scrollController,
    required this.reveal,
  });

  final TabGroup group;

  /// Owned by the host and kept across rebuilds, so a strip that scrolls
  /// keeps its place when the tree changes under it.
  final ScrollController scrollController;

  /// A request to bring one of this group's tabs into view, or null. A strip
  /// that scrolls answers it; one that does not may ignore it.
  final RevealRequest? reveal;

  /// Wraps chip [index] so the drop hit-test can find it.
  Widget tabSlot(int index, Widget child) => MetaData(
    metaData: TabSlot(group.id, index),
    behavior: HitTestBehavior.opaque,
    child: child,
  );

  /// Wraps the strip's background so a drop past the last chip appends.
  Widget stripSlot(Widget child) => MetaData(
    metaData: StripSlot(group.id, group.tabs.length),
    behavior: HitTestBehavior.opaque,
    child: child,
  );
}

final class HeaderScope extends ChromeScope {
  const HeaderScope({
    required super.windowId,
    required super.theme,
    required super.callbacks,
    required super.decorations,
    required super.titleOf,
    required super.focused,
    required this.panel,
  });

  final SinglePanel panel;
}

final class DividerScope {
  const DividerScope({
    required this.theme,
    required this.geometry,
    required this.onDrag,
    required this.onSettle,
    required this.onSecondaryTap,
  });

  final PanelTheme theme;
  final DividerGeometry geometry;

  /// Pixels along the split's axis.
  final void Function(double delta) onDrag;
  final VoidCallback onSettle;

  /// A right click on the divider.
  final void Function(Offset global) onSecondaryTap;
}

/// Everything the host draws that is not content: strips, headers, dividers,
/// the drop preview. `DefaultPanelChrome` is the three built-in tab styles; a
/// host with its own look subclasses this and keeps docking for free, as long
/// as its chips go through [StripScope.tabSlot].
abstract class PanelChrome {
  const PanelChrome();

  /// How tall a group's strip is; the content starts below it.
  double stripHeight(PanelTheme theme, TabGroup group) => theme.stripHeight;

  /// How tall a single panel's header is.
  double headerHeight(PanelTheme theme, SinglePanel panel) =>
      theme.headerHeight;

  Widget buildStrip(BuildContext context, StripScope scope);
  Widget buildHeader(BuildContext context, HeaderScope scope);
  Widget buildDivider(BuildContext context, DividerScope scope);
  Widget buildDropPreview(BuildContext context, PanelTheme theme);
}
