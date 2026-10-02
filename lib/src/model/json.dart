import 'edits.dart';
import 'geometry.dart';
import 'node.dart';
import 'tab.dart';
import 'window.dart';

/// A layout file that cannot be read: a newer version than this build knows,
/// or a shape that is not a layout at all.
final class PanelFormatException implements Exception {
  const PanelFormatException(this.message);
  final String message;

  @override
  String toString() => 'PanelFormatException: $message';
}

/// Called with every tab read from a file. Return the tab to keep it — the
/// same one or an adjusted one — or null to drop it: a content id this build
/// no longer knows, a path that is gone. Dropped tabs take their empty
/// leaves with them, so a stale file never restores an empty rectangle.
typedef TabResolver = PanelTab? Function(PanelTab tab);

/// The JSON shape of a [PanelWorkspace], both ways.
///
/// Every wire name here is a string literal, never a Dart identifier: a
/// release build renames types and `Enum.toString()` follows the renaming,
/// while `Enum.name` and a literal do not.
abstract final class PanelJson {
  static Map<String, Object?> encodeWorkspace(PanelWorkspace workspace) => {
    'version': PanelWorkspace.version,
    'windows': [for (final window in workspace.windows) encodeWindow(window)],
  };

  static Map<String, Object?> encodeWindow(PanelWindow window) => {
    'id': window.id,
    'root': window.root == null ? null : encodeNode(window.root!),
    if (window.focusedLeafId != null) 'focused': window.focusedLeafId,
    'floating': const <Object?>[],
  };

  static Map<String, Object?> encodeNode(LayoutNode node) => switch (node) {
    SplitNode() => {
      'type': 'split',
      'id': node.id,
      'axis': node.axis.name,
      'sizes': [for (final size in node.sizes) encodeExtent(size)],
      'children': [for (final child in node.children) encodeNode(child)],
    },
    SinglePanel() => {
      'type': 'single',
      'id': node.id,
      'tab': encodeTab(node.tab),
    },
    TabGroup() => {
      'type': 'group',
      'id': node.id,
      'active': node.active,
      if (node.persistent) 'persistent': true,
      'tabs': [for (final tab in node.tabs) encodeTab(tab)],
    },
  };

  static Map<String, Object?> encodeExtent(PanelExtent extent) =>
      switch (extent) {
        FlexExtent(:final weight) => {'flex': weight},
        FixedExtent(:final pixels) => {'fixed': pixels},
      };

  static Map<String, Object?> encodeTab(PanelTab tab) => {
    'id': tab.id,
    'content': tab.contentId,
    'metadata': tab.metadata,
    'forms': [
      for (final form in SurfaceForm.values)
        if (tab.allows(form)) form.name,
    ],
    if (!tab.keepAlive) 'keepAlive': false,
    if (!tab.closable) 'closable': false,
    if (tab.minWidth > 0) 'minWidth': tab.minWidth,
    if (tab.minHeight > 0) 'minHeight': tab.minHeight,
  };

  /// Reads a file written by [encodeWorkspace]. Refuses a newer version; runs
  /// [resolve] over every tab; normalises every window afterwards.
  static PanelWorkspace decodeWorkspace(
    Map<String, Object?> json, {
    TabResolver? resolve,
  }) {
    final version = json['version'];
    if (version is! int) {
      throw const PanelFormatException('missing integer version');
    }
    if (version > PanelWorkspace.version) {
      throw PanelFormatException(
        'layout version $version is newer than this build reads (${PanelWorkspace.version})',
      );
    }
    final windows = json['windows'];
    if (windows is! List) throw const PanelFormatException('missing windows');
    return PanelWorkspace(
      windows: [
        for (final window in windows)
          decodeWindow(_map(window, 'window'), resolve: resolve),
      ],
    );
  }

  static PanelWindow decodeWindow(
    Map<String, Object?> json, {
    TabResolver? resolve,
  }) {
    final root = json['root'];
    return PanelWindow(
      id: _string(json, 'id'),
      focusedLeafId: json['focused'] is String
          ? json['focused'] as String
          : null,
      root: root == null
          ? null
          : LayoutTree.normalise(
              decodeNode(_map(root, 'root'), resolve: resolve),
            ),
    );
  }

  /// A node, or null when every tab under it was dropped by [resolve]. The
  /// result is not normalised; [decodeWindow] does that once at the top.
  static LayoutNode? decodeNode(
    Map<String, Object?> json, {
    TabResolver? resolve,
  }) {
    final id = _string(json, 'id');
    switch (json['type']) {
      case 'split':
        final rawChildren = json['children'];
        final rawSizes = json['sizes'];
        if (rawChildren is! List || rawSizes is! List) {
          throw PanelFormatException('split $id is missing children or sizes');
        }
        if (rawChildren.length != rawSizes.length) {
          throw PanelFormatException(
            'split $id has ${rawChildren.length} children and ${rawSizes.length} sizes',
          );
        }
        final children = <LayoutNode>[];
        final sizes = <PanelExtent>[];
        for (var i = 0; i < rawChildren.length; i++) {
          final child = decodeNode(
            _map(rawChildren[i], 'child'),
            resolve: resolve,
          );
          if (child == null) continue;
          children.add(child);
          sizes.add(decodeExtent(_map(rawSizes[i], 'size')));
        }
        if (children.isEmpty) return null;
        if (children.length == 1) return children.single;
        return SplitNode(
          id: id,
          axis: _axis(json['axis'], id),
          children: children,
          sizes: sizes,
        );
      case 'single':
        final tab = _resolve(decodeTab(_map(json['tab'], 'tab')), resolve);
        return tab == null ? null : SinglePanel(id: id, tab: tab);
      case 'group':
        final rawTabs = json['tabs'];
        if (rawTabs is! List) {
          throw PanelFormatException('group $id is missing tabs');
        }
        final tabs = <PanelTab>[];
        var active = json['active'] is int ? json['active'] as int : 0;
        for (var i = 0; i < rawTabs.length; i++) {
          final tab = _resolve(decodeTab(_map(rawTabs[i], 'tab')), resolve);
          if (tab != null) {
            tabs.add(tab);
          } else if (i < active) {
            active -= 1;
          }
        }
        final persistent = json['persistent'] == true;
        if (tabs.isEmpty && !persistent) return null;
        return TabGroup(
          id: id,
          tabs: tabs,
          active: tabs.isEmpty ? 0 : active.clamp(0, tabs.length - 1),
          persistent: persistent,
        );
      default:
        throw PanelFormatException('node $id has unknown type ${json['type']}');
    }
  }

  static PanelExtent decodeExtent(Map<String, Object?> json) {
    final flex = json['flex'];
    if (flex is num) return FlexExtent(flex.toDouble());
    final fixed = json['fixed'];
    if (fixed is num) return FixedExtent(fixed.toDouble());
    throw const PanelFormatException('extent is neither flex nor fixed');
  }

  static PanelTab decodeTab(Map<String, Object?> json) {
    final rawForms = json['forms'];
    final forms = <SurfaceForm>{};
    if (rawForms is List) {
      for (final name in rawForms) {
        for (final form in SurfaceForm.values) {
          if (form.name == name) forms.add(form);
        }
      }
    }
    final metadata = json['metadata'];
    return PanelTab(
      id: _string(json, 'id'),
      contentId: _string(json, 'content'),
      metadata: metadata is Map
          ? Map<String, Object?>.from(metadata)
          : const {},
      allowedForms: forms.isEmpty ? SurfaceForm.values.toSet() : forms,
      keepAlive: json['keepAlive'] != false,
      closable: json['closable'] != false,
      minWidth: (json['minWidth'] as num?)?.toDouble() ?? 0,
      minHeight: (json['minHeight'] as num?)?.toDouble() ?? 0,
    );
  }

  static PanelTab? _resolve(PanelTab tab, TabResolver? resolve) =>
      resolve == null ? tab : resolve(tab);

  static PanelAxis _axis(Object? name, String id) {
    for (final axis in PanelAxis.values) {
      if (axis.name == name) return axis;
    }
    throw PanelFormatException('split $id has unknown axis $name');
  }

  static Map<String, Object?> _map(Object? value, String what) {
    if (value is Map) return Map<String, Object?>.from(value);
    throw PanelFormatException('$what is not an object');
  }

  static String _string(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is String) return value;
    throw PanelFormatException('missing string $key');
  }
}
