# Working on fl_panel

A docking layout for Flutter: a tree describing rectangles, a layout
algorithm, interaction and hit-testing, persistence. Standalone package; it
will be consumed as a git submodule by the apps that use it, `ripple_effect`
first, and it knows nothing about what a panel contains.

## Environment

**`flutter` and `dart` are not on PATH.** The toolchain is pinned in `.fvmrc`
to 3.41.9 and reached through FVM. Either works:

```sh
fvm flutter test
export PATH="$HOME/fvm/versions/3.41.9/bin:$PATH"
```

```sh
pre-commit install          # once per clone
pre-commit run --all-files  # sweep the tree
```

The hooks run format, analyze and both test suites — the package's and the
example's — on any Dart change. The example is not a sample; it is the only
thing that exercises the docking end to end.

## Verifying a change

```sh
fvm flutter analyze && fvm flutter test
cd example && fvm flutter analyze && fvm flutter test
fvm flutter run -d linux                                # nothing replaces dragging things
```

`dart format` is checked, never applied by a hook — a hook that rewrites a file
under you turns one failed commit into two.

## House style

Tests: local factory closures at the top of `main()`, `addTearDown(controller.dispose)`,
`reason:` on anything non-obvious, no mocks, helpers declared before first use.
British spelling in prose ("serialisation", "normalises", "colour").

Comments earn their place by saying *why*, especially where the obvious
implementation is wrong. Doc comments on public API; a `///` on a field that
just restates its name is noise.

CHANGELOG entries state the change **and its rationale**, name the symbol in
backticks with its default in parentheses, and close by naming the test that
pins the new behaviour.

## The shape of it

Four layers, each a view onto the one below, and only the top two import
Flutter:

| | |
| --- | --- |
| `lib/src/model/` | The tree — `PanelWorkspace` → `PanelWindow` → `LayoutNode` (`SplitNode`, `SinglePanel`, `TabGroup`) → `PanelTab` — and `LayoutTree`, the edits on it as pure functions. `PanelJson` is the file format. |
| `lib/src/layout/` | `PanelSolver`: tree and bounds in, a rectangle per node and the dividers out; the inverse for one divider. `DockResolver`: a pointer position in, a legal drop out, over the `DockZones` the host hands the controller. |
| `lib/src/policy/` | `DockPolicy`, the two affinity levels. |
| `lib/src/controller/` | `PanelController`, a `ChangeNotifier` over an immutable `PanelWorkspace`: the verbs, the focused leaf, the drag session, the event stream, load and save. |
| `lib/src/widgets/` | `PanelHost`, one window of the layout as widgets; `PanelChrome`, the contract for everything drawn that is not content; `DefaultPanelChrome`, the three tab styles. |

`package:fl_panel/model.dart` exports the first three and nothing else, and
`test/flutter_free_test.dart` is the grep that keeps Flutter out of them. A
tree can be built, edited, solved and serialised headless.

## The decisions

Each of these was argued once, in the design session that started the
package, and is recorded here so it is not argued again by accident.

**A tab holds an identity, never a widget.** `PanelTab` is a `contentId`,
JSON metadata, the forms it may take, and its minimums. The host's
`contentBuilder` turns the id into a widget. Three things rest on this: the
tree serialises without asking anybody; a tab moving between windows —
separate engines under multi-window, nothing can carry a widget across — is a
tree edit and a rebuild from identity; and the host keeps ownership of what a
tab *is*.

**Splits are n-ary and flattened, not binary.** A `SplitNode` holds any
number of children along one axis, and `LayoutTree.normalise` splices a child
split on its parent's axis into the parent. A strictly binary tree draws
`((A|B)|C)` and `(A|(B|C))` identically and resizes them differently, and which
one a user has is an accident of the order they docked things in. Flattening
gives every layout exactly one tree: a saved file round-trips to what the user
recognises, and tests compare trees by equality. The user's original sketch
was `Split(direction, ratio, first, second)`; this is that with the ratio
generalised to one extent per child.

**Extents are weights, and `fixed` is a preference.** `PanelExtent.flex`
children share what is left after `fixed` ones take their pixels. Weights
persist and pixels do not, so a file is indifferent to DPI and window size.
Content minimums (`PanelTab.minWidth`/`minHeight`) are the only hard
constraint: a fixed child is held at its pixels while the minimums allow and
gives them back when they do not, and when even the minimums do not fit,
everything scales down together rather than one child going to zero. A leaf's
minimum is the largest among its tabs, not the active tab's, because switching
tabs must never move a divider.

**A persistent group is the editor area, and the last one stays.**
`TabGroup.persistent` keeps a group in the tree with no tabs in it — the one
place in the model an empty leaf is allowed. Every IDE has it: documents
come and go, but the area they open into is part of the layout, and closing
the last one must leave an empty area rather than hand its rectangle to the
neighbours. The rule is **window-wide**, which is why `normalise` has a pass
over the whole tree after the recursive one: an empty persistent group is
removed as soon as the tree keeps another persistent group, and a tab
dragged out of a persistent group makes a persistent group. So an editor
area split in two is two editor areas, either folds away when it empties
while the other remains, and only the last ever stands empty — the first
draft kept every empty one, and a user who had split the area was left with
a surface they could not close. `removeTab` empties, `join` keeps the flag,
an empty one cannot be dragged, `LeafNode.activeTab` is nullable for it,
and the host draws `emptyLeafBuilder` where its content would be. The first
host to need it was ripple_effect, whose "Nothing open" placeholder is what
the editor area shows with nothing in it.

**Focus is a policy question too.** `DockPolicy.canBeFocusedLeaf(leaf)` says
which leaves may be the window's focused leaf. It is on the dock policy
rather than a flag on a tab because it is the same kind of host knowledge
as who may share a strip with whom: an IDE's tool panels never take focus,
so clicking in the file tree does not move where the next document opens,
and the accent — which is what tells the user where it will open — stays on
the editor group. `focusLeaf` and `activate` consult it; the controller's
`focusedLeaf` falls back to the first leaf that does take focus. The
window's recorded id is left alone, so a policy that changes at runtime
does not lose it.

**`PanelTab.closable` is a model fact, not a chrome option.** A file tree, a
console, an IDE's tool windows: content the application always shows has no
close glyph and `close` refuses it without consulting the guard, so the
group verbs skip it. A chrome option alone would have left the middle click
and the verbs closing what the × could not.

**`SinglePanel` and `TabGroup` are distinct types, and a group of one stays a
group.** The affinities are about which *form* a content may take, and both
shapes exist in real products — Blender's areas are single panels with a
header, VS Code's editor groups keep their strip at one tab. Nothing collapses
a group to a panel by itself; only a drop that asks for the `single` form makes
one. A single panel joined by a tab becomes a group *under the same id*, and a
moved leaf keeps its id, so anything keyed on a leaf follows it.

**Every edit ends in `normalise`, and `dock` returns null for a no-op.** No
caller ever sees a split of one, an empty group that is not persistent, or a
same-axis nesting.
`LayoutTree.dock` answers null when the tree or the policy refuses the move
*and* when the move would change nothing — a tab dropped on the centre of its
own group, a panel dropped beside itself. The resolver uses that null to decide
what lights up, so the rules live in one place and a drag never has to fail.

**Two affinity levels, one policy object.** Level one is the surface matrix,
answered per tab from `PanelTab.allowedForms`: may this content be a single panel, a
tab, or either. Level two is the host's entirely: `DockPolicy.canJoin` and
`canSplit` are handed both sides of a proposed move, metadata included, and
answer with a bool. The base class allows everything.

**A window has a focused leaf, and it is model state.** `PanelWindow.focusedLeafId`
is where `open` puts new content, what `nextTab`/`closeActive` act on, and
whose strip draws the full accent. It moves on activation, on a pointer down
in a panel, and on `focusLeaf`; it persists, because "the group I was in" is
part of the layout a user expects back; and `focusedLeaf` falls back to the
first leaf when the id is gone, so nothing has to keep it valid. Changing it
is not a settle — nor is activating a tab — because neither is worth a write
per click.

**`open` with no target falls back.** The focused leaf first; when it or
the policy refuses — a single panel whose content may not be tabbed, a group
of the wrong kind — the first leaf that accepts, then a new leaf along the
right edge. The demo hit this on its first click: Files was the focused leaf
and Files takes no tabs.

**Chips shrink to a floor, then the strip scrolls.** One behaviour, not a
mode: every chip is `(strip − gaps) / n` clamped to
`[tabMinWidth, tabMaxWidth]`, and once that clamps low the row is wider than
the strip and scrolls. Uniform widths are what make this simple — the reveal
offset is `index × (width + gap)`, no text is measured, and strip hit-testing
would be arithmetic if it were not already `MetaData`. The strip never
scrolls by pointer drag: a drag on a strip already means "move this tab", and
the scroll view's horizontal recogniser would win that arena every time
(it accepts at `kTouchSlop`, a pan at `kPanSlop`). The wheel scrolls it — a
vertical wheel over a horizontal strip, as browsers do — and so does a reveal.

**Reveal is a request with a nonce, answered in two places.** `focus(tabId)`
activates, focuses the leaf, and sets `PanelController.reveal`. The strip
that holds the tab scrolls its chip into view (`TabStrip._scheduleReveal`,
from layout, because the offset depends on the chip width just computed);
with `keyboard: true` the host gives the tab's `FocusScopeNode` the focus and,
if the scope never held it, steps into the first focusable descendant with
`nextFocus()` — a scope that never had focus otherwise keeps it for itself.
Both remember the nonce they answered, so a rebuild does not re-scroll.
Activation alone also reveals: a strip watches `group.active` and scrolls to
a newly active chip whether the change came from a click or a verb.

**Reordering counts indices with the tab still in place.** A strip hit says
"between chips 1 and 2" as the user sees them; `dock` removes the tab first and
shifts the index down when the tab sat before it. Dropping a tab into its own
slot, or the slot right after it, is the no-op it looks like.

## The chrome

`PanelChrome` is the contract: `buildStrip`, `buildHeader`, `buildDivider`,
`buildDropPreview`, plus the two heights. Each is handed a scope — the
resolved theme, the callbacks, the decorations, whether the leaf is focused,
and for a strip the group, a host-owned `ScrollController` and the pending
reveal. **The one rule custom chrome must keep** is `StripScope.tabSlot(index,
child)` around every chip and `stripSlot` around the strip: those apply the
`MetaData` the drop hit-test finds, and chips outside them are not drop
targets. `test/chrome_test.dart` *custom chrome* pins that a bare chrome that
does only this still docks.

`DefaultPanelChrome` draws the three `PanelTabStyle`s from one `TabChip`:

- **attached** — a `DecoratedBox`: flush, hairline right border, accent line
  on top of the active chip (`indicatorColor` when the group is focused,
  `unfocusedIndicatorColor` when not), full height so the active chip paints
  over the strip's bottom hairline and joins its content.
- **blended** — a `CustomPaint` with `BlendedChipPainter`: the Chrome shape,
  an open path from bottom-left to bottom-right whose sides leave the floor
  through a quarter circle of `shoulder` and whose top corners have
  `radius`. The bottom is not drawn, so the active chip and the content are
  one surface; the strip floor is a step darker (`surfaceContainerHigh`) so
  the chip reads as cut out of it. Short separators between *inactive*
  neighbours only. The shoulder is a fillet: the curve is thin at the very
  edge, which is right and which the first test got wrong.
- **floating** — a rounded `DecoratedBox` inset by `inset` with `gap` between
  pills; the active one filled, bordered with the indicator when focused; a
  hairline under the whole strip.

Geometry per style is a `PanelTabStyleSpec` with defaults in
`PanelTabStyleSpec.of`; `PanelTheme.tabStyleSpec` overrides them. A window may
mix styles: `PanelHost.tabStyleOf(group)` picks per group and the host
resolves one theme per style used, since the floor colour differs.

`PanelDecorations` is what an application hangs on the default chrome without
replacing it — `tabLeading`, `tabTrailing` (which *replaces* the close glyph,
the way an unsaved dot does; middle click and the verbs still close),
`wrapTab` (around the whole chip, inside the drop slot — a tooltip or a
tutorial's spotlight target), `stripTrailing`, `headerTrailing`. A right
click is not a decoration: it is `PanelMenus`, whose `build` returning nothing
is how a host opens a menu of its own instead.

**The context menus are `fl_nodes_v2`'s shape, on purpose.** `PanelMenuEntry`
is `NodeMenuEntry` renamed — label, icon, shortcut hint, `onSelected` (null
greys the row), children for a submenu, separators tidied at the end — so an
application hosting both packages draws both menus alike, and so what a
menu offers can be asserted as data (`PanelMenus.defaultEntries` is pure).
`PanelMenuHost` is the node editor's menu host with the same load-bearing
detail: the `MenuAnchor` is a zero-sized box at the click, never the host
around it, or every click on the host would count as inside the menu.
Four targets: a chip, a strip's background, a header, a divider; the chrome
reports them through `ChromeCallbacks.onStripSecondaryTap`,
`onHeaderSecondaryTap` and `DividerScope.onSecondaryTap`. A custom chrome
that wants menus reports the same three. The menus need an `Overlay` above
the host — any app widget — so a bare host passes `contextMenus: null`. The chrome never
requires a `Material` ancestor.

## The words

**What the host says goes through `PanelLocalizations`**
(`lib/src/widgets/panel_localizations.dart`), Flutter's `MaterialLocalizations`
pattern: an abstract class, `DefaultPanelLocalizations` in English, and
`PanelLocalizations.of(context)` falling back to the default when no delegate
is in scope — so a bare host, or a test that pumps one, needs nothing.
`PanelMenus.defaultEntries` stays pure: the words travel on
`PanelMenuRequest.localizations`, which `PanelHost` fills where it builds the
request, and a request built by hand is English.

Three rules hold it together:

- **A string the host can already set is the host's**, and stays out of the
  class: tab titles (`titleOf`), every entry a builder adds.
- **Keys are named by meaning, not by the English.** `closeTabsAfter` says
  "Close to the right" in English and whatever direction is *after* in a
  right-to-left language; `swapSides(axis)` and `dockSide(side)` take the
  value rather than baking one sentence per case.
- **A built-in menu entry is found by `PanelMenuEntryId`, never by its
  label**, and `copyWith` keeps the id. A builder matching `'Close'` breaks
  silently the day the host translates it.

A host translates by **extending** `DefaultPanelLocalizations`, never by
implementing the abstract class, and the doc says so: a new string in a minor
version then falls back to English rather than breaking the host's build. So
adding a getter is a minor change only because the default implements it —
every new one lands in `DefaultPanelLocalizations` in the same commit.

**Not yet:** the close glyph has no tooltip and no semantics label at all,
which is an accessibility gap rather than a translation; when it gets one, the
words go here.

## The one architectural decision

Docking's classic trap is content state surviving a move. Reparent a widget
from group A to group B and Flutter rebuilds it from scratch unless it wears a
`GlobalKey`, and `GlobalKey` reparenting has its own sharp edges — one frame,
one tree, a leak if the key outlives the content.

So `PanelHost` does not reparent. It renders **one flat `Stack`**: one
`Positioned` content child per tab, keyed on the tab's id and placed by the
solver's rectangles, with the chrome — strips, headers, dividers, the drop
preview — as sibling layers above. Moving a tab changes its rectangle and
nothing else. `test/panel_host_test.dart` *content keeps its state when its
tab moves groups* is the pin. Inactive tabs are kept built under `Offstage` +
`TickerMode` unless `PanelTab.keepAlive` is false, in which case they are not
built at all and lose their state — the host says so for content too heavy to
hold.

The same reasoning is in `fl_nodes_v2`'s CLAUDE.md under the same heading,
reached from a different direction: isolation is available one layer up from
the render tree, and the widget layer should stay ordinary widgets.

**One move a `Stack` cannot express is a move to another host**, and that is
the one place a `GlobalKey` is used. Every tab's content is wrapped in a
`KeyedSubtree` whose key is the same in every host of the controller (an
`Expando` on the controller in `panel_host.dart`, pruned in any host's build
of every tab no longer in the workspace), so Flutter carries the element from
one host's `Stack` to the other's. Within a host the `Positioned` above it
never moves, so nothing is reparented there and the flat `Stack` still does
all the work: remove the `KeyedSubtree` and *content keeps its state when its
tab moves groups* still passes while *content keeps its state when its tab
moves to another host* (`test/cross_host_test.dart`) fails.

The sharp edges the paragraph above names are what three rules exist to
blunt, and the first two are checks rather than hopes, because a duplicate
`GlobalKey` corrupts the element tree in a release build where it would only
assert in a debug one:

- **A tab is in one place only.** `PanelWorkspace.duplicateTabId`;
  `PanelJson.decodeWorkspace` refuses such a file, `replaceWorkspace` and
  `setRoot` throw, and `open` refuses a tab that is already open — the
  verb for that is `focus`.
- **A window is shown by one host at a time.** Hosts register per
  `(controller, windowId)`; a second one still mounted **after** the frame is
  reported through `FlutterError.reportError`. After, not at `initState`: a
  host replaced in one rebuild is mounted before the old one is disposed,
  and *a host replaced in one rebuild is not two hosts* is the test that
  failed when the check ran at once.
- **A drop between hosts is one commit of both windows**, so no listener —
  and no frame — ever sees the tab in both or in neither.

## A drag belongs to the workspace, not to a host

Several `PanelHost`s may share one controller, one per window, and a drag that
starts in one may end in any of them. `_hitAt` hit-tests the whole view once
and walks the path: every host wears a translucent `MetaData(_HostSlot)`, and
**the first `_HostSlot` on the path is the host drawn on top at that point** —
so a drawer laid over the dock takes the drop where it covers it, a host
nested in another's tab takes it over itself, and a host under
`IgnorePointer` or `Offstage` is passed over for free. A `TabSlot` or
`StripSlot` counts only when it comes before that host's slot on the path,
which is what makes the strip its own. The hit and that host's last layout go
to `updateDrag(…, windowId:)`; the resolver then runs `LayoutTree.dockAcross`
over both trees, the candidate carries both results, and the host whose
window is `DockDrag.targetWindowId` draws the preview.

`dockAcross` and `dock` share `_lift`, which takes the content out of its
tree; what stays in `dock` are the no-ops that only exist because the content
lands in the tree it left. So a leaf keeps its id and a tab out of an editor
area makes an editor area in either window, and `moveToWindow` is
`dockAcross` too. Which windows may trade content is the host's call, not the
tree's: `DockPolicy.canMoveBetween`, asked per tab before anything else and
never for a move within one window.

**The gesture stays with the host it started in.** A pan recognizer keeps its
pointer route after its widget stops being hit-testable, so a source host made
`IgnorePointer` or slid offscreen mid-drag still delivers the drop — that is
the drawer recipe, and `example/lib/main.dart` `_drawer` is it. A source host
that is **removed** takes the recognizer with it, and a disposed recognizer
reports neither an end nor a cancel: the drop stayed shaded with nothing left
to finish it until `_cancelOrphanedDrag`, which cancels after the frame
(the tree is locked while it is torn down) and only if it is still the same
drag. `PanelController.dispose` clears the drag so that late cancel is a
no-op on a controller torn down in the same frame.

A window with no tree is still a drop target — a drawer emptied by dragging
everything out has to take something back — so the empty host wears its slot
too, and any hit over it lands as the window's root.

## Solo is a view, not an edit

`PanelHost.solo` shows one leaf over the whole host — an editor's zen mode —
and it lives on the host, not in the tree, on purpose. Maximise written into
the model would be saved, would have to be undone on every close and dock
that touched the leaf, and would come back on the next launch whether the
user wanted it or not; a host parameter is gone the moment the app stops
passing it. It costs nothing in state, because of the one architectural
decision above: under solo the leaf's rectangle is the host's bounds and
every other tab keeps its own solved rectangle, offstage, under the same key
— a rectangle is all that changes, so no content is rebuilt going in or
coming out.

What solo leaves out is everything that would act on a leaf nobody can see:
no other leaf's chrome, no divider, and **no drop** — `_hitAt` refuses a
solo host, since a preview over a hidden leaf would show the user nothing,
and the hidden leaves' rectangles are not where they appear to be.
`chrome: false` drops the solo leaf's own strip too, so the app moving
between tabs does it with `focus`, `nextTab` and `previousTab`. A `leafId`
the window does not hold falls back to the layout rather than to nothing:
the app is meant to pass the focused leaf, and for the frame after that leaf
closes, the old id is stale.

## Traps

**Two pointer deltas can land in one frame.** A mouse reports faster than the
screen paints. `PanelController.resize` solves the *current* tree for the
host's bounds on every call rather than reading pixels off the host's last
frame — with the stale layout, the second delta was measured against the same
pixels as the first and the divider lost twenty pixels on every grab. The
test *dragging a divider resizes and settles once* is what caught it.

**Dividers deliver the slop distance.** `DividerHandle` uses
`DragStartBehavior.down`; with the default `start`, the first eighteen pixels
of every drag are swallowed by the recognizer and the handle lags the pointer.

**Strip hit-testing goes through `MetaData`, not geometry.** The host knows
every leaf's rectangle but not where one chip ends and the next begins —
that depends on text. Each chip wears `MetaData(TabSlot(leafId, index))` and
the strip's tail `StripSlot`; `PanelHost._hitAt` hit-tests the view at the
pointer and walks the path for them, using the entry's local position to pick
before or after. Everything below the strips is geometry: `LayoutResult.leafAt`.

**The chrome must not need `Material`.** The close glyph was an `InkWell` and
threw "No Material widget found" in the first widget test. A host that is not
Material — or a test that pumps the host bare — has to work.

**The drop overlay is `IgnorePointer`.** It is painted above the strips at the
pointer, and the hit-test above would otherwise find it instead of them.

**`onSettled` is the persistence hook, and live frames do not fire it.** A
drop, a close, a divider *release*, an `updateTab` settle; the frames of a
drag do not; `activate` and `focusLeaf` do not either, because which tab is
active is persisted but not worth a write per click. A host that saves on
`onSettled` gets one write per gesture.

**Events come from one diff.** `PanelController.events` reports
`TabOpened`/`TabClosed`/`TabMoved` by comparing every tab's placement before
and after a commit, so no verb can forget to report and `load` reports what
it replaced. `TabActivated`, `LeafFocused`, `TabUpdated` and `LayoutReplaced`
are sent by the verbs themselves. The stream is synchronous: a listener sees
the event before the frame that draws its consequence, which is what lets a
host drop a session in the same tick its tab disappears.

**`close` is async because of the guard.** `closeGuard` may show a dialog; the
× fires and forgets, the verbs await, and the group verbs ask per tab in
order so a refusal keeps one tab and closes the rest.

## What is deliberately not here yet

Floating panels (`PanelWindow` reserves the `floating` slot in the file
format, empty), maximise/minimise kept in the layout (`solo` is the view half
of it, and saves nothing), pinning, overflow affordances on
a scrolled strip (edge fades, a ⌄ listing every tab), and any
`desktop_multi_window` integration. The model is multi-window from the start —
`PanelWorkspace` holds windows, hosts of one controller drag between each
other, `PanelController.moveToWindow` moves a tab by code — but a second OS
window is a second engine with its own controller, where neither a drag nor a
`GlobalKey` can cross; wiring the two is the application's job when it comes.

## Releasing

Bump `version` in `pubspec.yaml`, turn `## Unreleased` into `## <version>` in
the CHANGELOG, merge, then run **Actions → publish** on the default branch. It
tags `v<version>`, cuts the GitHub release with that CHANGELOG section as its
notes, and publishes to pub.dev with GitHub's OIDC token, so no credential
lives anywhere. Pushing a `v*` tag, or creating a release in the UI, only
publishes. `.github/workflows/publish.yml` says why it dispatches itself on
the tag, and what pub.dev's admin page must allow for that.

Before a version goes out, check the archive rather than the dry-run: the
dry-run does not resolve imports, and fl_crashpad 1.0.0 shipped without a file
its build hook imported.
