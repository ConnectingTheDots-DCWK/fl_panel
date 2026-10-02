import 'package:flutter/material.dart';

import '../../controller/panel_controller.dart';
import '../../layout/solver.dart';
import '../../model/dock.dart';
import '../../model/geometry.dart';
import '../../model/node.dart';
import '../../model/tab.dart';
import 'panel_menu_entry.dart';

/// What was right-clicked.
@immutable
sealed class PanelMenuTarget {
  const PanelMenuTarget();
}

/// A chip in a strip.
final class PanelMenuTabTarget extends PanelMenuTarget {
  const PanelMenuTabTarget(this.tab, this.leaf);
  final PanelTab tab;
  final LeafNode leaf;
}

/// A strip's background, past its chips.
final class PanelMenuStripTarget extends PanelMenuTarget {
  const PanelMenuStripTarget(this.group);
  final TabGroup group;
}

/// A single panel's header.
final class PanelMenuHeaderTarget extends PanelMenuTarget {
  const PanelMenuHeaderTarget(this.panel);
  final SinglePanel panel;
}

/// The divider between two split children.
final class PanelMenuDividerTarget extends PanelMenuTarget {
  const PanelMenuDividerTarget(this.divider);
  final DividerGeometry divider;
}

/// Everything a menu is built from.
@immutable
class PanelMenuRequest {
  const PanelMenuRequest({
    required this.controller,
    required this.windowId,
    required this.target,
    required this.globalPosition,
  });

  final PanelController controller;
  final String windowId;
  final PanelMenuTarget target;

  /// Where the click landed, for a host that wants to open something of
  /// its own there.
  final Offset globalPosition;
}

/// Decides the entries of a menu, given the ones the host would have shown.
typedef PanelMenuBuilder =
    List<PanelMenuEntry> Function(
      PanelMenuRequest request,
      List<PanelMenuEntry> defaults,
    );

/// The host's right-click menus: on a chip, on a strip's background, on a
/// single panel's header and on a divider.
///
/// Pass `contextMenus: null` to `PanelHost` to turn them off. A host with a
/// menu of its own builds no entries — [build] returning an empty list —
/// and opens its own at [PanelMenuRequest.globalPosition]. The menus are
/// Material's, opened in the nearest `Overlay`, so a host with none needs
/// `contextMenus: null`.
@immutable
class PanelMenus {
  const PanelMenus({this.build});

  /// Rewrites the entries just before they are shown.
  ///
  /// It receives the defaults, so adding one line is `[...defaults, mine]`
  /// rather than rebuilding the menu. Returning an empty list opens nothing.
  final PanelMenuBuilder? build;

  /// The entries for [request], after [build] has had its say.
  List<PanelMenuEntry> entriesFor(PanelMenuRequest request) {
    final defaults = defaultEntries(request);
    final built = build?.call(request, defaults) ?? defaults;
    return PanelMenuEntry.tidy(built);
  }

  /// What the host offers by itself, from the controller's own verbs. Pure,
  /// so a test can assert what a menu says without opening one.
  static List<PanelMenuEntry> defaultEntries(PanelMenuRequest request) {
    final c = request.controller;
    final windowId = request.windowId;
    return switch (request.target) {
      PanelMenuTabTarget(:final tab, :final leaf) => [
        PanelMenuEntry(
          label: 'Close',
          onSelected: tab.closable ? () => c.close(tab.id) : null,
        ),
        PanelMenuEntry(
          label: 'Close others',
          onSelected: leaf.tabs.any((t) => t.id != tab.id && t.closable)
              ? () => c.closeOthers(tab.id)
              : null,
        ),
        PanelMenuEntry(
          label: 'Close to the right',
          onSelected:
              leaf is TabGroup &&
                  leaf.tabs
                      .skip(leaf.indexOf(tab.id) + 1)
                      .any((t) => t.closable)
              ? () => c.closeToTheRight(tab.id)
              : null,
        ),
        PanelMenuEntry(
          label: 'Close all',
          onSelected: leaf.tabs.any((t) => t.closable)
              ? () => c.closeLeaf(windowId, leaf.id)
              : null,
        ),
        const PanelMenuEntry.separator(),
        PanelMenuEntry(
          label: 'Split',
          icon: Icons.vertical_split_outlined,
          children: [
            for (final side in DockSide.values)
              PanelMenuEntry(
                label: _sideLabel(side),
                // A leaf of one tab split beside itself would be the same
                // picture under a new id: not offered.
                onSelected:
                    leaf.tabs.length > 1 &&
                        c.canDock(
                          windowId,
                          DockSource.tab(tab.id),
                          DockTarget.split(leaf.id, side),
                        )
                    ? () => c.dock(
                        windowId,
                        DockSource.tab(tab.id),
                        DockTarget.split(leaf.id, side),
                      )
                    : null,
              ),
          ],
        ),
      ],
      PanelMenuStripTarget(:final group) => [
        PanelMenuEntry(
          label: 'Close all',
          onSelected: group.tabs.any((t) => t.closable)
              ? () => c.closeLeaf(windowId, group.id)
              : null,
        ),
        const PanelMenuEntry.separator(),
        _moveToEdge(c, windowId, group),
      ],
      PanelMenuHeaderTarget(:final panel) => [
        PanelMenuEntry(
          label: 'Close',
          onSelected: panel.tab.closable
              ? () => c.closeLeaf(windowId, panel.id)
              : null,
        ),
        const PanelMenuEntry.separator(),
        _moveToEdge(c, windowId, panel),
      ],
      PanelMenuDividerTarget(:final divider) => [
        PanelMenuEntry(
          label: 'Equalise',
          icon: Icons.balance_outlined,
          onSelected: _isEqual(c, windowId, divider.splitId)
              ? null
              : () => c.equalise(windowId, divider.splitId),
        ),
        PanelMenuEntry(
          label: divider.axis == PanelAxis.horizontal
              ? 'Swap left and right'
              : 'Swap top and bottom',
          icon: Icons.swap_horiz_outlined,
          onSelected: () => c.swap(windowId, divider.splitId, divider.index),
        ),
      ],
    };
  }

  /// A leaf moved to one of the window's edges, as a leaf of its own.
  static PanelMenuEntry _moveToEdge(
    PanelController c,
    String windowId,
    LeafNode leaf,
  ) => PanelMenuEntry(
    label: 'Move to edge',
    icon: Icons.open_in_full_outlined,
    children: [
      for (final side in DockSide.values)
        PanelMenuEntry(
          label: _sideLabel(side),
          onSelected:
              c.canDock(
                windowId,
                DockSource.leaf(leaf.id),
                DockTarget.root(side, form: leaf.form),
              )
              ? () => c.dock(
                  windowId,
                  DockSource.leaf(leaf.id),
                  DockTarget.root(side, form: leaf.form),
                )
              : null,
        ),
    ],
  );

  static bool _isEqual(PanelController c, String windowId, String splitId) {
    final split = c.rootOf(windowId)?.find(splitId);
    if (split is! SplitNode) return true;
    return split.sizes.every((size) => size == const PanelExtent.flex());
  }

  static String _sideLabel(DockSide side) => switch (side) {
    DockSide.left => 'Left',
    DockSide.top => 'Top',
    DockSide.right => 'Right',
    DockSide.bottom => 'Bottom',
  };
}
