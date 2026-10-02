import 'package:fl_panel/fl_panel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PanelTab tab(String id) =>
      PanelTab(id: id, contentId: id, metadata: {'title': 'T$id'});

  PanelController controller(LayoutNode root, {String? focused}) {
    final c = PanelController(
      workspace: PanelWorkspace(
        windows: [PanelWindow(id: 'w', root: root, focusedLeafId: focused)],
      ),
    );
    addTearDown(c.dispose);
    return c;
  }

  /// A group of [n] tabs beside a single panel, in a 1000 × 400 window.
  LayoutNode manyTabs(int n) => SplitNode(
    id: 'root',
    axis: PanelAxis.horizontal,
    sizes: const [PanelExtent.fixed(500), PanelExtent.flex(1)],
    children: [
      TabGroup(id: 'g', tabs: [for (var i = 0; i < n; i++) tab('t$i')]),
      SinglePanel(id: 'p', tab: tab('side')),
    ],
  );

  Future<void> pump(
    WidgetTester tester,
    PanelController c, {
    PanelTheme theme = const PanelTheme(),
    PanelTabStyle? Function(TabGroup)? tabStyleOf,
    PanelChrome chrome = const DefaultPanelChrome(),
    PanelDecorations decorations = const PanelDecorations(),
    PanelMenus? contextMenus = const PanelMenus(),
  }) async {
    tester.view.physicalSize = const Size(1000, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: PanelHost(
          controller: c,
          windowId: 'w',
          theme: theme,
          tabStyleOf: tabStyleOf,
          chrome: chrome,
          decorations: decorations,
          contextMenus: contextMenus,
          contentBuilder: (context, tab) => Focus(
            key: ValueKey('content:${tab.id}'),
            child: Text('body ${tab.id}'),
          ),
        ),
      ),
    );
  }

  Finder chip(String id) =>
      find.ancestor(of: find.text('T$id'), matching: find.byType(TabChip));

  ScrollController stripOf(WidgetTester tester) =>
      tester.widget<TabStrip>(find.byType(TabStrip)).scope.scrollController;

  group('styles', () {
    test('switching style drops a spec made for the old one', () {
      const custom = PanelTabStyleSpec(radius: 3);
      final theme = const PanelTheme(
        tabStyle: PanelTabStyle.floating,
      ).copyWith(tabStyleSpec: custom, stripHeight: 40);
      expect(theme.spec, custom);

      final blended = theme.withTabStyle(PanelTabStyle.blended);
      expect(
        blended.spec,
        PanelTabStyleSpec.blended,
        reason: "a floating pill's geometry would draw blended chips wrong",
      );
      expect(blended.stripHeight, 40, reason: 'everything else is kept');
    });

    for (final style in PanelTabStyle.values) {
      testWidgets('${style.name} draws every chip', (tester) async {
        final c = controller(manyTabs(3));
        await pump(tester, c, theme: PanelTheme(tabStyle: style));
        expect(find.byType(TabChip), findsNWidgets(3));
        final painted = find.descendant(
          of: find.byType(TabChip),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is BlendedChipPainter,
          ),
        );
        expect(
          painted,
          style == PanelTabStyle.blended ? findsNWidgets(3) : findsNothing,
          reason: 'only blended paints its shoulders',
        );
      });
    }

    testWidgets('tabStyleOf overrides the theme per group', (tester) async {
      final c = controller(manyTabs(2));
      await pump(
        tester,
        c,
        theme: const PanelTheme(tabStyle: PanelTabStyle.attached),
        tabStyleOf: (group) => PanelTabStyle.floating,
      );
      final strip = tester.widget<TabStrip>(find.byType(TabStrip));
      expect(strip.scope.theme.tabStyle, PanelTabStyle.floating);
      expect(
        strip.scope.theme.spec.gap,
        PanelTabStyleSpec.floating.gap,
        reason: 'the style brings its own geometry',
      );
    });

    test('the blended shape is closed between its two shoulders', () {
      const painter = BlendedChipPainter(
        fill: Colors.white,
        outline: null,
        separator: null,
        radius: 8,
        shoulder: 8,
      );
      final path = painter.shape(const Size(120, 30));
      final bounds = path.getBounds();
      expect(bounds.left, 0);
      expect(bounds.right, closeTo(120, 0.01));
      expect(bounds.top, closeTo(0, 0.01));
      expect(bounds.bottom, closeTo(30, 0.01));
      expect(path.contains(const Offset(60, 15)), isTrue);
      expect(
        path.contains(const Offset(2, 2)),
        isFalse,
        reason: 'the top-left is outside the shoulder and the corner',
      );
      expect(
        path.contains(const Offset(7, 29)),
        isTrue,
        reason: 'the fillet fills the corner between wall and floor',
      );
      expect(
        path.contains(const Offset(1, 29)),
        isFalse,
        reason: 'and is thin at the very edge, where it meets the floor',
      );
    });
  });

  group('shrink then scroll', () {
    testWidgets('chips share the strip down to the minimum', (tester) async {
      final c = controller(manyTabs(4));
      await pump(
        tester,
        c,
        theme: const PanelTheme(tabMinWidth: 80, tabMaxWidth: 200),
      );
      // 500 wide strip, four chips: 125 each, within the bounds.
      expect(tester.getSize(chip('t0')).width, closeTo(125, 0.5));
      expect(stripOf(tester).position.maxScrollExtent, 0);
    });

    testWidgets('past the minimum the strip scrolls instead', (tester) async {
      final c = controller(manyTabs(10));
      await pump(
        tester,
        c,
        theme: const PanelTheme(tabMinWidth: 80, tabMaxWidth: 200),
      );
      expect(tester.getSize(chip('t0')).width, 80);
      final position = stripOf(tester).position;
      expect(position.maxScrollExtent, closeTo(300, 0.5), reason: '800 - 500');
      expect(
        tester.getRect(chip('t9')).left,
        greaterThan(500),
        reason: 'the last chip lies beyond the strip until it scrolls',
      );
    });

    testWidgets('the wheel scrolls it, a strip drag still moves the group', (
      tester,
    ) async {
      final c = controller(manyTabs(10));
      await pump(tester, c);
      final position = stripOf(tester).position;
      final over = tester.getCenter(chip('t1'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: over);
      addTearDown(mouse.removePointer);
      await tester.sendEventToBinding(
        PointerScrollEvent(position: over, scrollDelta: const Offset(0, 120)),
      );
      await tester.pump();
      expect(position.pixels, 120);
      await tester.sendEventToBinding(
        PointerScrollEvent(position: over, scrollDelta: const Offset(0, 9999)),
      );
      await tester.pump();
      expect(position.pixels, position.maxScrollExtent, reason: 'clamped');

      // A pointer drag on the strip is never a scroll.
      final before = position.pixels;
      await tester.drag(find.byType(TabStrip), const Offset(-100, 0));
      await tester.pump();
      expect(position.pixels, before);
    });

    testWidgets('focus reveals a clipped chip, activation too', (tester) async {
      final c = controller(manyTabs(10));
      await pump(tester, c);
      final position = stripOf(tester).position;
      expect(position.pixels, 0);

      c.focus('t9');
      await tester.pump();
      await tester.pumpAndSettle();
      expect(position.pixels, position.maxScrollExtent);
      expect(tester.getRect(chip('t9')).right, closeTo(500, 0.5));

      c.activate('t0');
      await tester.pump();
      await tester.pumpAndSettle();
      expect(position.pixels, 0, reason: 'activating scrolls back too');
    });

    testWidgets('focus with keyboard gives the content the focus', (
      tester,
    ) async {
      final c = controller(manyTabs(3));
      await pump(tester, c);
      c.focus('t2', keyboard: true);
      await tester.pump();
      await tester.pump();
      final node = Focus.of(
        tester.element(find.text('body t2', skipOffstage: false)),
      );
      expect(node.hasFocus, isTrue);
      expect(
        Focus.of(
          tester.element(find.text('body t0', skipOffstage: false)),
        ).hasFocus,
        isFalse,
      );
    });
  });

  group('focused leaf', () {
    testWidgets('a pointer down in a panel focuses its leaf', (tester) async {
      final c = controller(manyTabs(2));
      expect(c.focusedLeaf('w')!.id, 'g');
      await pump(tester, c);
      await tester.tap(find.text('body side'));
      await tester.pump();
      expect(c.focusedLeaf('w')!.id, 'p');
    });

    testWidgets('the strip and header know whether they are focused', (
      tester,
    ) async {
      final c = controller(manyTabs(2), focused: 'p');
      await pump(tester, c);
      expect(
        tester.widget<TabStrip>(find.byType(TabStrip)).scope.focused,
        isFalse,
      );
      expect(
        tester.widget<PanelHeader>(find.byType(PanelHeader)).scope.focused,
        isTrue,
      );
    });
  });

  group('decorations', () {
    testWidgets('leading, trailing and strip trailing are placed', (
      tester,
    ) async {
      final c = controller(manyTabs(2));
      await pump(
        tester,
        c,
        decorations: PanelDecorations(
          tabLeading: (context, tab) =>
              Icon(Icons.circle, key: ValueKey('lead:${tab.id}')),
          tabTrailing: (context, tab) => tab.id == 't0'
              ? const Icon(Icons.brightness_1, key: ValueKey('dirty'))
              : null,
          stripTrailing: (context, group) =>
              const Icon(Icons.add, key: ValueKey('plus')),
        ),
      );
      expect(find.byKey(const ValueKey('lead:t0')), findsOneWidget);
      expect(find.byKey(const ValueKey('plus')), findsOneWidget);
      expect(find.byKey(const ValueKey('dirty')), findsOneWidget);
      // The dirty dot took the close glyph's place on t0 and only there.
      expect(
        find.descendant(of: chip('t0'), matching: find.byType(CloseGlyph)),
        findsNothing,
      );
      expect(
        find.descendant(of: chip('t1'), matching: find.byType(CloseGlyph)),
        findsOneWidget,
      );
    });

    testWidgets('an unclosable tab draws no glyph and wrapTab wraps the chip', (
      tester,
    ) async {
      final c = controller(manyTabs(2));
      c.updateTab('t0', (tab) => tab.copyWith(closable: false));
      await pump(
        tester,
        c,
        decorations: PanelDecorations(
          wrapTab: (context, tab, chip) =>
              Tooltip(message: 'tip ${tab.id}', child: chip),
        ),
      );
      expect(
        find.descendant(of: chip('t0'), matching: find.byType(CloseGlyph)),
        findsNothing,
      );
      expect(
        find.descendant(of: chip('t1'), matching: find.byType(CloseGlyph)),
        findsOneWidget,
      );
      expect(
        find.ancestor(of: chip('t1'), matching: find.byTooltip('tip t1')),
        findsOneWidget,
      );
      // Wrapped chips are still drop targets: t1 dragged before t0 reorders.
      final gesture = await tester.startGesture(tester.getCenter(chip('t1')));
      await tester.pump();
      await gesture.moveTo(tester.getTopLeft(chip('t0')) + const Offset(4, 10));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect((c.rootOf('w')!.find('g') as TabGroup).tabs.map((t) => t.id), [
        't1',
        't0',
      ]);
    });

    testWidgets(
      'a right click reaches the menu builder with the position, a middle '
      'click closes',
      (tester) async {
        final c = controller(manyTabs(2));
        PanelTab? clicked;
        Offset? at;
        await pump(
          tester,
          c,
          // The way a host opens a menu of its own: take the click, show
          // nothing of the package's.
          contextMenus: PanelMenus(
            build: (request, defaults) {
              if (request.target case PanelMenuTabTarget(:final tab)) {
                clicked = tab;
              }
              at = request.globalPosition;
              return const [];
            },
          ),
        );
        final where = tester.getCenter(chip('t1'));

        await tester.tapAt(where, buttons: kSecondaryButton);
        await tester.pump();
        expect(clicked?.id, 't1');
        expect(at, where);

        await tester.tapAt(where, buttons: kTertiaryButton);
        await tester.pump();
        expect(c.tab('t1'), isNull);
      },
    );
  });

  group('custom chrome', () {
    testWidgets('chips wrapped in tabSlot are drop targets', (tester) async {
      final c = controller(manyTabs(2));
      await pump(tester, c, chrome: const _BareChrome());
      expect(find.byType(TabStrip), findsNothing);
      expect(find.text('bare Tt0'), findsOneWidget);

      // Drag the single panel's header onto the left half of the first bare
      // chip: the slot says "before index 0".
      final target = tester.getRect(find.text('bare Tt0'));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('bare Tside')),
      );
      await gesture.moveBy(const Offset(-30, 0));
      await gesture.moveTo(Offset(target.left + 2, target.center.dy));
      await tester.pump();
      expect(c.drag?.candidate?.target, const DockTarget.join('g', index: 0));
      await gesture.up();
      await tester.pump();
      expect((c.rootOf('w')!.find('g') as TabGroup).tabs.map((t) => t.id), [
        'side',
        't0',
        't1',
      ]);
    });
  });
}

/// The least a chrome can be: text per chip, text per header, a box for a
/// divider, and the slot wrappers — which is all docking needs.
final class _BareChrome extends PanelChrome {
  const _BareChrome();

  @override
  Widget buildStrip(BuildContext context, StripScope scope) => scope.stripSlot(
    SizedBox(
      height: scope.theme.stripHeight,
      child: Row(
        children: [
          for (var i = 0; i < scope.group.tabs.length; i++)
            scope.tabSlot(
              i,
              GestureDetector(
                onPanStart: (d) => scope.callbacks.onDragTabStart(
                  scope.group.tabs[i].id,
                  d.globalPosition,
                ),
                onPanUpdate: (d) =>
                    scope.callbacks.onDragUpdate(d.globalPosition),
                onPanEnd: (_) => scope.callbacks.onDragEnd(),
                child: SizedBox(
                  width: 100,
                  child: Text('bare ${scope.titleOf(scope.group.tabs[i])}'),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  @override
  Widget buildHeader(BuildContext context, HeaderScope scope) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) =>
            scope.callbacks.onDragLeafStart(scope.panel.id, d.globalPosition),
        onPanUpdate: (d) => scope.callbacks.onDragUpdate(d.globalPosition),
        onPanEnd: (_) => scope.callbacks.onDragEnd(),
        child: SizedBox(
          height: scope.theme.headerHeight,
          child: Text('bare ${scope.titleOf(scope.panel.tab)}'),
        ),
      );

  @override
  Widget buildDivider(BuildContext context, DividerScope scope) =>
      const ColoredBox(color: Colors.grey);

  @override
  Widget buildDropPreview(BuildContext context, PanelTheme theme) =>
      const ColoredBox(color: Colors.blue);
}
