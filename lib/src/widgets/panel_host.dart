import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../controller/panel_controller.dart';
import '../layout/dock_resolver.dart';
import '../layout/solver.dart';
import '../model/dock.dart';
import '../model/geometry.dart';
import '../model/node.dart';
import '../model/tab.dart';
import 'chrome.dart';
import 'default_chrome.dart';
import 'menus/panel_menu_host.dart';
import 'menus/panel_menus.dart';
import 'panel_localizations.dart';
import 'panel_theme.dart';

/// Builds the widget shown for a tab. Called for every tab in the window, not
/// only the active ones; keyed on the tab's id so its state survives a move.
typedef PanelContentBuilder =
    Widget Function(BuildContext context, PanelTab tab);

/// One leaf of a window shown over the whole of its host, and nothing else:
/// an editor's zen mode, a maximised panel.
///
/// A way of *showing* the layout, never an edit to it. The tree is not
/// touched, so nothing is saved and nothing has to be put back: every other
/// tab stays built, offstage, and leaving solo finds each one as it was.
/// Hand [PanelHost.solo] the focused leaf and solo follows the user — a
/// `focus` on a tab in another leaf shows that leaf instead.
@immutable
final class PanelSolo {
  const PanelSolo(this.leafId, {this.chrome = true});

  /// The leaf shown. One the window does not hold — a leaf closed a moment
  /// ago — shows the layout as usual rather than nothing.
  final String leafId;

  /// Whether the leaf keeps its strip or header. Without it the content has
  /// the whole host, and the tabs are reached by whatever the host's app
  /// binds to `nextTab`, `previousTab` and `focus`.
  final bool chrome;

  @override
  bool operator ==(Object other) =>
      other is PanelSolo && other.leafId == leafId && other.chrome == chrome;

  @override
  int get hashCode => Object.hash(leafId, chrome);
}

/// Shows one window of a [PanelController]'s layout.
///
/// The host is a view: it solves the tree for its constraints, positions one
/// content child per tab, draws the chrome over them through a [PanelChrome],
/// and turns pointer gestures into controller verbs. It never reparents
/// content. Every tab is a `Positioned` child of one `Stack`, keyed on the
/// tab's id, and a move changes its rectangle and nothing else — which is
/// what keeps a text field's selection when the tab it is in lands in another
/// group. The classic alternative, a widget per leaf holding its tabs'
/// widgets, rebuilds content from scratch on every move unless every piece
/// wears a `GlobalKey`, and `GlobalKey` reparenting has sharp edges of its own.
///
/// **Several hosts may share one controller**, one per window, and a tab or
/// a group dragged out of one host can be dropped into another — a drawer
/// into the dock, one monitor's window into the next. The drop goes to the
/// topmost host under the pointer; [DockPolicy.canMoveBetween] may refuse it.
/// Content keeps its state across that move too: the one move a `Stack`
/// cannot express is the one place a `GlobalKey` is used, shared by every
/// host of the controller. Two rules keep that key from ever being built
/// twice: **a tab is in one place only** (the controller refuses a workspace
/// that breaks this), and **a window is shown by one host at a time** — a
/// second mounted host for the same window of the same controller is
/// reported as an error.
///
/// The drag belongs to the host it started in, so that host must stay
/// mounted until the drop: a drawer that is dragged out of should slide away
/// or stop taking pointers, not be removed. A source host that is disposed
/// mid-drag cancels the drag.
class PanelHost extends StatefulWidget {
  const PanelHost({
    super.key,
    required this.controller,
    required this.windowId,
    required this.contentBuilder,
    this.titleOf = defaultTitle,
    this.theme = const PanelTheme(),
    this.tabStyleOf,
    this.chrome = const DefaultPanelChrome(),
    this.decorations = const PanelDecorations(),
    this.emptyBuilder,
    this.emptyLeafBuilder,
    this.contextMenus = const PanelMenus(),
    this.solo,
  });

  final PanelController controller;

  /// Which of the controller's windows this host shows.
  final String windowId;
  final PanelContentBuilder contentBuilder;

  /// The text on a tab or header. By default the tab's `title` metadata,
  /// falling back to its content id.
  final String Function(PanelTab tab) titleOf;
  final PanelTheme theme;

  /// A tab style for one group, overriding the theme's; null keeps the
  /// theme's. Lets a window mix styles — attached tool panels beside blended
  /// editors.
  final PanelTabStyle? Function(TabGroup group)? tabStyleOf;

  /// What draws strips, headers, dividers and the drop preview.
  final PanelChrome chrome;
  final PanelDecorations decorations;

  /// What fills the host when the window has no tree.
  final WidgetBuilder? emptyBuilder;

  /// What fills a persistent group that has no tabs — an IDE's "nothing
  /// open" watermark. Its strip is still drawn above, so a tab can be
  /// dropped in.
  final Widget Function(BuildContext context, TabGroup group)? emptyLeafBuilder;

  /// The right-click menus on chips, strips, headers and dividers, or null
  /// for none. See [PanelMenus] for what they offer and how to add to it.
  final PanelMenus? contextMenus;

  /// One leaf over the whole host, or null for the layout as it is. No other
  /// leaf's chrome and no divider is drawn while it is set, and the host
  /// takes no drop: there is nowhere to show where one would land.
  final PanelSolo? solo;

  static String defaultTitle(PanelTab tab) =>
      tab.metadataValue<String>('title') ?? tab.contentId;

  @override
  State<PanelHost> createState() => _PanelHostState();
}

class _PanelHostState extends State<PanelHost> {
  /// The layout the last frame was drawn from: what a drop hit-test measures
  /// against, and whose bounds a divider drag is solved in.
  LayoutResult _layout = const LayoutResult(
    bounds: PanelRect.zero(),
    rects: {},
    dividers: [],
  );
  late ChromeCallbacks _callbacks;

  /// One per group, kept across rebuilds so a scrolled strip stays scrolled;
  /// pruned when the group is gone.
  final _stripScroll = <String, ScrollController>{};

  /// One per tab, so `focus(keyboard: true)` can hand the content the
  /// keyboard without knowing what is inside it.
  final _focusScopes = <String, FocusScopeNode>{};
  int? _handledReveal;

  /// The reorder the strips were last drawn with — what a strip hit is
  /// measured against, since a strip being reordered shows its chips in the
  /// order the drop would leave them, not the order the tree holds.
  _Reorder? _shownReorder;

  final _menuController = MenuController();
  final _menuKey = GlobalKey<PanelMenuHostState>();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _callbacks = _makeCallbacks();
    _register(widget.controller, widget.windowId);
  }

  @override
  void didUpdateWidget(PanelHost old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
    if (old.windowId != widget.windowId ||
        old.controller != widget.controller) {
      _unregister(old.controller, old.windowId);
      _register(widget.controller, widget.windowId);
      _callbacks = _makeCallbacks();
    }
  }

  @override
  void dispose() {
    _cancelOrphanedDrag();
    _unregister(widget.controller, widget.windowId);
    widget.controller.removeListener(_onChanged);
    for (final controller in _stripScroll.values) {
      controller.dispose();
    }
    for (final node in _focusScopes.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// A drag this host started cannot outlive it: the recognizer carrying it
  /// is disposed with the chrome and reports neither an end nor a cancel,
  /// so the drop would stay shaded with nothing left to finish it. Cancelled
  /// after the frame, because the tree is locked while it is torn down, and
  /// only if it is still the same drag.
  void _cancelOrphanedDrag() {
    final drag = _controller.drag;
    if (drag == null || drag.windowId != widget.windowId) return;
    final controller = _controller;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final now = controller.drag;
      if (now != null &&
          now.windowId == drag.windowId &&
          now.source == drag.source) {
        controller.cancelDrag();
      }
    });
  }

  void _onChanged() => setState(() {});

  PanelController get _controller => widget.controller;
  LayoutNode? get _root => _controller.rootOf(widget.windowId);

  // The callbacks are built once per (controller, window) so that the chrome
  // widgets see equal inputs across frames; a closure rebuilt per build is
  // the one input Flutter cannot compare.
  ChromeCallbacks _makeCallbacks() => ChromeCallbacks(
    onActivate: _controller.activate,
    onClose: _controller.close,
    onCloseLeaf: (leafId) => _controller.closeLeaf(widget.windowId, leafId),
    onFocusLeaf: (leafId) => _controller.focusLeaf(widget.windowId, leafId),
    onDragTabStart: (tabId, global) {
      _controller.beginDrag(widget.windowId, DockSource.tab(tabId));
      _track(global);
    },
    onDragLeafStart: (leafId, global) {
      _controller.beginDrag(widget.windowId, DockSource.leaf(leafId));
      _track(global);
    },
    onDragUpdate: _track,
    onDragEnd: _controller.commitDrag,
    onDragCancel: _controller.cancelDrag,
    onTabSecondaryTap: (tabId, global) {
      final tab = _controller.tab(tabId);
      if (tab == null) return;
      final leaf = _root?.leafOf(tabId);
      if (leaf != null) _openMenu(PanelMenuTabTarget(tab, leaf), global);
    },
    onStripSecondaryTap: (leafId, global) {
      final leaf = _root?.find(leafId);
      if (leaf is TabGroup) _openMenu(PanelMenuStripTarget(leaf), global);
    },
    onHeaderSecondaryTap: (leafId, global) {
      final leaf = _root?.find(leafId);
      if (leaf is SinglePanel) _openMenu(PanelMenuHeaderTarget(leaf), global);
    },
  );

  /// Opens the menu for [target] at [global], in the host's own space.
  void _openMenu(PanelMenuTarget target, Offset global) {
    final menus = widget.contextMenus;
    final box = context.findRenderObject();
    if (menus == null || box is! RenderBox || !box.hasSize) return;
    final entries = menus.entriesFor(
      PanelMenuRequest(
        controller: _controller,
        windowId: widget.windowId,
        target: target,
        globalPosition: global,
        localizations: PanelLocalizations.of(context),
      ),
    );
    _menuKey.currentState?.open(entries, box.globalToLocal(global));
  }

  /// Tells the controller what the drag is over now, in whichever host of
  /// this controller is topmost at [global] — this one or another.
  void _track(Offset global) {
    final (host, hit) = _hitAt(global);
    _controller.updateDrag(
      hit,
      host?._layout ?? _layout,
      windowId: host?.widget.windowId,
    );
  }

  /// The topmost host of this controller at [global], and what in it is
  /// under the pointer, for the resolver.
  ///
  /// One hit test of the whole view answers both. Every host wears a
  /// [_HostSlot]; the first one on the path is the host drawn on top at that
  /// point, so a drawer over the dock takes the drop where it covers it, a
  /// host nested in another's tab takes it over itself, and a host that is
  /// `IgnorePointer` or offstage is passed over. Strips are found by the
  /// `TabSlot`/`StripSlot` metadata the chrome wears — the only way to know
  /// where one chip ends and the next begins without measuring text here —
  /// and count only when they come before that host's slot, which is what
  /// makes them its own. Everything else is geometry: the leaf whose solved
  /// rectangle holds the point.
  (_PanelHostState?, DockHit) _hitAt(Offset global) {
    final result = HitTestResult();
    RendererBinding.instance.hitTestInView(
      result,
      global,
      View.of(context).viewId,
    );
    DockHit? strip;
    for (final entry in result.path) {
      final target = entry.target;
      if (target is! RenderMetaData) continue;
      final meta = target.metaData;
      if (strip == null && meta is TabSlot && entry is BoxHitTestEntry) {
        final before = entry.localPosition.dx < target.size.width / 2;
        strip = DockHit.strip(
          meta.leafId,
          before ? meta.index : meta.index + 1,
        );
      } else if (strip == null && meta is StripSlot) {
        strip = DockHit.strip(meta.leafId, meta.count);
      } else if (meta is _HostSlot) {
        final host = meta.state;
        if (!host.mounted ||
            host.widget.controller != _controller ||
            host._soloLeaf != null) {
          return (null, const DockHit.none());
        }
        return (host, host._unshift(strip) ?? host._geometryAt(global));
      }
    }
    return (null, const DockHit.none());
  }

  /// A strip hit on chips this host drew in reordered form, turned back into
  /// the index the tree means: a slot counted with the dragged tab where it
  /// still sits. The dragged chip is drawn at its new slot, so either half
  /// of it means "here", which is what keeps the order from flickering as
  /// the pointer crosses it.
  DockHit? _unshift(DockHit? hit) {
    final reorder = _shownReorder;
    if (hit is! DockStripHit || reorder == null) return hit;
    if (hit.leafId != reorder.group.id) return hit;
    // Where among the other tabs the pointer is, then that position counted
    // with the dragged tab still in its old place.
    final among = hit.index > reorder.shown ? hit.index - 1 : hit.index;
    return DockHit.strip(hit.leafId, among < reorder.from ? among : among + 1);
  }

  /// The drag in progress as a reorder of one of this window's strips, or
  /// null: a tab over its own strip, at a slot that changes something. The
  /// candidate already holds the tree after the drop, so the strip is drawn
  /// from it — the preview is the chips themselves.
  _Reorder? _reorderIn(LayoutNode root) {
    final drag = _controller.drag;
    final candidate = drag?.candidate;
    if (drag == null ||
        candidate == null ||
        candidate.crossesWindows ||
        drag.windowId != widget.windowId ||
        drag.targetWindowId != widget.windowId) {
      return null;
    }
    final source = drag.source;
    final target = candidate.target;
    if (source is! DockTabSource || target is! DockJoin) return null;
    if (target.index == null) return null;
    final leaf = root.leafOf(source.tabId);
    if (leaf is! TabGroup || leaf.id != target.leafId) return null;
    final shown = candidate.result.find(leaf.id);
    if (shown is! TabGroup) return null;
    return _Reorder(
      group: shown,
      from: leaf.indexOf(source.tabId),
      shown: shown.indexOf(source.tabId),
    );
  }

  /// The leaf of this host under [global], by geometry. A window with no
  /// tree is one target with no leaves in it.
  DockHit _geometryAt(Offset global) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return const DockHit.none();
    final local = box.globalToLocal(global);
    final root = _root;
    if (root == null) return DockHit.leaf('', local.dx, local.dy);
    final leaf = _layout.leafAt(root, local.dx, local.dy);
    if (leaf == null) return const DockHit.none();
    return DockHit.leaf(leaf.id, local.dx, local.dy);
  }

  /// The leaf [PanelHost.solo] names, if this window holds it.
  LeafNode? get _soloLeaf {
    final solo = widget.solo;
    if (solo == null) return null;
    final node = _root?.find(solo.leafId);
    return node is LeafNode ? node : null;
  }

  ScrollController _scrollFor(String leafId) =>
      _stripScroll.putIfAbsent(leafId, ScrollController.new);

  FocusScopeNode _focusFor(String tabId) => _focusScopes.putIfAbsent(
    tabId,
    () => FocusScopeNode(debugLabel: 'fl_panel.tab.$tabId'),
  );

  void _prune(LayoutNode root) {
    final leafIds = {for (final leaf in root.leaves) leaf.id};
    _stripScroll.removeWhere((id, controller) {
      if (leafIds.contains(id)) return false;
      controller.dispose();
      return true;
    });
    final tabIds = {for (final tab in root.tabs) tab.id};
    _focusScopes.removeWhere((id, node) {
      if (tabIds.contains(id)) return false;
      node.dispose();
      return true;
    });
  }

  /// The keyboard half of a reveal: the strip scrolls to the chip on its
  /// own, the host gives the content the focus. After the frame, so the
  /// scope has been mounted if the tab was just opened.
  void _answerReveal(LayoutNode root) {
    final reveal = _controller.reveal;
    if (reveal == null || reveal.nonce == _handledReveal) return;
    if (root.leafOf(reveal.tabId) == null) return;
    _handledReveal = reveal.nonce;
    if (!reveal.keyboard) return;
    final node = _focusFor(reveal.tabId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      node.requestFocus();
      // A scope that never held focus takes it itself; the content wants its
      // first field, so step into it. With nothing focusable the scope keeps
      // it, which is still "the keyboard is in this panel".
      if (node.focusedChild == null) node.nextFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final root = _root;
    _pruneContentKeys();
    if (root == null) {
      _shownReorder = null;
      // Still a drop target: a drawer emptied by dragging everything out of
      // it has to take something back.
      return _slot(
        LayoutBuilder(
          builder: (context, constraints) {
            _layout = _controller.solver.layout(
              null,
              PanelRect(0, 0, constraints.maxWidth, constraints.maxHeight),
            );
            return _emptyWithPreview(context);
          },
        ),
      );
    }
    _prune(root);
    _answerReveal(root);
    final reorder = _shownReorder = _reorderIn(root);
    final focusedLeafId = _controller.focusedLeaf(widget.windowId)?.id;
    final base = widget.theme.resolve(Theme.of(context));
    // Styles per group need their own resolution, since the blended floor is
    // a different colour; resolved once per style used, not per group.
    final themes = <PanelTabStyle, PanelTheme>{base.tabStyle: base};
    PanelTheme themeFor(LeafNode leaf) {
      final style = leaf is TabGroup ? widget.tabStyleOf?.call(leaf) : null;
      if (style == null) return base;
      return themes.putIfAbsent(
        style,
        () => widget.theme.withTabStyle(style).resolve(Theme.of(context)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bounds = PanelRect(
          0,
          0,
          constraints.maxWidth,
          constraints.maxHeight,
        );
        _layout = _controller.solver.layout(root, bounds);
        final solo = _soloLeaf;
        final soloChrome = widget.solo?.chrome ?? true;
        final children = <Widget>[];

        // Content first, chrome above it, the drop preview above everything.
        // Content children are sorted by tab id so that a move reorders as
        // little of the Stack as possible; the keys are what preserve state.
        final placements = <_Placement>[];
        for (final leaf in root.leaves) {
          // Under solo every other leaf keeps its own rectangle, offstage:
          // a tab's rectangle is all that changes, so its state is kept.
          final shown = solo == null || leaf.id == solo.id;
          final rect = leaf.id == solo?.id ? bounds : _layout.rectOf(leaf.id)!;
          final theme = themeFor(leaf);
          final chromeHeight = leaf.id == solo?.id && !soloChrome
              ? 0.0
              : switch (leaf) {
                  TabGroup() => widget.chrome.stripHeight(theme, leaf),
                  SinglePanel() => widget.chrome.headerHeight(theme, leaf),
                };
          final content = PanelRect(
            rect.left,
            rect.top + chromeHeight,
            rect.width,
            (rect.height - chromeHeight).clamp(0, double.infinity),
          );
          if (leaf is TabGroup && leaf.isEmpty) {
            if (!shown) continue;
            final empty = widget.emptyLeafBuilder?.call(context, leaf);
            if (empty != null) {
              children.add(
                Positioned.fromRect(
                  key: ValueKey('fl_panel.empty.${leaf.id}'),
                  rect: _toRect(content),
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) => _callbacks.onFocusLeaf(leaf.id),
                    child: empty,
                  ),
                ),
              );
            }
            continue;
          }
          for (final tab in leaf.tabs) {
            placements.add(
              _Placement(
                tab,
                leaf.id,
                content,
                active: identical(tab, leaf.activeTab),
                shown: shown,
              ),
            );
          }
        }
        placements.sort((a, b) => a.tab.id.compareTo(b.tab.id));
        for (final placement in placements) {
          if (!placement.active && !placement.tab.keepAlive) continue;
          final active = placement.active && placement.shown;
          children.add(
            Positioned.fromRect(
              key: ValueKey('fl_panel.tab.${placement.tab.id}'),
              rect: _toRect(placement.rect),
              child: Offstage(
                offstage: !active,
                child: TickerMode(
                  enabled: active,
                  child: Listener(
                    // Translucent: the content still gets the event; the
                    // host only learns which leaf the user is working in.
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) =>
                        _callbacks.onFocusLeaf(placement.leafId),
                    child: FocusScope(
                      node: _focusFor(placement.tab.id),
                      // The key every host of this controller gives this
                      // tab: within a host the `Positioned` above never
                      // moves, and into another host Flutter carries the
                      // element across rather than building it anew.
                      child: KeyedSubtree(
                        key: _contentKeyOf(placement.tab.id),
                        child: widget.contentBuilder(context, placement.tab),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        for (final leaf in root.leaves) {
          if (solo != null && (leaf.id != solo.id || !soloChrome)) continue;
          final rect = leaf.id == solo?.id ? bounds : _layout.rectOf(leaf.id)!;
          final theme = themeFor(leaf);
          final focused = leaf.id == focusedLeafId;
          children.add(
            Positioned(
              key: ValueKey('fl_panel.chrome.${leaf.id}'),
              left: rect.left,
              top: rect.top,
              width: rect.width,
              child: switch (leaf) {
                TabGroup() => widget.chrome.buildStrip(
                  context,
                  StripScope(
                    windowId: widget.windowId,
                    theme: theme,
                    callbacks: _callbacks,
                    decorations: widget.decorations,
                    titleOf: widget.titleOf,
                    focused: focused,
                    group: reorder?.group.id == leaf.id ? reorder!.group : leaf,
                    scrollController: _scrollFor(leaf.id),
                    reveal: _revealFor(leaf),
                  ),
                ),
                SinglePanel() => widget.chrome.buildHeader(
                  context,
                  HeaderScope(
                    windowId: widget.windowId,
                    theme: theme,
                    callbacks: _callbacks,
                    decorations: widget.decorations,
                    titleOf: widget.titleOf,
                    focused: focused,
                    panel: leaf,
                  ),
                ),
              },
            ),
          );
        }

        for (final divider
            in solo == null ? _layout.dividers : const <DividerGeometry>[]) {
          children.add(
            Positioned.fromRect(
              key: ValueKey(
                'fl_panel.divider.${divider.splitId}.${divider.index}',
              ),
              rect: _toRect(divider.rect),
              child: widget.chrome.buildDivider(
                context,
                DividerScope(
                  theme: base,
                  geometry: divider,
                  onDrag: (delta) => _controller.resize(
                    widget.windowId,
                    divider.splitId,
                    divider.index,
                    delta,
                    _layout.bounds,
                  ),
                  onSettle: _controller.settle,
                  onSecondaryTap: (global) =>
                      _openMenu(PanelMenuDividerTarget(divider), global),
                ),
              ),
            ),
          );
        }

        // A reorder is previewed by the chips moving, not by shading the
        // panel they sit over.
        final preview = reorder == null ? _preview(context, base) : null;
        if (preview != null) children.add(preview);

        if (widget.contextMenus != null) {
          children.add(
            PanelMenuHost(key: _menuKey, controller: _menuController),
          );
        }

        return _slot(Stack(clipBehavior: Clip.hardEdge, children: children));
      },
    );
  }

  /// [child] wearing the slot the drop hit-test finds this host by.
  /// Translucent, so the slot is on the path anywhere inside the host — over
  /// a gap no child covers as much as over a chip — without taking the
  /// pointer from what is under it.
  Widget _slot(Widget child) => MetaData(
    metaData: _HostSlot(this),
    behavior: HitTestBehavior.translucent,
    child: child,
  );

  /// The drop preview, when the drag in progress would land in this
  /// window. Above the strips at the pointer, and the drop hit-test must find
  /// them rather than this, so it takes no pointer.
  Widget? _preview(BuildContext context, PanelTheme theme) {
    final drag = _controller.drag;
    final candidate = drag?.targetWindowId == widget.windowId
        ? drag?.candidate
        : null;
    if (candidate == null) return null;
    return Positioned.fromRect(
      key: const ValueKey('fl_panel.preview'),
      rect: _toRect(candidate.preview),
      child: IgnorePointer(
        child: widget.chrome.buildDropPreview(context, theme),
      ),
    );
  }

  Widget _emptyWithPreview(BuildContext context) {
    final empty = widget.emptyBuilder?.call(context) ?? const SizedBox.expand();
    final preview = _preview(context, widget.theme.resolve(Theme.of(context)));
    if (preview == null) return empty;
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned.fill(child: empty),
        preview,
      ],
    );
  }

  GlobalKey _contentKeyOf(String tabId) =>
      _contentKeys(_controller).putIfAbsent(tabId, GlobalKey.new);

  /// Drops the key of every tab no longer anywhere in the workspace. Any
  /// host's build may do it: what it removes no host will build again.
  void _pruneContentKeys() {
    final keys = _contentKeys(_controller);
    if (keys.isEmpty) return;
    final alive = {
      for (final placement in _controller.workspace.placements)
        placement.tab.id,
    };
    keys.removeWhere((id, _) => !alive.contains(id));
  }

  void _register(PanelController controller, String windowId) {
    final hosts = (_hosts[controller] ??= {}).putIfAbsent(windowId, () => {});
    hosts.add(this);
    if (hosts.length < 2) return;
    // Checked once the frame is done rather than here: a host replaced in
    // one rebuild is mounted before the old one is disposed, and only two
    // that are both still there at the end of a frame are a mistake.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final still = _hosts[controller]?[windowId];
      if (still == null || still.length < 2) return;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: FlutterError.fromParts([
            ErrorSummary(
              'Window "$windowId" is shown by ${still.length} PanelHosts at '
              'once.',
            ),
            ErrorDescription(
              'Each host builds every tab of its window under a key every '
              'host of the controller shares, so two hosts of one window '
              'build each tab twice.',
            ),
            ErrorHint(
              'Show a window in one PanelHost at a time, or give the second '
              'one a window of its own.',
            ),
          ]),
          library: 'fl_panel',
        ),
      );
    });
  }

  void _unregister(PanelController controller, String windowId) {
    final windows = _hosts[controller];
    final hosts = windows?[windowId];
    if (hosts == null) return;
    hosts.remove(this);
    if (hosts.isEmpty) windows!.remove(windowId);
  }

  RevealRequest? _revealFor(TabGroup group) {
    final reveal = _controller.reveal;
    if (reveal == null || group.indexOf(reveal.tabId) < 0) return null;
    return reveal;
  }

  static Rect _toRect(PanelRect rect) =>
      Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height);
}

/// The mounted hosts of each controller, by window. Weak on the controller,
/// so a controller nobody holds takes its entry with it.
final _hosts = Expando<Map<String, Set<_PanelHostState>>>('fl_panel.hosts');

final _contentKeyMaps = Expando<Map<String, GlobalKey>>('fl_panel.contentKeys');

/// The content key of every tab of [controller], shared by all its hosts.
Map<String, GlobalKey> _contentKeys(PanelController controller) =>
    _contentKeyMaps[controller] ??= {};

/// What the drop hit-test finds a host by. An identity, not a value: two
/// hosts are two slots.
final class _HostSlot {
  const _HostSlot(this.state);
  final _PanelHostState state;
}

/// A strip drawn mid-reorder: the group as the drop would leave it, where
/// the dragged tab sat before the drag, and where it is drawn now.
final class _Reorder {
  const _Reorder({
    required this.group,
    required this.from,
    required this.shown,
  });
  final TabGroup group;
  final int from;
  final int shown;
}

final class _Placement {
  const _Placement(
    this.tab,
    this.leafId,
    this.rect, {
    required this.active,
    required this.shown,
  });
  final PanelTab tab;
  final String leafId;
  final PanelRect rect;

  /// The active tab of its leaf.
  final bool active;

  /// Its leaf is drawn: always, unless another leaf is solo.
  final bool shown;
}
