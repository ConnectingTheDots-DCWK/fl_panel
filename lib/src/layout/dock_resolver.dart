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
  });

  final DockTarget target;
  final PanelRect preview;

  /// The tree after the drop — computed to know the drop is legal, kept so
  /// committing it is a swap rather than a second computation.
  final LayoutNode result;

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

  DockCandidate? resolve({
    required LayoutNode? root,
    required LayoutResult layout,
    required DockSource source,
    required DockHit hit,
    required SurfaceForm preferredForm,
  }) {
    switch (hit) {
      case DockNoHit():
        return null;
      case DockStripHit(:final leafId, :final index):
        final rect = layout.rectOf(leafId);
        if (rect == null) return null;
        return _try(root, source, DockJoin(leafId, index: index), rect);
      case DockLeafHit(:final leafId, :final x, :final y):
        final bounds = layout.bounds;
        final rootSide = _edgeSide(bounds, x, y);
        if (rootSide != null && root != null) {
          final candidate = _tryForms(
            root,
            source,
            preferredForm,
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
          return _try(root, source, DockJoin(leafId), rect);
        }
        final side = _nearestSide(rx, ry);
        return _tryForms(
          root,
          source,
          preferredForm,
          (form) => DockSplit(leafId, side, form: form),
          _slice(rect, side, 0.5),
        );
    }
  }

  /// A split in the preferred form, or in the other form when the preferred
  /// one is refused — a tab that may not stand alone still splits as a group
  /// of one.
  DockCandidate? _tryForms(
    LayoutNode? root,
    DockSource source,
    SurfaceForm preferred,
    DockTarget Function(SurfaceForm) target,
    PanelRect preview,
  ) {
    return _try(root, source, target(preferred), preview) ??
        _try(root, source, target(_other(preferred)), preview);
  }

  DockCandidate? _try(
    LayoutNode? root,
    DockSource source,
    DockTarget target,
    PanelRect preview,
  ) {
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

  static SurfaceForm _other(SurfaceForm form) =>
      form == SurfaceForm.single ? SurfaceForm.tabbed : SurfaceForm.single;
}
