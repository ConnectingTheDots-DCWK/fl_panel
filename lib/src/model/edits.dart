import '../policy/dock_policy.dart';
import 'dock.dart';
import 'geometry.dart';
import 'node.dart';
import 'tab.dart';

/// Fresh node ids.
///
/// A counter behind a per-process prefix, so ids minted in this run never
/// collide with the ones in a restored file from an earlier one. Tests hand
/// the edits their own generator for readable trees.
abstract final class PanelIds {
  static final String _prefix = DateTime.now().microsecondsSinceEpoch
      .toRadixString(36);
  static int _counter = 0;

  static String next() => '$_prefix-${_counter++}';
}

/// The edits a layout tree admits, as pure functions: a tree in, a tree out,
/// nothing mutated. Every one ends in [normalise], so no caller ever sees a
/// split of one, an empty group or a same-axis nesting.
abstract final class LayoutTree {
  /// The canonical form of [node]:
  ///
  /// - a split whose child was removed keeps going with the rest; a split
  ///   left with one child is replaced by it; a split left with none is gone;
  /// - an empty group is gone, unless it is persistent — and an empty
  ///   persistent group is gone too when the tree keeps another persistent
  ///   group, so closing the last document in one editor area folds it into
  ///   its neighbour and only the last editor area ever stands empty;
  /// - a child split on its parent's axis is spliced into the parent, its
  ///   children taking their proportional share of the extent it had;
  /// - a group of one stays a group. It collapses to a single panel only
  ///   when a drop asks for that form.
  static LayoutNode? normalise(LayoutNode? node) {
    var result = _normalise(node);
    if (result == null) return null;
    // The window-wide rule, which no subtree can answer for itself: an empty
    // persistent group stays only while it is the last persistent group.
    final persistent = [
      for (final leaf in result.leaves)
        if (leaf is TabGroup && leaf.persistent) leaf,
    ];
    if (persistent.length < 2) return result;
    final empty = persistent.where((group) => group.isEmpty).toList();
    // Keep one only when every persistent group is empty.
    final spare = empty.length == persistent.length ? empty.skip(1) : empty;
    for (final group in spare) {
      result = _normalise(replace(result, group.id, null));
      if (result == null) return null;
    }
    return result;
  }

  static LayoutNode? _normalise(LayoutNode? node) {
    switch (node) {
      case null:
        return null;
      case TabGroup():
        return node.isEmpty && !node.persistent ? null : node;
      case SinglePanel():
        return node;
      case SplitNode():
        final children = <LayoutNode>[];
        final sizes = <PanelExtent>[];
        for (var i = 0; i < node.children.length; i++) {
          final child = _normalise(node.children[i]);
          if (child == null) continue;
          if (child is SplitNode && child.axis == node.axis) {
            final share = node.sizes[i];
            for (var j = 0; j < child.children.length; j++) {
              children.add(child.children[j]);
              sizes.add(_flattenedExtent(share, child.sizes, j));
            }
          } else {
            children.add(child);
            sizes.add(node.sizes[i]);
          }
        }
        if (children.isEmpty) return null;
        if (children.length == 1) return children.single;
        final unchanged =
            children.length == node.children.length &&
            _identical(children, node.children) &&
            _identical(sizes, node.sizes);
        return unchanged
            ? node
            : node.copyWith(children: children, sizes: sizes);
    }
  }

  /// The extent grandchild [index] takes when its parent, which had [share]
  /// of the grandparent, is spliced away. A flex parent hands its weight out
  /// in proportion; a fixed parent's fixed children keep their pixels and its
  /// flex children become flex in the grandparent — the pixel budget the
  /// parent had is not something a flex child can carry.
  static PanelExtent _flattenedExtent(
    PanelExtent share,
    List<PanelExtent> siblings,
    int index,
  ) {
    final own = siblings[index];
    if (own is FixedExtent) return own;
    final weight = (own as FlexExtent).weight;
    if (share is! FlexExtent) return own;
    var total = 0.0;
    for (final sibling in siblings) {
      if (sibling is FlexExtent) total += sibling.weight;
    }
    return FlexExtent(share.weight * weight / total);
  }

  /// [root] with [replacement] where the node with [nodeId] was. The root
  /// itself may be replaced. Unknown ids leave the tree as it is.
  ///
  /// A child removed outright hands its room to the sibling before it — or
  /// after it, when it was first — rather than to every sibling in
  /// proportion: closing the right-hand editor group should widen the group
  /// beside it, not nudge the file tree along too. Only flex room moves; a
  /// fixed neighbour keeps its pixels and the room goes to the nearest flex
  /// sibling, and a fixed child that goes leaves nothing to hand over.
  static LayoutNode? replace(
    LayoutNode? root,
    String nodeId,
    LayoutNode? replacement,
  ) {
    if (root == null) return null;
    if (root.id == nodeId) return replacement;
    if (root is! SplitNode) return root;
    var changed = false;
    final children = <LayoutNode>[];
    final sizes = <PanelExtent>[];
    var orphaned = 0.0;
    for (var i = 0; i < root.children.length; i++) {
      final child = replace(root.children[i], nodeId, replacement);
      if (!identical(child, root.children[i])) changed = true;
      if (child == null) {
        final size = root.sizes[i];
        if (size is! FlexExtent) continue;
        final previous = sizes.lastIndexWhere((s) => s is FlexExtent);
        if (previous >= 0) {
          sizes[previous] = FlexExtent(
            (sizes[previous] as FlexExtent).weight + size.weight,
          );
        } else {
          orphaned += size.weight;
        }
        continue;
      }
      children.add(child);
      var size = root.sizes[i];
      if (orphaned > 0 && size is FlexExtent) {
        size = FlexExtent(size.weight + orphaned);
        orphaned = 0;
      }
      sizes.add(size);
    }
    if (!changed) return root;
    if (children.isEmpty) return null;
    if (children.length == 1) return children.single;
    return root.copyWith(children: children, sizes: sizes);
  }

  /// [root] without the tab with [tabId], normalised. A group down to no
  /// tabs is removed with it unless it is persistent; a group down to one
  /// stays a group.
  static LayoutNode? removeTab(LayoutNode? root, String tabId) {
    final leaf = root?.leafOf(tabId);
    if (leaf == null) return root;
    return normalise(replace(root, leaf.id, _without(leaf, tabId)));
  }

  static LeafNode? _without(LeafNode leaf, String tabId) {
    switch (leaf) {
      case SinglePanel():
        return null;
      case TabGroup():
        final index = leaf.indexOf(tabId);
        if (index < 0) return leaf;
        if (leaf.tabs.length == 1) {
          return leaf.persistent
              ? leaf.copyWith(tabs: const [], active: 0)
              : null;
        }
        final tabs = List<PanelTab>.of(leaf.tabs)..removeAt(index);
        // The active tab follows the content, not the slot: closing the tab to
        // the left of the active one must not switch what is shown.
        var active = leaf.active;
        if (index < active) {
          active -= 1;
        } else if (index == active) {
          active = active.clamp(0, tabs.length - 1);
        }
        return leaf.copyWith(tabs: tabs, active: active);
    }
  }

  /// [root] with [tab] in place of the tab with the same id — a title that
  /// changed, a flag that flipped. Unknown ids leave the tree as it is.
  static LayoutNode? replaceTab(LayoutNode? root, PanelTab tab) {
    final leaf = root?.leafOf(tab.id);
    if (leaf == null) return root;
    final LeafNode next = switch (leaf) {
      SinglePanel() => leaf.copyWith(tab: tab),
      TabGroup() => leaf.copyWith(
        tabs: [for (final t in leaf.tabs) t.id == tab.id ? tab : t],
      ),
    };
    return replace(root, leaf.id, next);
  }

  /// [root] without the leaf with [leafId], normalised.
  static LayoutNode? removeLeaf(LayoutNode? root, String leafId) =>
      normalise(replace(root, leafId, null));

  /// [root] with the tab with [tabId] shown in its group.
  static LayoutNode? activate(LayoutNode? root, String tabId) {
    final leaf = root?.leafOf(tabId);
    if (leaf is! TabGroup) return root;
    final index = leaf.indexOf(tabId);
    if (index == leaf.active) return root;
    return replace(root, leaf.id, leaf.copyWith(active: index));
  }

  /// [root] with [inserted] beside the node with [targetId], on [side].
  ///
  /// When the target's parent already runs along that axis the new node
  /// simply becomes another child of it and the target hands over half its
  /// extent — no nesting is ever created on the parent's axis. Otherwise the
  /// target is wrapped in a new split of two, halves each, which inherits
  /// the target's extent in the grandparent.
  static LayoutNode? insertBeside(
    LayoutNode? root,
    String targetId,
    LayoutNode inserted,
    DockSide side, {
    String Function() newId = PanelIds.next,
  }) {
    final target = root?.find(targetId);
    if (root == null || target == null) return root;
    final parent = root.parentOf(targetId);
    if (parent != null && parent.axis == side.axis) {
      final index = parent.children.indexOf(target);
      final children = List<LayoutNode>.of(parent.children);
      final sizes = List<PanelExtent>.of(parent.sizes);
      final half = _half(sizes[index]);
      sizes[index] = half;
      final at = side.before ? index : index + 1;
      children.insert(at, inserted);
      sizes.insert(at, half);
      return normalise(
        replace(
          root,
          parent.id,
          parent.copyWith(children: children, sizes: sizes),
        ),
      );
    }
    final pair = side.before ? [inserted, target] : [target, inserted];
    final wrapper = SplitNode(id: newId(), axis: side.axis, children: pair);
    return normalise(replace(root, targetId, wrapper));
  }

  static PanelExtent _half(PanelExtent extent) => switch (extent) {
    FlexExtent(:final weight) => FlexExtent(weight / 2),
    FixedExtent(:final pixels) => FixedExtent(pixels / 2),
  };

  /// [tabs] joining the leaf with [leafId] at [index] (or the end), the first
  /// of them becoming active. A single panel becomes a group under the same
  /// id, so anything keyed on the leaf survives the change of form.
  static LayoutNode? join(
    LayoutNode? root,
    String leafId,
    List<PanelTab> tabs,
    int? index,
  ) {
    final leaf = root?.find(leafId);
    if (leaf is! LeafNode || tabs.isEmpty) return root;
    final existing = List<PanelTab>.of(leaf.tabs);
    final at = (index ?? existing.length).clamp(0, existing.length);
    existing.insertAll(at, tabs);
    return replace(
      root,
      leafId,
      TabGroup(
        id: leafId,
        tabs: existing,
        active: at,
        // A persistent group stays persistent however many tabs pass
        // through it; a single panel that becomes a group is an ordinary one.
        persistent: leaf is TabGroup && leaf.persistent,
      ),
    );
  }

  /// A new leaf of [form] holding [tabs]. A group is [persistent] when the
  /// tabs came out of a persistent group: an editor area split in two is two
  /// editor areas, and [normalise] is what folds the empty one away later.
  static LeafNode leafOf(
    List<PanelTab> tabs,
    SurfaceForm form,
    String id, {
    bool persistent = false,
  }) => form == SurfaceForm.single && tabs.length == 1
      ? SinglePanel(id: id, tab: tabs.single)
      : TabGroup(id: id, tabs: tabs, persistent: persistent);

  /// [root] with every child of the split with [splitId] given an equal
  /// share: the way back from a divider dragged somewhere regrettable.
  static LayoutNode? equalise(LayoutNode? root, String splitId) {
    final split = root?.find(splitId);
    if (split is! SplitNode) return root;
    return replace(
      root,
      splitId,
      split.copyWith(
        sizes: List.filled(split.children.length, const PanelExtent.flex()),
      ),
    );
  }

  /// [root] with the two children either side of divider [dividerIndex] of
  /// the split with [splitId] exchanged, extents and all.
  static LayoutNode? swap(LayoutNode? root, String splitId, int dividerIndex) {
    final split = root?.find(splitId);
    if (split is! SplitNode) return root;
    if (dividerIndex < 0 || dividerIndex >= split.children.length - 1) {
      return root;
    }
    final children = List<LayoutNode>.of(split.children);
    final sizes = List<PanelExtent>.of(split.sizes);
    final a = dividerIndex;
    final b = dividerIndex + 1;
    children[a] = split.children[b];
    children[b] = split.children[a];
    sizes[a] = split.sizes[b];
    sizes[b] = split.sizes[a];
    return replace(
      root,
      splitId,
      split.copyWith(children: children, sizes: sizes),
    );
  }

  /// The whole move: [source] taken out of [root] and put down at [target],
  /// if the tree and [policy] admit it. Returns null when they do not, and
  /// when the move would change nothing — a tab dropped onto the centre of
  /// its own group, a panel dropped beside itself. The widget layer uses the
  /// null to decide what lights up, so the rules live here once.
  static LayoutNode? dock(
    LayoutNode? root,
    DockSource source,
    DockTarget target, {
    DockPolicy policy = DockPolicy.permissive,
    String Function() newId = PanelIds.next,
  }) {
    // The no-ops that only exist because the content lands in the tree it
    // left. A move to another window has none of them, which is why they are
    // here and not in [_lift].
    switch (source) {
      case DockTabSource(:final tabId):
        final leaf = root?.leafOf(tabId);
        if (leaf == null) return null;
        if (target is DockJoin && target.leafId == leaf.id) {
          if (target.index == null) return null;
          // A tab reordered within its own strip is removed first, so the
          // index the caller saw — counted with the tab still in place — has
          // to shift down when the tab sat before it.
          if (leaf is TabGroup) {
            final from = leaf.indexOf(tabId);
            final to = target.index!;
            if (to == from || to == from + 1) return null;
            return _place(
              replace(root, leaf.id, _without(leaf, tabId)),
              [leaf.tabs[from]],
              DockJoin(leaf.id, index: to > from ? to - 1 : to),
              policy,
              newId,
              root,
              persistent: leaf.persistent,
            );
          }
        }
      case DockLeafSource():
      case DockFreshSource():
        break;
    }
    final lifted = _lift(root, source);
    if (lifted == null) return null;
    return _place(
      // Not normalised here: a persistent group just emptied by this move
      // must still be there for a join that puts the tab straight back, and
      // the window-wide rule about spare empty groups runs once, at the end.
      _normalise(lifted.tree),
      lifted.tabs,
      target,
      policy,
      newId,
      root,
      leafId: lifted.keepId,
      persistent: lifted.persistent,
    );
  }

  /// [source] taken out of the tree [from] and put down at [target] in the
  /// tree [to] — a move between two windows. Both trees after the move, or
  /// null when [to] or [policy] refuses it.
  ///
  /// The rules are [dock]'s: a moved leaf keeps its id, and a tab taken out
  /// of a persistent group makes a persistent group. Leaf ids come from one
  /// [newId] for every window, so a kept id cannot collide on arrival. The
  /// source tree is normalised and is null when the move emptied it.
  ///
  /// Which windows may trade content is not a question about trees and is
  /// not asked here; see `DockPolicy.canMoveBetween`.
  static ({LayoutNode? from, LayoutNode to})? dockAcross(
    LayoutNode? from,
    LayoutNode? to,
    DockSource source,
    DockTarget target, {
    DockPolicy policy = DockPolicy.permissive,
    String Function() newId = PanelIds.next,
  }) {
    final lifted = _lift(from, source);
    if (lifted == null) return null;
    final placed = _place(
      to,
      lifted.tabs,
      target,
      policy,
      newId,
      to,
      leafId: lifted.keepId,
      persistent: lifted.persistent,
    );
    if (placed == null) return null;
    return (from: normalise(lifted.tree), to: placed);
  }

  /// [source] taken out of [root]: the tree left behind, not yet normalised,
  /// and what is being moved. Null when there is nothing to move.
  static ({
    LayoutNode? tree,
    List<PanelTab> tabs,
    String? keepId,
    bool persistent,
  })?
  _lift(LayoutNode? root, DockSource source) {
    switch (source) {
      case DockTabSource(:final tabId):
        final leaf = root?.leafOf(tabId);
        if (leaf == null) return null;
        return (
          tree: replace(root, leaf.id, _without(leaf, tabId)),
          tabs: [leaf.tabs.firstWhere((tab) => tab.id == tabId)],
          keepId: null,
          // A new leaf made from a persistent group's tab is persistent too.
          persistent: leaf is TabGroup && leaf.persistent,
        );
      case DockLeafSource(:final leafId):
        final leaf = root?.find(leafId);
        if (leaf is! LeafNode) return null;
        // An empty persistent group has nothing to move: its strip is a
        // drop target, not a handle.
        if (leaf.tabs.isEmpty) return null;
        return (
          tree: replace(root, leafId, null),
          tabs: leaf.tabs,
          // A moved leaf keeps its id wherever it lands, so anything keyed on
          // it — the host's chrome, a caller's bookkeeping — follows it.
          keepId: leafId,
          persistent: leaf is TabGroup && leaf.persistent,
        );
      case DockFreshSource(:final tabs):
        if (tabs.isEmpty) return null;
        return (tree: root, tabs: tabs, keepId: null, persistent: false);
    }
  }

  static LayoutNode? _place(
    LayoutNode? tree,
    List<PanelTab> tabs,
    DockTarget target,
    DockPolicy policy,
    String Function() newId,
    LayoutNode? original, {
    String? leafId,
    bool persistent = false,
  }) {
    final LayoutNode? result;
    switch (target) {
      case DockJoin(:final leafId, :final index):
        final leaf = tree?.find(leafId);
        if (leaf is! LeafNode) return null;
        for (final tab in tabs) {
          if (!policy.canTakeForm(tab, SurfaceForm.tabbed)) return null;
          if (!policy.canJoin(tab, leaf)) return null;
        }
        // A single panel joined by another tab is a group afterwards, so its
        // own content has to be allowed the tabbed form too.
        if (leaf is SinglePanel &&
            !policy.canTakeForm(leaf.tab, SurfaceForm.tabbed)) {
          return null;
        }
        result = normalise(join(tree, leafId, tabs, index));
      case DockSplit(:final nodeId, :final side, :final form):
        final neighbour = tree?.find(nodeId);
        if (neighbour == null) return null;
        if (!_allowsLeaf(tabs, form, policy)) return null;
        for (final tab in tabs) {
          if (!policy.canSplit(tab, neighbour, side)) return null;
        }
        result = insertBeside(
          tree,
          nodeId,
          leafOf(tabs, form, leafId ?? newId(), persistent: persistent),
          side,
          newId: newId,
        );
      case DockRoot(:final side, :final form):
        if (!_allowsLeaf(tabs, form, policy)) return null;
        final leaf = leafOf(
          tabs,
          form,
          leafId ?? newId(),
          persistent: persistent,
        );
        if (tree == null) {
          result = leaf;
        } else {
          for (final tab in tabs) {
            if (!policy.canSplit(tab, tree, side)) return null;
          }
          result = insertBeside(tree, tree.id, leaf, side, newId: newId);
        }
    }
    // A no-op is judged by what the user would see, not by equality: a tab
    // lifted out of a group of one and put down beside the neighbour it was
    // already beside comes back as a new leaf with a new id, and a persistent
    // group split beside itself leaves the same picture once its empty half
    // folds away. Extents are not part of the picture either — a drop that
    // only rebalances two neighbours is not something anybody drags to do.
    if (result == null || _sameArrangement(result, original)) return null;
    return result;
  }

  /// Whether [a] and [b] draw the same panels in the same places: the same
  /// axes in the same order, the same tabs in each leaf with the same one
  /// shown, the same forms. Node ids and extents do not count.
  static bool _sameArrangement(LayoutNode a, LayoutNode? b) => switch ((a, b)) {
    (SplitNode a, SplitNode b) =>
      a.axis == b.axis &&
          a.children.length == b.children.length &&
          [
            for (var i = 0; i < a.children.length; i++)
              _sameArrangement(a.children[i], b.children[i]),
          ].every((same) => same),
    (SinglePanel a, SinglePanel b) => a.tab == b.tab,
    (TabGroup a, TabGroup b) =>
      a.active == b.active &&
          a.persistent == b.persistent &&
          _equalTabs(a.tabs, b.tabs),
    _ => false,
  };

  static bool _equalTabs(List<PanelTab> a, List<PanelTab> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _allowsLeaf(
    List<PanelTab> tabs,
    SurfaceForm form,
    DockPolicy policy,
  ) {
    if (form == SurfaceForm.single && tabs.length != 1) return false;
    for (final tab in tabs) {
      if (!policy.canTakeForm(tab, form)) return false;
    }
    return true;
  }

  static bool _identical<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }
}
