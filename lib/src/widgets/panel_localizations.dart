import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../model/geometry.dart';

/// The words the host's own chrome says: today, its context menus.
///
/// The same pattern as Flutter's `MaterialLocalizations`. Nothing has to be
/// set up — with no delegate in scope, [of] answers
/// [DefaultPanelLocalizations], which is the English the package has always
/// shown. A host that translates its interface supplies a delegate for this
/// type in `localizationsDelegates`, beside its own and Material's.
///
/// **Extend [DefaultPanelLocalizations] rather than implementing this
/// class.** A later minor version may add a string; a subclass of the
/// default then shows it in English until it is translated, where an
/// `implements` would stop compiling.
///
/// Only what a host cannot already set is here. Tab titles are the host's
/// (`PanelHost.titleOf`), and so is every entry a menu builder adds.
abstract class PanelLocalizations {
  const PanelLocalizations();

  /// The localizations in scope, or English when no delegate provides any.
  static PanelLocalizations of(BuildContext context) =>
      Localizations.of<PanelLocalizations>(context, PanelLocalizations) ??
      const DefaultPanelLocalizations();

  /// A tab's menu: closes that tab.
  String get closeTab;

  /// A tab's menu: closes every other tab in its group.
  String get closeOtherTabs;

  /// A tab's menu: closes the tabs after this one in reading order — to the
  /// right in a left-to-right layout, to the left in a right-to-left one.
  String get closeTabsAfter;

  /// A tab's or a strip's menu: closes every tab in the group.
  String get closeAllTabs;

  /// A single panel's header menu: closes the panel.
  String get closePanel;

  /// A tab's menu: the submenu that splits the tab out beside its group.
  String get split;

  /// A strip's or a header's menu: the submenu that docks the whole group
  /// against one edge of the window.
  String get moveToEdge;

  /// A divider's menu: gives every child of the split the same size.
  String get equalise;

  /// A divider's menu: swaps the two children either side of it. [axis] is
  /// the split's: horizontal for children side by side.
  String swapSides(PanelAxis axis);

  /// One side of a group or a window, in the Split and Move to edge
  /// submenus.
  String dockSide(DockSide side);
}

/// The English every host shows until it says otherwise.
class DefaultPanelLocalizations extends PanelLocalizations {
  const DefaultPanelLocalizations();

  /// Answers [DefaultPanelLocalizations] for every locale, like
  /// `DefaultMaterialLocalizations.delegate` — for a host that lists its
  /// delegates explicitly and wants this one's English among them.
  static const LocalizationsDelegate<PanelLocalizations> delegate =
      _DefaultPanelLocalizationsDelegate();

  @override
  String get closeTab => 'Close';

  @override
  String get closeOtherTabs => 'Close others';

  @override
  String get closeTabsAfter => 'Close to the right';

  @override
  String get closeAllTabs => 'Close all';

  @override
  String get closePanel => 'Close';

  @override
  String get split => 'Split';

  @override
  String get moveToEdge => 'Move to edge';

  @override
  String get equalise => 'Equalise';

  @override
  String swapSides(PanelAxis axis) => switch (axis) {
    PanelAxis.horizontal => 'Swap left and right',
    PanelAxis.vertical => 'Swap top and bottom',
  };

  @override
  String dockSide(DockSide side) => switch (side) {
    DockSide.left => 'Left',
    DockSide.top => 'Top',
    DockSide.right => 'Right',
    DockSide.bottom => 'Bottom',
  };
}

class _DefaultPanelLocalizationsDelegate
    extends LocalizationsDelegate<PanelLocalizations> {
  const _DefaultPanelLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<PanelLocalizations> load(Locale locale) =>
      SynchronousFuture<PanelLocalizations>(const DefaultPanelLocalizations());

  @override
  bool shouldReload(_DefaultPanelLocalizationsDelegate old) => false;
}
