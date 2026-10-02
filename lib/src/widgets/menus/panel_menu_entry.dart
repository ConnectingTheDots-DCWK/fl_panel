import 'package:flutter/material.dart';

/// Which built-in entry a [PanelMenuEntry] is.
///
/// A menu builder that keeps, drops or relabels one of the package's own
/// entries matches on this, never on [PanelMenuEntry.label]: the label is in
/// whatever language the host speaks, and a match on `'Close'` stops
/// matching the day the host translates it. Entries a host adds carry no id.
enum PanelMenuEntryId {
  closeTab,
  closeOtherTabs,
  closeTabsAfter,
  closeAllTabs,
  closePanel,
  split,
  splitLeft,
  splitTop,
  splitRight,
  splitBottom,
  moveToEdge,
  moveToLeftEdge,
  moveToTopEdge,
  moveToRightEdge,
  moveToBottomEdge,
  equalise,
  swapSides,
}

/// One row of a context menu.
///
/// Entries are data rather than widgets so that what a menu offers — and what
/// it offers greyed out — can be asserted without pumping a menu and
/// dismissing it. It also gives a host something to inspect: the build hook
/// receives the defaults and can filter or reorder them instead of having to
/// rebuild the whole menu to change one line. The shape is `fl_nodes_v2`'s
/// `NodeMenuEntry`, so an application that hosts both draws both the same.
@immutable
class PanelMenuEntry {
  const PanelMenuEntry({
    required this.label,
    this.icon,
    this.shortcut,
    this.onSelected,
    this.children = const <PanelMenuEntry>[],
    this.id,
  }) : _separator = false;

  /// A rule between two groups of entries.
  ///
  /// Leading, trailing and doubled separators are dropped when the menu is
  /// built, so a hook that removes the last entry of a group does not leave a
  /// rule hanging under nothing.
  const PanelMenuEntry.separator()
    : label = '',
      icon = null,
      shortcut = null,
      onSelected = null,
      children = const <PanelMenuEntry>[],
      id = null,
      _separator = true;

  final String label;
  final IconData? icon;

  /// Rendered as a hint. It does not bind anything — a menu that claimed a
  /// key it did not own would be lying.
  final MenuSerializableShortcut? shortcut;

  /// Null renders the entry disabled, which is the point: an action that does
  /// not apply right now should still say it exists.
  final VoidCallback? onSelected;

  /// Non-empty turns this into a submenu, and [onSelected] is then ignored.
  final List<PanelMenuEntry> children;

  /// Which built-in entry this is, or null for one a host made. Kept by
  /// [copyWith], so a relabelled default is still recognisable.
  final PanelMenuEntryId? id;

  final bool _separator;

  bool get isSeparator => _separator;
  bool get isSubmenu => children.isNotEmpty;

  /// A submenu is enabled when anything inside it is, however deep.
  bool get isEnabled =>
      isSubmenu ? children.any((child) => child.isEnabled) : onSelected != null;

  PanelMenuEntry copyWith({
    String? label,
    IconData? icon,
    MenuSerializableShortcut? shortcut,
    VoidCallback? onSelected,
    List<PanelMenuEntry>? children,
    PanelMenuEntryId? id,
  }) => _separator
      ? this
      : PanelMenuEntry(
          label: label ?? this.label,
          icon: icon ?? this.icon,
          shortcut: shortcut ?? this.shortcut,
          onSelected: onSelected ?? this.onSelected,
          children: children ?? this.children,
          id: id ?? this.id,
        );

  /// Drops separators that would render against nothing.
  static List<PanelMenuEntry> tidy(List<PanelMenuEntry> entries) {
    final out = <PanelMenuEntry>[];
    for (final entry in entries) {
      if (entry.isSeparator && (out.isEmpty || out.last.isSeparator)) continue;
      out.add(entry);
    }
    while (out.isNotEmpty && out.last.isSeparator) {
      out.removeLast();
    }
    return out;
  }

  @override
  String toString() => _separator
      ? 'PanelMenuEntry.separator()'
      : 'PanelMenuEntry($label'
            '${isSubmenu ? ', ${children.length} children' : ''}'
            '${isEnabled ? '' : ', disabled'})';
}
