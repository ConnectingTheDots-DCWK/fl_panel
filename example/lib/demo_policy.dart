import 'package:fl_panel/fl_panel.dart';

/// The second affinity level, as a host would write it: tools share strips
/// with tools, editors with editors, and the file tree with nobody. The
/// first level — which forms a tab may take — is on the tabs themselves.
///
/// And the one thing about focus a host knows: only an editor group is ever
/// the focused leaf, so a click in Files or the console does not make it
/// where the next editor opens. The empty editor area counts as one.
final class DemoPolicy extends DockPolicy {
  const DemoPolicy();

  static bool isEditors(LeafNode leaf) =>
      leaf is TabGroup && leaf.persistent ||
      leaf.tabs.any((tab) => tab.metadata['kind'] == 'editor');

  @override
  bool canJoin(PanelTab moving, LeafNode target) {
    final kind = moving.metadata['kind'];
    if (kind == 'files') return false;
    if (target is TabGroup && target.persistent) return kind == 'editor';
    return target.tabs.every((tab) => tab.metadata['kind'] == kind);
  }

  @override
  bool canBeFocusedLeaf(LeafNode leaf) => isEditors(leaf);
}
