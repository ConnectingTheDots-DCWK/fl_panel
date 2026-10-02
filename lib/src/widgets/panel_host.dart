import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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

  final _menuController = MenuController();
  final _menuKey = GlobalKey<PanelMenuHostState>();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _callbacks = _makeCallbacks();
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
      _callbacks = _makeCallbacks();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    for (final controller in _stripScroll.values) {
      controller.dispose();
    }
    for (final node in _focusScopes.values) {
      node.dispose();
    }
    super.dispose();
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
      _controller.updateDrag(_hitAt(global), _layout);
    },
    onDragLeafStart: (leafId, global) {
      _controller.beginDrag(widget.windowId, DockSource.leaf(leafId));
      _controller.updateDrag(_hitAt(global), _layout);
    },
    onDragUpdate: (global) => _controller.updateDrag(_hitAt(global), _layout),
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

  /// What is under the pointer, for the resolver. Strips are found by
  /// hit-testing for the `TabSlot`/`StripSlot` metadata the chrome wears — the
  /// only way to know where one chip ends and the next begins without
  /// measuring text here. Everything else is geometry: the leaf whose solved
  /// rectangle holds the point.
  DockHit _hitAt(Offset global) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return const DockHit.none();
    final local = box.globalToLocal(global);
    final result = HitTestResult();
    RendererBinding.instance.hitTestInView(
      result,
      global,
      View.of(context).viewId,
    );
    for (final entry in result.path) {
      final target = entry.target;
      if (target is! RenderMetaData) continue;
      final meta = target.metaData;
      if (meta is TabSlot && entry is BoxHitTestEntry) {
        final before = entry.localPosition.dx < target.size.width / 2;
        return DockHit.strip(meta.leafId, before ? meta.index : meta.index + 1);
      }
      if (meta is StripSlot) return DockHit.strip(meta.leafId, meta.count);
    }
    final leaf = _layout.leafAt(_root, local.dx, local.dy);
    if (leaf == null) return const DockHit.none();
    return DockHit.leaf(leaf.id, local.dx, local.dy);
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
    if (root == null) {
      return widget.emptyBuilder?.call(context) ?? const SizedBox.expand();
    }
    _prune(root);
    _answerReveal(root);
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
        final children = <Widget>[];

        // Content first, chrome above it, the drop preview above everything.
        // Content children are sorted by tab id so that a move reorders as
        // little of the Stack as possible; the keys are what preserve state.
        final placements = <_Placement>[];
        for (final leaf in root.leaves) {
          final rect = _layout.rectOf(leaf.id)!;
          final theme = themeFor(leaf);
          final chromeHeight = switch (leaf) {
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
              _Placement(tab, leaf.id, content, identical(tab, leaf.activeTab)),
            );
          }
        }
        placements.sort((a, b) => a.tab.id.compareTo(b.tab.id));
        for (final placement in placements) {
          final active = placement.active;
          if (!active && !placement.tab.keepAlive) continue;
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
                      child: widget.contentBuilder(context, placement.tab),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        for (final leaf in root.leaves) {
          final rect = _layout.rectOf(leaf.id)!;
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
                    group: leaf,
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

        for (final divider in _layout.dividers) {
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

        final drag = _controller.drag;
        final candidate = drag?.windowId == widget.windowId
            ? drag?.candidate
            : null;
        if (candidate != null) {
          children.add(
            Positioned.fromRect(
              key: const ValueKey('fl_panel.preview'),
              rect: _toRect(candidate.preview),
              // Above the strips at the pointer, and the drop hit-test must
              // find them rather than this.
              child: IgnorePointer(
                child: widget.chrome.buildDropPreview(context, base),
              ),
            ),
          );
        }

        if (widget.contextMenus != null) {
          children.add(
            PanelMenuHost(key: _menuKey, controller: _menuController),
          );
        }

        return Stack(clipBehavior: Clip.hardEdge, children: children);
      },
    );
  }

  RevealRequest? _revealFor(TabGroup group) {
    final reveal = _controller.reveal;
    if (reveal == null || group.indexOf(reveal.tabId) < 0) return null;
    return reveal;
  }

  static Rect _toRect(PanelRect rect) =>
      Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height);
}

final class _Placement {
  const _Placement(this.tab, this.leafId, this.rect, this.active);
  final PanelTab tab;
  final String leafId;
  final PanelRect rect;
  final bool active;
}
