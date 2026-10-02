## 1.1.0

The host's own words can be translated, and its menus can be read without
reading English. Additive: a host that changes nothing sees exactly what 1.0.0
showed.

### Added

- `PanelLocalizations`, the words the host draws — its menu labels — in the
  pattern of Flutter's `MaterialLocalizations`. `PanelLocalizations.of(context)`
  answers the one a delegate in scope provides, or `DefaultPanelLocalizations`
  (English) when none does, so nothing has to be set up. A host translates by
  extending the default and listing a delegate for it in
  `localizationsDelegates`; extending rather than implementing means a string
  added later shows in English instead of breaking the build. Strings the host
  already sets, such as tab titles through `titleOf`, are not in it. Pinned by
  *every default label comes from the localizations, and keeps its id* and
  *says what the delegate in scope says* in `test/localizations_test.dart`.
- `DefaultPanelLocalizations.delegate`, which answers the English for every
  locale, for a host that lists its delegates explicitly.
- `PanelMenuRequest.localizations` (`const DefaultPanelLocalizations()`).
  `PanelMenus.defaultEntries` stays pure and reads its labels from the
  request, so a test can still assert a menu without pumping one; `PanelHost`
  fills it from `PanelLocalizations.of`.
- `PanelMenuEntry.id` (null) and `PanelMenuEntryId`, one per built-in entry,
  submenu sides included. A builder that keeps, drops or relabels a default
  matched its English label until now, and would have stopped matching the
  day the label was translated; it matches the id instead, and `copyWith`
  keeps it. Pinned by *a builder finds a default by id, whatever it says* in
  `test/localizations_test.dart`.

## 1.0.0

The API is stable from here. Nothing about the file format changed — the
version is still 1 and a layout saved by 0.1.0 loads as it was — so what
follows is names, and four things a host could not do.

### Renamed

- `PanelApp` is `PanelWorkspace`. The `*App` name read as a widget at the
  root of an application, like `MaterialApp`, and this is neither: it is every
  window of the layout. Everything that said "app" follows —
  `PanelController(workspace:)`, `controller.workspace`, `replaceWorkspace`,
  `PanelJson.encodeWorkspace`/`decodeWorkspace`.
- `PanelTab.forms` is `allowedForms`, beside the `allows(form)` that already
  answered from it. The JSON key is still `forms`.
- `DockPolicy.takesFocus` is `canBeFocusedLeaf` (`true`). It never meant
  Flutter's keyboard focus — the content of a leaf answering false still takes
  the keyboard — and now says what it decides in the package's own words:
  `focusedLeafId`, `focusedLeaf`, `focusLeaf`.

| 0.1.0 | 1.0.0 |
| --- | --- |
| `PanelApp(windows: …)` | `PanelWorkspace(windows: …)` |
| `PanelController(app: …)`, `controller.app` | `PanelController(workspace: …)`, `controller.workspace` |
| `controller.replaceApp(…)` | `controller.replaceWorkspace(…)` |
| `PanelJson.encodeApp`/`decodeApp` | `PanelJson.encodeWorkspace`/`decodeWorkspace` |
| `PanelTab(forms: …)`, `tab.forms` | `PanelTab(allowedForms: …)`, `tab.allowedForms` |
| `bool takesFocus(LeafNode leaf)` | `bool canBeFocusedLeaf(LeafNode leaf)` |
| `PanelDecorations(onTabSecondaryTap: …)` | `PanelMenus(build: …)` returning `[]`, see below |
| `DockResolver(edgeBand: …, centreFraction: …)` | `DockResolver(zones: DockZones(…))` |

### Added

- `PanelTab.metadataValue<T>(key)`: the value as a `T`, or null when it is
  absent or something else. Metadata comes back from a file, so a wrong type
  is a stale or hand-edited layout and reads as missing rather than throwing
  under a host. An `int` is accepted as a `double`, because `1.0` comes back
  as `1` from anything that is not the Dart VM. `PanelHost.defaultTitle`
  reads through it. *metadata reads typed* in `test/model_test.dart`.
- `PanelTheme.copyWith`, so a host overrides one field of a theme it was
  handed; `clearTabStyleSpec` (`false`) is how a spec is taken away, and
  `withTabStyle` is that. *switching style drops a spec made for the old one*
  in `test/chrome_test.dart`.
- `DockZones` (`edgeBand` 24, `centreFraction` 0.5) and
  `PanelController.dockZones`. The two numbers were fields on `DockResolver`,
  which the controller built with the defaults, so no host could change them —
  and a touch screen wants wider bands than a mouse. *the drop zones a host
  sets are the ones a drag resolves with* in `test/controller_test.dart`.

### Removed

- `PanelDecorations.onTabSecondaryTap`. It predates the context menus and
  survived so a host with its own chip menu did not suddenly show two. That
  host now returns no entries from `PanelMenus.build` and opens its own at
  `PanelMenuRequest.globalPosition` — the same way on a strip, a header and a
  divider as on a chip, which the decoration never covered. *a right click
  reaches the menu builder with the position* in `test/chrome_test.dart`.
- `TabSlot` and `StripSlot` from the barrel. `StripScope.tabSlot` and
  `stripSlot` are how a chrome applies them and nothing else constructs one.

## 0.1.0

The first cut: the tree, the solver, the controller, the host.

- `PanelApp` → `PanelWindow` → `LayoutNode` → `PanelTab`: an immutable tree
  of splits, single panels and tab groups, edited by the pure functions in
  `LayoutTree`, which normalises after every edit so no caller sees a split
  of one, an empty group or a same-axis nesting. Splits are n-ary and flatten
  same-axis children rather than binary, so `((A|B)|C)` and `(A|(B|C))` — which
  draw the same and resize differently — are one tree. A tab holds a
  `contentId` and metadata, never a widget, so the tree serialises and moves
  between windows without asking anybody. `test/model_test.dart`.
- `PanelSolver`: `PanelExtent.flex(weight)` children share what
  `PanelExtent.fixed(pixels)` ones leave; `PanelTab.minWidth`/`minHeight` are
  the only hard constraint, held by taking from siblings with slack, scaled
  together when even they do not fit. `resize` trades pixels between two
  neighbours and nobody else moves. `test/layout_test.dart`.
- `DockResolver`: five zones over a leaf (centre joins, edges split), a band
  along the window's edges splits the root, a strip hit inserts at the index.
  Every candidate is checked by running the edit, so a drop the policy refuses
  is never offered. `DockPolicy` carries the two affinity levels:
  `canTakeForm` from `PanelTab.forms`, `canJoin`/`canSplit` for the host's
  metadata rules. Default permissive. *affinity* in `test/model_test.dart`.
- `PanelController`: a `ChangeNotifier` over the app; `dock`, `open`, `close`,
  `activate`, `resize`, `moveToWindow`; the drag session (`beginDrag`,
  `updateDrag`, `commitDrag`); `toJson`/`load` with an integer `version`
  (`PanelApp.version`, 1) refused when newer and a `TabResolver` that drops
  what this build cannot show. `onSettled` fires once per gesture, never per
  frame.
- `PanelHost`: one window as one flat `Stack`, a keyed `Positioned` per tab,
  chrome above, preview on top — content is never reparented, so its state
  survives a move. Strips and headers drag; dividers resize with
  `DragStartBehavior.down` so they track the pointer from the first pixel.
  `test/panel_host_test.dart`.
- `PanelChrome`: the contract for everything drawn that is not content, with
  `StripScope.tabSlot`/`stripSlot` as the one rule custom chrome keeps to stay
  a drop target. `DefaultPanelChrome` draws three `PanelTabStyle`s —
  `attached`, `blended` (a `BlendedChipPainter` with Chrome's shoulders, the
  bottom left open so the active tab and its content are one surface),
  `floating` — from a `PanelTabStyleSpec` per style, per theme or per group
  through `PanelHost.tabStyleOf`. `PanelDecorations` hangs an icon, an unsaved
  dot, a strip button and a context menu on the default chrome. *styles*,
  *decorations* and *custom chrome* in `test/chrome_test.dart`.
- Chips share a strip between `PanelTheme.tabMinWidth` (96) and
  `tabMaxWidth` (200) and the strip scrolls once they would shrink below the
  floor — by wheel, never by pointer drag, which already means "move". *shrink
  then scroll* in `test/chrome_test.dart`.
- `PanelWindow.focusedLeafId`, persisted: where `open` puts content (falling
  back to the first leaf that accepts, then the right edge) and what
  `nextTab`/`previousTab`/`closeActive` act on; the focused group's strip
  shows the full accent. `PanelController.focus(tabId, keyboard:)` activates,
  reveals the chip in a scrolled strip and, with `keyboard`, hands the content
  the focus. `test/controller_test.dart` *focus*, `test/chrome_test.dart`
  *focus reveals a clipped chip*.
- `PanelController.events`, synchronous: `TabOpened`, `TabClosed`, `TabMoved`
  from one placement diff per commit, plus `TabActivated`, `LeafFocused`,
  `TabUpdated`, `LayoutReplaced`. `closeGuard` asked before any close, from
  the × or a verb; `closeOthers`, `closeToTheRight`, `closeLeaf` ask per tab.
  `updateTab` for a title or a flag. `test/controller_test.dart`.
- `TabGroup.persistent` (false): a group that stays in the tree when its
  last tab closes — an IDE's editor area, where documents come and go but
  the place they open into is part of the layout. The rule is window-wide:
  an empty persistent group is removed as soon as the tree keeps *another*
  persistent group, so only the last editor area ever stands empty, and a
  tab dragged out of a persistent group makes a persistent group, so an
  editor area split in two is two editor areas that fold back into one as
  they empty. `removeTab` empties rather than removes, `join` keeps the
  flag, and an empty one cannot be dragged: its strip is a drop target, not
  a handle. `LeafNode.activeTab` is nullable for it, and
  `PanelHost.emptyLeafBuilder` draws what goes where its content would. The
  file format carries `persistent`. *a persistent group survives its last
  tab*, *an emptied editor area folds away while another remains* and *a tab
  dragged out of an editor area makes another editor area* in
  `test/model_test.dart`; *an empty persistent group draws its placeholder
  and takes a drop* in `test/panel_host_test.dart`.
- A removed child hands its room to the sibling before it — after it when
  it was first — rather than to every sibling in proportion, so closing the
  right-hand editor group widens the group beside it and does not nudge the
  file tree along too; a fixed neighbour keeps its pixels and the room goes
  to the nearest flex one. In `LayoutTree.replace`. *a removed child hands
  its room to its neighbour* in `test/model_test.dart`.
- `DockPolicy.takesFocus(leaf)` (true): which leaves may be the window's
  focused leaf — where `open` puts content, what the keyboard verbs act on,
  whose strip shows the full accent. An IDE answers no for its tool panels,
  so a click in the file tree never makes the tree where the next document
  opens, and the accent stays on the editor group it will open into.
  `PanelController.focusedLeaf` falls back to the first leaf that does. *focus
  policy* in `test/controller_test.dart`.
- Context menus, in the shape of `fl_nodes_v2`'s: `PanelHost.contextMenus`
  (`const PanelMenus()`; null for none) opens a Material menu on a right
  click on a chip, a strip's background, a single panel's header or a
  divider. The entries are `PanelMenuEntry` data built by
  `PanelMenus.defaultEntries` from the controller's verbs — close verbs and
  a Split submenu on a chip, Close all and Move to edge on a strip or a
  header, Equalise and Swap on a divider, each greyed when it would not
  apply — and `PanelMenus.build` rewrites them with the defaults in hand. A
  `PanelDecorations.onTabSecondaryTap` keeps winning on chips. Two verbs
  came with them: `PanelController.equalise` and `swap`, over
  `LayoutTree.equalise`/`swap`, and `canDock` as the dry run a menu greys
  by; a leaf moved to the window edge it already sits on is a no-op.
  `test/menus_test.dart`.
- `PanelTab.closable` (true): off for content an application always shows.
  The chrome draws no close glyph on its chip or header, and
  `PanelController.close` refuses without asking the guard, so the group
  verbs skip it and `closeLeaf` keeps its leaf; it still moves. In the file
  format as `closable`. *closable* in `test/controller_test.dart`, *an
  unclosable tab draws no glyph* in `test/chrome_test.dart`.
- `PanelDecorations.wrapTab`: a wrapper around the whole chip, inside the
  drop slot — a tooltip, a spotlight target — because a host with a tour
  needs to point at a tab and neither `tabLeading` nor `tabTrailing` is the
  tab. Same test as above.
- `package:fl_panel/model.dart` exports the Flutter-free half;
  `test/flutter_free_test.dart` keeps it so.
- `example/`: an IDE-shaped demo with a metadata policy and save/restore.
