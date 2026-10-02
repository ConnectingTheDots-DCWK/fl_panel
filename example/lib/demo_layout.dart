import 'package:fl_panel/fl_panel.dart';

const mainWindow = 'main';

/// A tab whose content is an editor: it may be a panel of its own or one of
/// several in a group.
PanelTab editorTab(String id, String title) => PanelTab(
  id: id,
  contentId: 'editor',
  metadata: {'title': title, 'kind': 'editor'},
  minWidth: 240,
  minHeight: 120,
);

/// A tool: inspector, outline, console. Tabbed only — a tool torn out of its
/// group becomes a group of one, never a bare panel — and it groups only with
/// other tools (see `DemoPolicy`).
PanelTab toolTab(String id, String title) => PanelTab(
  id: id,
  contentId: 'tool',
  metadata: {'title': title, 'kind': 'tool'},
  allowedForms: const {SurfaceForm.tabbed},
  minWidth: 160,
  minHeight: 100,
);

/// The IDE shape: files down the left at a fixed width, editors in the
/// middle, tools on the right, a console along the bottom.
LayoutNode demoLayout() => SplitNode(
  id: 'root',
  axis: PanelAxis.vertical,
  sizes: const [PanelExtent.flex(3), PanelExtent.flex(1)],
  children: [
    SplitNode(
      id: 'upper',
      axis: PanelAxis.horizontal,
      sizes: const [
        PanelExtent.fixed(240),
        PanelExtent.flex(3),
        PanelExtent.flex(1),
      ],
      children: [
        SinglePanel(
          id: 'files',
          tab: PanelTab(
            id: 'files',
            contentId: 'files',
            metadata: const {'title': 'Files', 'kind': 'files'},
            allowedForms: const {SurfaceForm.single},
            minWidth: 160,
          ),
        ),
        // Persistent: the editor area stays when its last tab closes, and
        // an editor dragged out of it makes another editor area, which folds
        // away again when it empties while this one remains.
        TabGroup(
          id: 'editors',
          persistent: true,
          tabs: [
            editorTab('editor-1', 'chapter-one.md'),
            editorTab('editor-2', 'chapter-two.md'),
            editorTab('editor-3', 'notes.txt'),
          ],
        ),
        TabGroup(
          id: 'tools',
          tabs: [
            toolTab('inspector', 'Inspector'),
            toolTab('outline', 'Outline'),
          ],
        ),
      ],
    ),
    TabGroup(id: 'bottom', tabs: [toolTab('console', 'Console')]),
  ],
);
