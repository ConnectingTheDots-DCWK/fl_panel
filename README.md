# fl_panel

A docking layout for Flutter: a tree of splits, single panels and tab groups
that the user resizes, docks and rearranges, with ordinary Flutter widgets
inside every panel. The shape you know from Blender, Visual Studio and VS
Code — and a file format to bring it back tomorrow.

**[Try it in the browser](https://williamkaroldicioccio.github.io/fl_panel/).**

```dart
final controller = PanelController(
  workspace: PanelWorkspace(windows: [
    PanelWindow(
      id: 'main',
      root: SplitNode(
        id: 'root',
        axis: PanelAxis.horizontal,
        sizes: const [PanelExtent.fixed(240), PanelExtent.flex(1)],
        children: [
          SinglePanel(id: 'files', tab: PanelTab(id: 'files', contentId: 'files')),
          TabGroup(id: 'editors', tabs: [
            PanelTab(id: 'a', contentId: 'editor', metadata: {'title': 'a.md'}),
            PanelTab(id: 'b', contentId: 'editor', metadata: {'title': 'b.md'}),
          ]),
        ],
      ),
    ),
  ]),
);

PanelHost(
  controller: controller,
  windowId: 'main',
  contentBuilder: (context, tab) => switch (tab.contentId) {
    'files' => const FileTree(),
    _ => Editor(path: tab.metadataValue<String>('title') ?? 'untitled'),
  },
);
```

## How the model works

```text
PanelWorkspace                     every window, in one value
└── PanelWindow                    one window's tree, and its focused leaf
    └── LayoutNode
        ├── SplitNode              children along one axis, an extent each
        │   └── LayoutNode …
        ├── SinglePanel            a leaf holding exactly one tab, under a header
        └── TabGroup               a leaf holding tabs, under a strip
            └── PanelTab           a contentId and metadata — never a widget
```

A tab names its content by `contentId`; the content itself stays outside the
model, and your `contentBuilder` turns the id into a widget. That is what lets
the whole tree be saved, restored, edited in a plain `dart` test, and moved
between windows.

**A single panel and a group of one are different things on purpose.** A
`SinglePanel` is Blender's area: a header, no strip. A `TabGroup` keeps its
strip even with one tab, as VS Code's editor groups do. A group never
collapses into a panel by itself — a tab becomes a panel only when it is
dropped in the `single` form, and `PanelTab.allowedForms` says whether it may
— and a panel joined by a tab becomes a group under the same id.

## What you get

- **A tree, not a widget tree.** Immutable values, every edit a pure function
  in `LayoutTree`. Metadata is JSON-shaped and read typed with
  `tab.metadataValue<String>('title')`, which answers null rather than
  throwing on a file somebody edited.
- **Resizing** with weights and fixed extents, content minimums honoured and
  redistributed, over-constrained layouts scaled together.
- **Docking** at both granularities: drag a tab out of its strip or a whole
  panel by its header; the centre of a leaf joins it, its edges split it, the
  window's edges split everything, a strip inserts at the index. A live preview
  shows where it lands, and `DockZones` sets how wide the bands are.
- **A tab can become a panel and a panel a tab**, governed by two affinity
  levels: `PanelTab.allowedForms` says which surface forms a content may take,
  and your `DockPolicy` says who may share a strip with whom.
- **State survives moves.** Content is rendered flat and keyed on the tab, so
  a text field keeps its selection when its tab lands in another group.
- **Three tab styles** — `attached` (VS Code), `blended` (Chrome's shoulders,
  painted), `floating` (pills) — per theme or per group, with a
  `PanelDecorations` for icons, an unsaved dot and a strip button, and a
  `PanelTheme` you can `copyWith`; or replace the whole chrome through
  `PanelChrome`.
- **Chips shrink to a floor, then the strip scrolls** — by wheel, and by
  `controller.focus(tabId, keyboard: true)`, which activates the tab, brings
  its chip into view and hands its content the keyboard.
- **An editor area that stays**: a `persistent` group keeps its place with
  nothing in it — and a second one folds away when it empties, so only the
  last stands empty. A tab can be `closable: false` — a file tree, a console
  — so it moves but never goes, and `DockPolicy.canBeFocusedLeaf` keeps such
  panels from ever being where the next document opens.
- **Right-click menus** on chips, strips, headers and dividers, from the
  controller's own verbs — close, split, move to an edge, equalise, swap —
  greyed where they do not apply, and rewritable through `PanelMenus.build` —
  which, returning nothing, is also how a host shows a menu of its own at the
  request's `globalPosition`.
- **A focused leaf per window**, where `open` puts new content and
  `nextTab`/`closeActive` act; a `closeGuard` for unsaved documents;
  `closeOthers`/`closeToTheRight`; `updateTab` for a title or a flag; and an
  `events` stream (`TabOpened`, `TabClosed`, `TabMoved`, …) for whatever an
  application keeps behind its tabs.
- **Persistence** with an integer `version`: `controller.toJson()`,
  `controller.load(json, resolve: …)`, where the resolver drops tabs this
  build no longer knows and the tree tidies itself.
- **Headless half.** `package:fl_panel/model.dart` imports nothing from
  Flutter: the tree, the edits, the solver, the resolver, the policy and the
  format run in a plain `dart` test or on a server.

## Install

```yaml
dependencies:
  fl_panel: ^1.0.0
```

## Not yet

Floating panels (the file format reserves the slot), maximise, pinning, and
multi-window hosting — the model already holds several windows and moves tabs
between them; wiring a second engine to a second `PanelHost` is the
application's job.

## Example

`example/` is an IDE-shaped demo: files at a fixed width, editors in the
middle, tools on the right that only group with other tools, a console along
the bottom; a style switcher, a button that opens twelve editors to watch the
strip scroll, a focus menu, a context menu, an unsaved dot that makes the
close guard ask, and save/restore of the layout. It is [live on GitHub
Pages](https://williamkaroldicioccio.github.io/fl_panel/), rebuilt from `main`
by `.github/workflows/demo.yml`.

```sh
cd example && flutter run -d linux
```
