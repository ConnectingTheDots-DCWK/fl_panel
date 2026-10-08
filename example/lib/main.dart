import 'dart:async';
import 'dart:convert';

import 'package:fl_panel/fl_panel.dart';
import 'package:flutter/material.dart';

import 'demo_layout.dart';
import 'demo_policy.dart';
import 'panes.dart';

void main() => runApp(const DemoApp());

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'fl_panel',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4F7CAC),
        brightness: Brightness.dark,
      ),
      home: const DemoPage(),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  late final PanelController controller = PanelController(
    workspace: demoWorkspace(),
    policy: const DemoPolicy(),
    onSettled: () => setState(() => _saves++),
    closeGuard: _confirmClose,
  );
  late final StreamSubscription<PanelEvent> _events;

  PanelTabStyle _style = PanelTabStyle.attached;
  bool _drawerOpen = false;

  /// The focused leaf over the whole dock, strip and all: what an editor's
  /// zen mode is made of. Click into another leaf first to solo that one.
  bool _solo = false;

  /// The last saved layout, as it would sit on disk.
  String? _saved;
  int _saves = 0;
  int _nextEditor = 4;
  String _lastEvent = '';

  @override
  void initState() {
    super.initState();
    _events = controller.events.listen((event) {
      setState(() => _lastEvent = _describe(event));
    });
  }

  @override
  void dispose() {
    _events.cancel();
    controller.dispose();
    super.dispose();
  }

  /// An unsaved editor asks before it goes: the guard in action.
  Future<bool> _confirmClose(PanelTab tab) async {
    if (tab.metadata['dirty'] != true) return true;
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Close ${tab.metadata['title']}?'),
        content: const Text('It has unsaved changes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  void _openEditor({int count = 1}) {
    for (var i = 0; i < count; i++) {
      final n = _nextEditor++;
      controller.open(mainWindow, [editorTab('editor-$n', 'Untitled $n')]);
    }
  }

  void _save() => setState(() => _saved = jsonEncode(controller.toJson()));

  void _restore() {
    final saved = _saved;
    if (saved == null) return;
    controller.load(jsonDecode(saved) as Map<String, Object?>);
  }

  /// The host's own menus, with one line of ours on a chip's: the built-in
  /// entries come in as `defaults`, so adding a line is adding a line.
  List<PanelMenuEntry> _menu(
    PanelMenuRequest request,
    List<PanelMenuEntry> defaults,
  ) => switch (request.target) {
    PanelMenuTabTarget(:final tab) => [
      ...defaults,
      const PanelMenuEntry.separator(),
      PanelMenuEntry(
        label: 'Focus',
        icon: Icons.center_focus_strong_outlined,
        onSelected: () => controller.focus(tab.id, keyboard: true),
      ),
    ],
    _ => defaults,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _Toolbar(
            style: _style,
            onStyle: (style) => setState(() => _style = style),
            onOpenEditor: _openEditor,
            onOpenMany: () => _openEditor(count: 12),
            onFocus: (id) => controller.focus(id, keyboard: true),
            tabs: controller.workspace.placements.map((p) => p.tab).toList(),
            onSave: _save,
            onRestore: _saved == null ? null : _restore,
            onReset: () => controller.replaceWorkspace(demoWorkspace()),
            drawerOpen: _drawerOpen,
            onDrawer: () => setState(() => _drawerOpen = !_drawerOpen),
            solo: _solo,
            onSolo: () => setState(() => _solo = !_solo),
            status: 'settled $_saves× · $_lastEvent',
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _dock()),
                ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) => _drawer(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The drawer: a second host, of the [drawerWindow], sliding over the dock.
  ///
  /// The one rule a drawer has to keep is that **its host stays mounted
  /// while a drag that started in it is in flight**: the drag belongs to the
  /// host it started in, and a host that is removed cancels it. So when a
  /// tool is pulled out over the dock, the drawer slides away and stops
  /// taking the pointer — it is still there, just out of the way — and it
  /// comes back when the drag ends.
  Widget _drawer(BuildContext context) {
    final drag = controller.drag;
    final pulledOut =
        drag != null &&
        drag.windowId == drawerWindow &&
        drag.targetWindowId != drawerWindow;
    final shown = _drawerOpen && !pulledOut;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      left: shown ? 0 : -_drawerWidth,
      top: 0,
      bottom: 0,
      width: _drawerWidth,
      child: IgnorePointer(
        ignoring: !shown,
        child: Material(
          elevation: 8,
          child: PanelHost(
            controller: controller,
            windowId: drawerWindow,
            theme: const PanelTheme(tabStyle: PanelTabStyle.attached),
            contentBuilder: (context, tab) =>
                buildPane(context, tab, onDirty: (tabId, dirty) {}),
            emptyBuilder: (context) => const Center(
              child: Text('Drag a tool here to keep it in the drawer.'),
            ),
          ),
        ),
      ),
    );
  }

  static const double _drawerWidth = 320;

  Widget _dock() => PanelHost(
    controller: controller,
    windowId: mainWindow,
    // The focused leaf, read every build: focus another leaf's tab and solo
    // follows it.
    solo: _solo
        ? switch (controller.focusedLeaf(mainWindow)) {
            final leaf? => PanelSolo(leaf.id),
            null => null,
          }
        : null,
    theme: PanelTheme(tabStyle: _style),
    // Tool groups stay attached whatever the editors wear: a window
    // may mix styles per group.
    tabStyleOf: (group) => group.tabs.first.metadata['kind'] == 'tool'
        ? PanelTabStyle.attached
        : null,
    decorations: PanelDecorations(
      tabLeading: (context, tab) => Icon(switch (tab.metadata['kind']) {
        'editor' => Icons.description_outlined,
        'tool' => Icons.build_outlined,
        _ => Icons.folder_outlined,
      }, size: 14),
      tabTrailing: (context, tab) => tab.metadata['dirty'] == true
          ? const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.circle, size: 8),
            )
          : null,
      stripTrailing: (context, group) =>
          group.tabs.first.metadata['kind'] == 'editor'
          ? IconButton(
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add),
              onPressed: () => controller.open(mainWindow, [
                editorTab('editor-${_nextEditor++}', 'Untitled'),
              ], target: DockTarget.join(group.id)),
            )
          : null,
    ),
    contextMenus: PanelMenus(build: _menu),
    emptyLeafBuilder: (context, group) =>
        const Center(child: Text('Nothing open — pick a file, or press +')),
    contentBuilder: (context, tab) => buildPane(
      context,
      tab,
      onDirty: (tabId, dirty) => controller.updateTab(
        tabId,
        (tab) => tab.copyWith(metadata: {...tab.metadata, 'dirty': dirty}),
      ),
    ),
    emptyBuilder: (context) => const Center(
      child: Text('Every panel is closed. Reset, or open an editor.'),
    ),
  );

  static String _describe(PanelEvent event) => switch (event) {
    TabOpened(:final tab, :final leafId) => 'opened ${tab.id} in $leafId',
    TabClosed(:final tab) => 'closed ${tab.id}',
    TabMoved(:final tab, :final to) => 'moved ${tab.id} to ${to.leafId}',
    TabUpdated(:final after) => 'updated ${after.id}',
    TabActivated(:final tab) => 'activated ${tab.id}',
    LeafFocused(:final leafId) => 'focused $leafId',
    LayoutReplaced() => 'layout replaced',
  };
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.style,
    required this.onStyle,
    required this.onOpenEditor,
    required this.onOpenMany,
    required this.onFocus,
    required this.tabs,
    required this.onSave,
    required this.onRestore,
    required this.onReset,
    required this.drawerOpen,
    required this.onDrawer,
    required this.solo,
    required this.onSolo,
    required this.status,
  });

  final PanelTabStyle style;
  final ValueChanged<PanelTabStyle> onStyle;
  final VoidCallback onOpenEditor;
  final VoidCallback onOpenMany;
  final ValueChanged<String> onFocus;
  final List<PanelTab> tabs;
  final VoidCallback onSave;
  final VoidCallback? onRestore;
  final VoidCallback onReset;
  final bool drawerOpen;
  final VoidCallback onDrawer;
  final bool solo;
  final VoidCallback onSolo;
  final String status;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: drawerOpen ? 'Close the drawer' : 'Open the drawer',
              isSelected: drawerOpen,
              onPressed: onDrawer,
              icon: const Icon(Icons.menu_open),
            ),
            IconButton(
              tooltip: solo ? 'Show every panel' : 'Solo the focused panel',
              isSelected: solo,
              onPressed: onSolo,
              icon: const Icon(Icons.fullscreen),
            ),
            SegmentedButton<PanelTabStyle>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                for (final s in PanelTabStyle.values)
                  ButtonSegment(value: s, label: Text(s.name)),
              ],
              selected: {style},
              onSelectionChanged: (s) => onStyle(s.first),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: onOpenEditor,
              icon: const Icon(Icons.add),
              label: const Text('Editor'),
            ),
            TextButton.icon(
              onPressed: onOpenMany,
              icon: const Icon(Icons.library_add_outlined),
              label: const Text('Twelve'),
            ),
            PopupMenuButton<String>(
              tooltip: 'Focus a tab',
              onSelected: onFocus,
              itemBuilder: (context) => [
                for (final tab in tabs)
                  PopupMenuItem(
                    value: tab.id,
                    child: Text(tab.metadata['title'] as String),
                  ),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.center_focus_strong_outlined, size: 18),
                    SizedBox(width: 4),
                    Text('Focus…'),
                  ],
                ),
              ),
            ),
            TextButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save'),
            ),
            TextButton.icon(
              onPressed: onRestore,
              icon: const Icon(Icons.restore),
              label: const Text('Restore'),
            ),
            TextButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.refresh),
              label: const Text('Reset'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: small,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
