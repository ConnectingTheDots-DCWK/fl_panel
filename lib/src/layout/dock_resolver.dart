import '../model/dock.dart';
import '../model/edits.dart';
import '../model/geometry.dart';
import '../model/node.dart';
import '../model/tab.dart';
import '../policy/dock_policy.dart';
import 'solver.dart';

/// What the widget layer found under the pointer. The resolver turns it into
/// a target; the widget layer only knows which rectangle it is over.
sealed class DockHit {
  const DockHit();

  /// Over the content of a leaf, at a point in layout coordinates.
  const factory DockHit.leaf(String leafId, double x, double y) = DockLeafHit;

  /// Over a tab strip, between the tabs at [index] - 1 and [index].
  const factory DockHit.strip(String leafId, int index) = DockStripHit;

  /// Over nothing that takes a drop, or outside the host.
  const factory DockHit.none() = DockNoHit;
}

final class DockLeafHit extends DockHit {
  const DockLeafHit(this.leafId, this.x, this.y);
  final String leafId;
  final double x;
  final double y;
}

final class DockStripHit extends DockHit {
  const DockStripHit(this.leafId, this.index);
  final String leafId;
  final int index;
}

final class DockNoHit extends DockHit {
  const DockNoHit();
}

/// A drop that would be accepted, and where it would put the content. The
/// preview is what the overlay shades: the target leaf for a join, the half
/// the new leaf would take for a split.
final class DockCandidate {
  const DockCandidate({
    required this.target,
    required this.preview,
    required this.result,
    this.crossesWindows = false,
    this.sourceResult,
  });

  final DockTarget target;
  final PanelRect preview;

  /// The tree after the drop — computed to know the drop is legal, kept so
  /// committing it is a swap rather than a second computation. For a drop in
  /// another window, that window's tree.
  final LayoutNode result;

  /// Whether the content comes from another window than the one it lands in.
  final bool crossesWindows;

  /// When [crossesWindows], the tree of the window the content left, after
  /// the move — null when the move emptied it. Null otherwise.
  final LayoutNode? sourceResult;

  @override
  String toString() => 'DockCandidate($target → $preview)';
}

/// Where over a leaf a drop joins it and where it splits it, and how near
/// the window's edge a drop splits everything.
///
/// Pointer geometry rather than a layout rule, so it is the host's to tune —
/// a touch screen wants wider bands than a mouse — and it reaches the
/// resolver through `PanelController.dockZones`.
final class DockZones {
  const DockZones({this.edgeBand = 24, this.centreFraction = 0.5})
    : assert(edgeBand >= 0, 'edgeBand cannot be negative'),
      assert(
        centreFraction >= 0 && centreFraction <= 1,
        'centreFraction is a share of the leaf',
      );

  /// How far in from the window's edges a drop still splits the root.
  final double edgeBand;

  /// The share of a leaf, in each dimension, that counts as its centre.
  final double centreFraction;
}

/// Turns a pointer position into a dock target, or nothing.
///
/// Five zones over a leaf: the inner half of each dimension joins the leaf as
/// a tab; outside that, the nearest edge splits the leaf on that side. A
/// band along the window's own edges splits the whole tree. A strip hit
/// inserts at the index. Every candidate is checked against the tree and the
/// policy by running the edit, so a target the policy refuses is never
/// offered — nothing lights up rather than something failing.
final class DockResolver {
  const DockResolver({
    this.policy = DockPolicy.permissive,
    this.zones = const DockZones(),
    this.newId = PanelIds.next,
  });

  final DockPolicy policy;
  final DockZones zones;

  final String Function() newId;

  /// The drop [hit] would make in the window whose tree is [root], laid out
  /// as [layout].
  ///
  /// [sourceRoot] is set when [source] lives in another window: it is that
  /// window's tree, and a candidate then carries both trees after the move.
  /// Left null, [source] is taken out of [root] itself.
  ///
  /// A window with no tree takes any hit over it as its root.
  DockCandidate? resolve({
    required LayoutNode? root,
    required LayoutResult layout,
    required DockSource source,
    required DockHit hit,
    required SurfaceForm preferredForm,
    LayoutNode? sourceRoot,
  }) {
    DockCandidate? attempt(DockTarget target, PanelRect preview) =>
        _try(root, source, target, preview, sourceRoot);
    // The other form is a fallback for content the policy will not let
    // stand in its own — a tab that may not stand alone still splits as a
    // group of one. It is not tried when the preferred form was merely a
    // no-op: a single panel already where it is dropped would otherwise
    // light up as the same panel turned into a group.
    final moving = _moving(source, sourceRoot ?? root);
    DockCandidate? attemptForms(
      DockTarget Function(SurfaceForm) target,
      PanelRect preview,
    ) => _canStandAs(moving, preferredForm)
        ? attempt(target(preferredForm), preview)
        : attempt(target(_other(preferredForm)), preview);

    if (root == null) {
      if (hit is DockNoHit) return null;
      return attemptForms(
        (form) => DockRoot(DockSide.right, form: form),
        layout.bounds,
      );
    }
    switch (hit) {
      case DockNoHit():
        return null;
      case DockStripHit(:final leafId, :final index):
        final rect = layout.rectOf(leafId);
        if (rect == null) return null;
        return attempt(DockJoin(leafId, index: index), rect);
      case DockLeafHit(:final leafId, :final x, :final y):
        final bounds = layout.bounds;
        final rootSide = _edgeSide(bounds, x, y);
        if (rootSide != null) {
          final candidate = attemptForms(
            (form) => DockRoot(rootSide, form: form),
            _slice(bounds, rootSide, 0.25),
          );
          if (candidate != null) return candidate;
        }
        final rect = layout.rectOf(leafId);
        if (rect == null) return null;
        final rx = (x - rect.left) / rect.width;
        final ry = (y - rect.top) / rect.height;
        final margin = (1 - zones.centreFraction) / 2;
        if (rx >= margin &&
            rx <= 1 - margin &&
            ry >= margin &&
            ry <= 1 - margin) {
          return attempt(DockJoin(leafId), rect);
        }
        final side = _nearestSide(rx, ry);
        return attemptForms(
          (form) => DockSplit(leafId, side, form: form),
          _slice(rect, side, 0.5),
        );
    }
  }

  /// [target] tried by running the edit — across windows when [sourceRoot]
  /// is set. A split is tried in the preferred form and then the other, by
  /// the caller, so a tab that may not stand alone still splits as a group
  /// of one.
  DockCandidate? _try(
    LayoutNode? root,
    DockSource source,
    DockTarget target,
    PanelRect preview,
    LayoutNode? sourceRoot,
  ) {
    if (sourceRoot != null) {
      final moved = LayoutTree.dockAcross(
        sourceRoot,
        root,
        source,
        target,
        policy: policy,
        newId: newId,
      );
      if (moved == null) return null;
      return DockCandidate(
        target: target,
        preview: preview,
        result: moved.to,
        crossesWindows: true,
        sourceResult: moved.from,
      );
    }
    final result = LayoutTree.dock(
      root,
      source,
      target,
      policy: policy,
      newId: newId,
    );
    if (result == null) return null;
    return DockCandidate(target: target, preview: preview, result: result);
  }

  DockSide? _edgeSide(PanelRect bounds, double x, double y) {
    if (x < bounds.left + zones.edgeBand) return DockSide.left;
    if (x >= bounds.right - zones.edgeBand) return DockSide.right;
    if (y < bounds.top + zones.edgeBand) return DockSide.top;
    if (y >= bounds.bottom - zones.edgeBand) return DockSide.bottom;
    return null;
  }

  static DockSide _nearestSide(double rx, double ry) {
    var side = DockSide.left;
    var distance = rx;
    if (1 - rx < distance) {
      side = DockSide.right;
      distance = 1 - rx;
    }
    if (ry < distance) {
      side = DockSide.top;
      distance = ry;
    }
    if (1 - ry < distance) side = DockSide.bottom;
    return side;
  }

  static PanelRect _slice(PanelRect rect, DockSide side, double fraction) =>
      switch (side) {
        DockSide.left => PanelRect(
          rect.left,
          rect.top,
          rect.width * fraction,
          rect.height,
        ),
        DockSide.right => PanelRect(
          rect.right - rect.width * fraction,
          rect.top,
          rect.width * fraction,
          rect.height,
        ),
        DockSide.top => PanelRect(
          rect.left,
          rect.top,
          rect.width,
          rect.height * fraction,
        ),
        DockSide.bottom => PanelRect(
          rect.left,
          rect.bottom - rect.height * fraction,
          rect.width,
          rect.height * fraction,
        ),
      };

  /// The tabs [source] carries, read out of the tree it lives in.
  static List<PanelTab> _moving(DockSource source, LayoutNode? tree) =>
      switch (source) {
        DockTabSource(:final tabId) => [
          for (final tab in tree?.leafOf(tabId)?.tabs ?? const <PanelTab>[])
            if (tab.id == tabId) tab,
        ],
        DockLeafSource(:final leafId) => switch (tree?.find(leafId)) {
          LeafNode(:final tabs) => tabs,
          _ => const [],
        },
        DockFreshSource(:final tabs) => tabs,
      };

  /// Whether [tabs] may make a new leaf of [form] — `LayoutTree.dock`'s own
  /// rule, asked before the edit so the resolver knows which form to try.
  bool _canStandAs(List<PanelTab> tabs, SurfaceForm form) {
    if (form == SurfaceForm.single && tabs.length != 1) return false;
    return tabs.every((tab) => policy.canTakeForm(tab, form));
  }

  static SurfaceForm _other(SurfaceForm form) =>
      form == SurfaceForm.single ? SurfaceForm.tabbed : SurfaceForm.single;
}
