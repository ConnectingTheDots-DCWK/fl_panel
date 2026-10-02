import 'node.dart';
import 'tab.dart';

/// One window's worth of layout: a tree, or nothing.
///
/// `floating` is reserved for panels that hover over the tree rather than
/// living in it. It is here so the file format has the slot from version 1;
/// nothing reads it yet.
final class PanelWindow {
  const PanelWindow({required this.id, this.root, this.focusedLeafId});

  final String id;

  /// The layout tree, or null for an empty window.
  final LayoutNode? root;

  /// The leaf the user last worked in: where `open` puts new content and
  /// where the keyboard verbs act. Persisted, because "the group I was in"
  /// is part of the layout a user expects back; falls back to the first leaf
  /// when the id no longer exists, see [focusedLeaf].
  final String? focusedLeafId;

  bool get isEmpty => root == null;

  /// The focused leaf, or the first one when none is recorded or the recorded
  /// one is gone. Null only for an empty window.
  LeafNode? get focusedLeaf {
    final root = this.root;
    if (root == null) return null;
    final id = focusedLeafId;
    if (id != null) {
      final found = root.find(id);
      if (found is LeafNode) return found;
    }
    return root.leaves.first;
  }

  PanelWindow withRoot(LayoutNode? root) =>
      PanelWindow(id: id, root: root, focusedLeafId: focusedLeafId);

  PanelWindow withFocus(String? leafId) =>
      PanelWindow(id: id, root: root, focusedLeafId: leafId);

  @override
  bool operator ==(Object other) =>
      other is PanelWindow &&
      other.id == id &&
      other.root == root &&
      other.focusedLeafId == focusedLeafId;

  @override
  int get hashCode => Object.hash(id, root, focusedLeafId);

  @override
  String toString() => 'PanelWindow($id: $root)';
}

/// Every window of the application, in one value.
///
/// Multi-window is in the model from the start so a tab can move between
/// windows as a tree edit; the widget layer hosts one window at a time and
/// the application decides how many hosts there are.
final class PanelWorkspace {
  PanelWorkspace({List<PanelWindow> windows = const []})
    : windows = List.unmodifiable(windows);

  /// The file format's version. Bumped when the JSON shape changes; a file
  /// from a newer build is refused rather than half-read.
  static const int version = 1;

  final List<PanelWindow> windows;

  PanelWindow? window(String id) {
    for (final window in windows) {
      if (window.id == id) return window;
    }
    return null;
  }

  /// The window holding [tabId], if any.
  PanelWindow? windowOfTab(String tabId) {
    for (final window in windows) {
      if (window.root?.leafOf(tabId) != null) return window;
    }
    return null;
  }

  /// Every tab in every window, with where it lives.
  Iterable<TabPlacement> get placements sync* {
    for (final window in windows) {
      final root = window.root;
      if (root == null) continue;
      for (final leaf in root.leaves) {
        for (final tab in leaf.tabs) {
          yield TabPlacement(tab, window.id, leaf.id);
        }
      }
    }
  }

  /// This workspace with [window] replacing the one of the same id, or appended.
  PanelWorkspace withWindow(PanelWindow window) {
    final index = windows.indexWhere((w) => w.id == window.id);
    final next = List<PanelWindow>.of(windows);
    if (index < 0) {
      next.add(window);
    } else {
      next[index] = window;
    }
    return PanelWorkspace(windows: next);
  }

  PanelWorkspace withoutWindow(String id) =>
      PanelWorkspace(windows: windows.where((w) => w.id != id).toList());

  @override
  bool operator ==(Object other) {
    if (other is! PanelWorkspace || other.windows.length != windows.length) {
      return false;
    }
    for (var i = 0; i < windows.length; i++) {
      if (other.windows[i] != windows[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(windows);

  @override
  String toString() => 'PanelWorkspace(${windows.join(', ')})';
}

/// A tab and the window and leaf it is in.
final class TabPlacement {
  const TabPlacement(this.tab, this.windowId, this.leafId);
  final PanelTab tab;
  final String windowId;
  final String leafId;
}
