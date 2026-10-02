/// A docking layout for Flutter.
///
/// A tree of splits, single panels and tab groups (`model.dart`), a
/// controller that edits it and runs a drag (`PanelController`), and a host
/// widget that draws one window of it with ordinary widgets inside every
/// panel (`PanelHost`), through a `PanelChrome` that is replaceable.
library;

export 'model.dart';
export 'src/controller/panel_controller.dart';
// TabSlot and StripSlot are what StripScope.tabSlot and stripSlot apply; a
// custom chrome reaches them only through those, so they are not API.
export 'src/widgets/chrome.dart' hide StripSlot, TabSlot;
export 'src/widgets/default_chrome.dart';
export 'src/widgets/menus/panel_menu_entry.dart';
export 'src/widgets/menus/panel_menu_host.dart' show PanelMenuHost;
export 'src/widgets/menus/panel_menus.dart';
export 'src/widgets/panel_host.dart';
export 'src/widgets/panel_theme.dart';
