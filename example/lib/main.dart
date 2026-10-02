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
    workspace: PanelWorkspace(
      windows: [
        PanelWindow(
          id: mainWindow,
          root: demoLayout(),
          focusedLeafId: 'editors',
        ),
      ],
    ),
    policy: const DemoPolicy(),
    onSettled: () => setState(() => _saves++),
    closeGuard: _confirmClose,
  );
  late final StreamSubscription<PanelEvent> _events;

  PanelTabStyle _style = PanelTabStyle.attached;

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
            onReset: () => controller.setRoot(mainWindow, demoLayout()),
            status: 'settled $_saves× · $_lastEvent',
          ),
          Expanded(
            child: PanelHost(
              controller: controller,
              windowId: mainWindow,
              theme: PanelTheme(tabStyle: _style),
              // Tool groups stay attached whatever the editors wear: a window
              // may mix styles per group.
              tabStyleOf: (group) => group.tabs.first.metadata['kind'] == 'tool'
                  ? PanelTabStyle.attached
                  : null,
              decorations: PanelDecorations(
                tabLeading: (context, tab) =>
                    Icon(switch (tab.metadata['kind']) {
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
              emptyLeafBuilder: (context, group) => const Center(
                child: Text('Nothing open — pick a file, or press +'),
              ),
              contentBuilder: (context, tab) => buildPane(
                context,
                tab,
                onDirty: (tabId, dirty) => controller.updateTab(
                  tabId,
                  (tab) =>
                      tab.copyWith(metadata: {...tab.metadata, 'dirty': dirty}),
                ),
              ),
              emptyBuilder: (context) => const Center(
                child: Text('Every panel is closed. Reset, or open an editor.'),
              ),
            ),
          ),
        ],
      ),
    );
  }

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
