import '../model/geometry.dart';
import '../model/node.dart';
import '../model/tab.dart';

/// What may dock where. Two levels, one object.
///
/// The first level is the surface matrix: may this content be shown as a
/// single panel, as a tab, or either? It is answered from [PanelTab.allowedForms] and
/// a policy rarely needs to override it. The second level is entirely the
/// host's: it is handed both sides of a proposed move, metadata included, and
/// answers with a bool — "tool panels only group with tool panels" is one
/// line. A move the policy refuses is simply never offered as a candidate; a
/// drag never has to fail.
///
/// One more question is answered here that is not about docking, because it
/// is the same kind of host knowledge: which leaves may be the window's
/// **focused** leaf — where `open` puts content, what the keyboard verbs act
/// on, whose strip shows the full accent. An IDE's tool panels never are:
/// clicking in the file tree must not make the tree where the next document
/// opens. [canBeFocusedLeaf] is that, and the base class says every leaf does.
///
/// The base class allows everything, so a host that wants no rules passes
/// [DockPolicy.permissive] or nothing at all.
class DockPolicy {
  const DockPolicy();

  static const DockPolicy permissive = DockPolicy();

  /// Level one. Whether [tab] may be shown in [form].
  bool canTakeForm(PanelTab tab, SurfaceForm form) => tab.allows(form);

  /// Level two. Whether [moving] may share a strip with the tabs of [target].
  /// Every tab of a moved group is asked in turn.
  bool canJoin(PanelTab moving, LeafNode target) => true;

  /// Level two. Whether [moving] may be placed on [side] of [neighbour] as a
  /// leaf of its own. Rarely restricted; here for completeness of the matrix.
  bool canSplit(PanelTab moving, LayoutNode neighbour, DockSide side) => true;

  /// Whether [leaf] may be the window's focused leaf. A leaf that may not is
  /// still drawn, still docks and still activates its tabs; it just never
  /// becomes where `open` puts content, and the accent stays on the leaf
  /// that is.
  ///
  /// This is the package's focused leaf, not Flutter's keyboard focus: the
  /// content of a leaf that answers false still takes the keyboard when it
  /// is clicked or tabbed into.
  bool canBeFocusedLeaf(LeafNode leaf) => true;
}
