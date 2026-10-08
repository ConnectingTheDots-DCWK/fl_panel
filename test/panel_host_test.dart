import 'package:fl_panel/fl_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PanelTab tab(String id) =>
      PanelTab(id: id, contentId: id, metadata: {'title': id.toUpperCase()});

  /// [ A | B ] over C, with A and B tabbed and C a single panel.
  SplitNode tree() => SplitNode(
    id: 'root',
    axis: PanelAxis.vertical,
    children: [
      SplitNode(
        id: 'top',
        axis: PanelAxis.horizontal,
        children: [
          TabGroup(id: 'left', tabs: [tab('a'), tab('a2')]),
          TabGroup(id: 'right', tabs: [tab('b')]),
        ],
      ),
      SinglePanel(id: 'bottom', tab: tab('c')),
    ],
  );

  PanelController controller({VoidCallback? onSettled}) {
    final controller = PanelController(
      workspace: PanelWorkspace(
        windows: [PanelWindow(id: 'main', root: tree())],
      ),
      onSettled: onSettled,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  Future<void> pump(WidgetTester tester, PanelController controller) async {
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: PanelHost(
          controller: controller,
          windowId: 'main',
          contentBuilder: (context, tab) => _Counter(key: ValueKey(tab.id)),
        ),
      ),
    );
  }

  Finder chip(String title) => find.descendant(
    of: find.byType(TabChip),
    matching: find.text(title.toUpperCase()),
  );

  LayoutNode root(PanelController c) => c.rootOf('main')!;

  testWidgets('content keeps its state when its tab moves groups', (
    tester,
  ) async {
    final c = controller();
    await pump(tester, c);
    await tester.tap(find.byKey(const ValueKey('a')));
    await tester.tap(find.byKey(const ValueKey('a')));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);

    c.dock('main', const DockSource.tab('a'), const DockTarget.join('right'));
    await tester.pump();

    final right = root(c).find('right') as TabGroup;
    expect(right.tabs.map((t) => t.id), ['b', 'a']);
    expect(right.activeTab!.id, 'a');
    expect(
      find.text('2'),
      findsOneWidget,
      reason:
          'the same element was repositioned, not rebuilt: the counter lives',
    );
  });

  testWidgets('an inactive tab stays built offstage', (tester) async {
    final c = controller();
    await pump(tester, c);
    expect(
      find.byKey(const ValueKey('a2'), skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('a2')), findsNothing);
    await tester.tap(chip('a2'));
    await tester.pump();
    expect(find.byKey(const ValueKey('a2')), findsOneWidget);
  });

  testWidgets('dragging a divider resizes and settles once', (tester) async {
    var settled = 0;
    final c = controller(onSettled: () => settled++);
    await pump(tester, c);

    final before = tester.getRect(find.byKey(const ValueKey('b')));
    final divider = find.byKey(const ValueKey('fl_panel.divider.top.0'));
    await tester.drag(divider, const Offset(100, 0));
    await tester.pump();
    final after = tester.getRect(find.byKey(const ValueKey('b')));

    expect(after.left - before.left, closeTo(100, 1));
    expect(after.right, before.right, reason: 'the far edge does not move');
    expect(settled, 1, reason: 'live frames do not settle; the release does');
  });

  testWidgets('a chip dragged to another leaf\'s centre joins it', (
    tester,
  ) async {
    final c = controller();
    await pump(tester, c);

    final target = tester.getCenter(find.byKey(const ValueKey('b')));
    final gesture = await tester.startGesture(tester.getCenter(chip('a')));
    await gesture.moveBy(const Offset(30, 30)); // past the pan slop
    await gesture.moveTo(target);
    await tester.pump();
    expect(c.drag?.candidate?.target, const DockTarget.join('right'));
    expect(
      find.byKey(const ValueKey('fl_panel.preview')),
      findsOneWidget,
      reason: 'the overlay shades the target',
    );

    await gesture.up();
    await tester.pump();
    expect(c.drag, isNull);
    expect((root(c).find('right') as TabGroup).tabs.map((t) => t.id), [
      'b',
      'a',
    ]);
    expect((root(c).find('left') as TabGroup).tabs.map((t) => t.id), ['a2']);
  });

  testWidgets('a chip dragged onto a strip lands at that index', (
    tester,
  ) async {
    final c = controller();
    await pump(tester, c);

    // Onto the left half of A's chip: before A.
    final aChip = tester.getRect(chip('a'));
    final gesture = await tester.startGesture(tester.getCenter(chip('b')));
    await gesture.moveBy(const Offset(-30, 0));
    await gesture.moveTo(Offset(aChip.left + 2, aChip.center.dy));
    await tester.pump();
    expect(c.drag?.candidate?.target, const DockTarget.join('left', index: 0));
    await gesture.up();
    await tester.pump();

    expect((root(c).find('left') as TabGroup).tabs.map((t) => t.id), [
      'b',
      'a',
      'a2',
    ]);
    expect(
      root(c).find('right'),
      isNull,
      reason: 'the emptied group is gone and the row collapsed',
    );
  });

  testWidgets('a chip dragged along its own strip reorders it as it goes', (
    tester,
  ) async {
    final c = controller();
    await pump(tester, c);
    // The whole chip, not its title: how far into a chip the pointer is
    // is what this test is about.
    Rect at(String title) => tester.getRect(
      find.ancestor(of: chip(title), matching: find.byType(TabChip)),
    );
    final preview = find.byKey(const ValueKey('fl_panel.preview'));
    final first = at('a');
    final second = at('a2');
    Future<void> settle() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    final gesture = await tester.startGesture(first.center);
    await gesture.moveBy(const Offset(30, 0));

    // A fifth of the way into A2 is not yet past it…
    await gesture.moveTo(
      Offset(second.left + second.width * 0.2, second.center.dy),
    );
    await settle();
    expect(c.drag?.candidate, isNull);

    // …a third of the way is: the strip answers before the midpoint, and the
    // chips trade places under the pointer before anything is dropped.
    await gesture.moveTo(
      Offset(second.left + second.width * 0.3, second.center.dy),
    );
    await settle();
    expect(c.drag?.candidate?.target, const DockTarget.join('left', index: 2));
    expect(at('a').left, greaterThan(at('a2').left));
    expect(
      preview,
      findsNothing,
      reason: 'the chips are the preview; nothing shades the panel',
    );

    // Back into A2, now on the left, but not a quarter of the way: the order
    // holds, so it cannot flicker at the boundary it just crossed.
    await gesture.moveTo(
      Offset(first.left + first.width * 0.85, first.center.dy),
    );
    await settle();
    expect(
      c.drag?.candidate?.target,
      const DockTarget.join('left', index: 2),
      reason: 'a strip hit is measured against the order it was drawn in',
    );

    // A quarter of the way back is: A returns to its own slot, a no-op.
    await gesture.moveTo(
      Offset(first.left + first.width * 0.7, first.center.dy),
    );
    await settle();
    expect(c.drag?.candidate, isNull);
    expect(at('a').left, lessThan(at('a2').left));

    await gesture.moveTo(
      Offset(second.left + second.width * 0.5, second.center.dy),
    );
    await settle();
    await gesture.up();
    await tester.pump();
    final left = root(c).find('left') as TabGroup;
    expect(left.tabs.map((t) => t.id), ['a2', 'a']);
    expect(left.activeTab!.id, 'a');
  });

  testWidgets('a panel header dragged to an edge splits as a single panel', (
    tester,
  ) async {
    final c = controller();
    await pump(tester, c);

    final b = tester.getRect(find.byKey(const ValueKey('b')));
    final header = find.byType(PanelHeader);
    final gesture = await tester.startGesture(tester.getCenter(header));
    await gesture.moveBy(const Offset(0, -30));
    await gesture.moveTo(Offset(b.left + 10, b.center.dy));
    await tester.pump();
    expect(
      c.drag?.candidate?.target,
      const DockTarget.split('right', DockSide.left, form: SurfaceForm.single),
      reason: 'a single panel stays single when it can',
    );
    await gesture.up();
    await tester.pump();

    final top = root(c) as SplitNode;
    expect(top.axis, PanelAxis.horizontal, reason: 'the outer split is gone');
    expect(
      top.children.map((n) => n.id),
      ['left', 'bottom', 'right'],
      reason: 'a same-axis insert joins the row rather than nesting',
    );
    expect(top.children[1], isA<SinglePanel>());
  });

  testWidgets('a refused drop lights nothing up and changes nothing', (
    tester,
  ) async {
    final c = controller();
    c.policy = const _NothingJoins();
    await pump(tester, c);
    final before = root(c);

    final gesture = await tester.startGesture(tester.getCenter(chip('a')));
    await gesture.moveBy(const Offset(30, 30));
    await gesture.moveTo(tester.getCenter(find.byKey(const ValueKey('b'))));
    await tester.pump();
    expect(c.drag, isNotNull);
    expect(c.drag!.candidate, isNull);
    expect(find.byKey(const ValueKey('fl_panel.preview')), findsNothing);
    await gesture.up();
    await tester.pump();
    expect(root(c), before);
  });

  testWidgets(
    'an empty persistent group draws its placeholder and takes a drop',
    (tester) async {
      final c = PanelController(
        workspace: PanelWorkspace(
          windows: [
            PanelWindow(
              id: 'main',
              root: SplitNode(
                id: 'root',
                axis: PanelAxis.horizontal,
                children: [
                  TabGroup(id: 'tools', tabs: [tab('a')]),
                  TabGroup(id: 'editors', tabs: const [], persistent: true),
                ],
              ),
            ),
          ],
        ),
      );
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(1000, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: PanelHost(
            controller: c,
            windowId: 'main',
            contentBuilder: (context, tab) => _Counter(key: ValueKey(tab.id)),
            emptyLeafBuilder: (context, group) =>
                Text('nothing open', key: ValueKey('empty:${group.id}')),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('empty:editors')), findsOneWidget);
      expect(
        find.byType(TabStrip),
        findsNWidgets(2),
        reason: 'its strip stays',
      );

      // Clicking the placeholder focuses the group, the way content does.
      await tester.tap(find.byKey(const ValueKey('empty:editors')));
      await tester.pump();
      expect(c.focusedLeaf('main')!.id, 'editors');

      // Dragging the only tab onto the empty strip fills it and empties the
      // other group, which is not persistent and goes.
      final strips = find.byType(TabStrip);
      final gesture = await tester.startGesture(tester.getCenter(chip('a')));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(strips.at(1)));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      final editors = root(c) as TabGroup;
      expect(editors.id, 'editors');
      expect(editors.activeTab!.id, 'a');
      expect(find.byKey(const ValueKey('empty:editors')), findsNothing);
    },
  );

  testWidgets('closing tabs collapses the tree down to nothing', (
    tester,
  ) async {
    final c = controller();
    await pump(tester, c);
    for (final id in ['a', 'a2', 'b']) {
      c.close(id);
    }
    await tester.pump();
    expect(root(c), isA<SinglePanel>());
    expect(find.byType(DividerHandle), findsNothing);
    c.close('c');
    await tester.pump();
    expect(c.rootOf('main'), isNull);
    expect(find.byType(PanelHeader), findsNothing);
  });
}

class _Counter extends StatefulWidget {
  const _Counter({super.key});

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => count++),
    child: Center(child: Text('$count')),
  );
}

final class _NothingJoins extends DockPolicy {
  const _NothingJoins();

  @override
  bool canJoin(PanelTab moving, LeafNode target) => false;
}
