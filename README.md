# fl_panel

A docking layout for Flutter: a tree of splits, single panels and tab groups
that the user resizes, docks and rearranges, with ordinary Flutter widgets
inside every panel. The shape you know from Blender, Visual Studio and VS
Code — and a file format to bring it back tomorrow.

**[Try it in the browser](https://connectingthedots-dcwk.github.io/fl_panel/).**

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
  a text field keeps its selection when its tab lands in another group — or
  in another host.
- **Several hosts, one controller.** Give each window a `PanelHost` — a
  drawer beside the dock, a second pane of the screen — and a tab or a whole
  panel drags from one into another; the host drawn on top under the pointer
  takes the drop, and `DockPolicy.canMoveBetween` can keep a window's tabs at
  home. The host a drag starts in has to stay mounted until the drop, so a
  drawer slides away rather than closing; `example/` shows how.
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
  request's `globalPosition`. Every built-in entry carries a
  `PanelMenuEntryId`, so a builder finds one by what it is rather than by
  what it says.
- **In any language** — see *Localisation* below. English until you say
  otherwise, with nothing to set up.
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

## Used in production

fl_panel is the workspace of [Ripple Effect](https://ripplefx.app), a desktop
application for writing interactive stories as graphs, built with Flutter and
Rust for Linux, macOS and Windows. A project's page is a single `PanelHost`: the
file tree, the changes and the messages are tabs of one group, and every open
document — a board, a passage, a script, a soundscape — is a tab in the editor
area that the author can split, dock and rearrange. The controller's JSON is
saved in the project's `.ripple/workspace.json` and the layout comes back as it
was left; a dock policy keeps a newly opened file out of the tool panels; the
document strips use the `blended` tab style; and the package's own strings are
translated along with the app's.

## Localisation

The words the host draws — today, its menus — come from `PanelLocalizations`,
the same pattern as Flutter's `MaterialLocalizations`. With no delegate in
scope it is `DefaultPanelLocalizations`, the English above. To translate it,
extend the default and hand Flutter a delegate for it, beside your own:

```dart
class GermanPanelLocalizations extends DefaultPanelLocalizations {
  const GermanPanelLocalizations();

  @override
  String get closeTab => 'Schließen';

  @override
  String get closeOtherTabs => 'Andere schließen';
}

class GermanPanelDelegate extends LocalizationsDelegate<PanelLocalizations> {
  const GermanPanelDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'de';

  @override
  Future<PanelLocalizations> load(Locale locale) =>
      SynchronousFuture(const GermanPanelLocalizations());

  @override
  bool shouldReload(GermanPanelDelegate old) => false;
}

// MaterialApp(localizationsDelegates: [GermanPanelDelegate(), ...], …)
```

**Extend, don't implement.** A later minor version may add a string; a
subclass of the default shows it in English until you translate it, where an
`implements` would stop compiling.

Because a label is now in whatever language the host speaks, a menu builder
matches the built-in entries by id:

```dart
PanelMenus(
  build: (request, defaults) => [
    for (final entry in defaults)
      if (entry.id != PanelMenuEntryId.closeTabsAfter) entry,
  ],
)
```

Tab titles are not here: they are yours already, through `PanelHost.titleOf`.

## Install

```yaml
dependencies:
  fl_panel: ^1.1.0
```

## Not yet

Floating panels (the file format reserves the slot), maximise, pinning, and
hosting across engines — several `PanelHost`s in one Flutter view share a
controller and drag between each other, but a second OS window under
`desktop_multi_window` is a second engine with a controller of its own;
wiring the two together is the application's job.

## Example

`example/` is an IDE-shaped demo: files at a fixed width, editors in the
middle, tools on the right that only group with other tools, a console along
the bottom; a style switcher, a button that opens twelve editors to watch the
strip scroll, a focus menu, a context menu, an unsaved dot that makes the
close guard ask, save/restore of the layout, and a drawer — a second host
over the dock — whose tools drag into the dock and back. It is [live on GitHub
Pages](https://connectingthedots-dcwk.github.io/fl_panel/), rebuilt from `main`
by `.github/workflows/demo.yml`.

```sh
cd example && flutter run -d linux
```
