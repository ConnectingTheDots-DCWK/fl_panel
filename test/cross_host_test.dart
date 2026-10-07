import 'package:fl_panel/fl_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two hosts of one controller: a drag that starts in one and ends in the
/// other, and the rules that keep a tab's content built exactly once.
void main() {
  PanelTab tab(String id) =>
      PanelTab(id: id, contentId: id, metadata: {'title': id.toUpperCase()});

  /// `main` is [ A(a, a2) | B(b) ]; `side` is a drawer's one group, D(d, d2).
  PanelController controller({
    DockPolicy policy = DockPolicy.permissive,
    bool emptySide = false,
    VoidCallback? onSettled,
  }) {
    final controller = PanelController(
      workspace: PanelWorkspace(
        windows: [
          PanelWindow(
            id: 'main',
            root: SplitNode(
              id: 'top',
              axis: PanelAxis.horizontal,
              children: [
                TabGroup(id: 'left', tabs: [tab('a'), tab('a2')]),
                TabGroup(id: 'right', tabs: [tab('b')]),
              ],
            ),
          ),
          PanelWindow(
            id: 'side',
            root: emptySide
                ? null
                : TabGroup(id: 'drawer', tabs: [tab('d'), tab('d2')]),
          ),
        ],
      ),
      policy: policy,
      onSettled: onSettled,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  Widget host(PanelController c, String windowId) => PanelHost(
    controller: c,
    windowId: windowId,
    contentBuilder: (context, tab) => _Counter(key: ValueKey(tab.id)),
    emptyBuilder: (context) => const SizedBox.expand(key: ValueKey('empty')),
  );

  Future<void> pumpApp(WidgetTester tester, Widget body) async {
    tester.view.physicalSize = const Size(1200, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: body));
  }

  /// The drawer on the left, 400 wide, the dock beside it.
  Future<void> pumpSideBySide(
    WidgetTester tester,
    PanelController c, {
    ValueNotifier<bool>? sideIgnoresPointer,
    ValueNotifier<bool>? sideShown,
  }) => pumpApp(
    tester,
    Row(
      children: [
        SizedBox(
          width: 400,
          child: ListenableBuilder(
            listenable: Listenable.merge([sideIgnoresPointer, sideShown]),
            builder: (context, _) => (sideShown?.value ?? true)
                ? IgnorePointer(
                    ignoring: sideIgnoresPointer?.value ?? false,
                    child: host(c, 'side'),
                  )
                : const SizedBox.expand(),
          ),
        ),
        Expanded(child: host(c, 'main')),
      ],
    ),
  );

  Finder chip(String title) => find.descendant(
    of: find.byType(TabChip),
    matching: find.text(title.toUpperCase()),
  );

  Finder hostOf(String windowId) => find.byWidgetPredicate(
    (widget) => widget is PanelHost && widget.windowId == windowId,
  );

  List<String> tabsOf(PanelController c, String windowId, String leafId) => [
    for (final t in c.rootOf(windowId)!.find(leafId)!.tabs) t.id,
  ];

  Future<TestGesture> grab(WidgetTester tester, Finder handle) async {
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(30, 30)); // past the pan slop
    await tester.pump();
    return gesture;
  }

  testWidgets('a chip dragged into another host joins the leaf it is over', (
    tester,
  ) async {
    final c = controller();
    await pumpSideBySide(tester, c);

    final gesture = await grab(tester, chip('d'));
    await gesture.moveTo(tester.getCenter(find.byKey(const ValueKey('b'))));
    await tester.pump();
    expect(c.drag?.targetWindowId, 'main');
    expect(c.drag?.candidate?.target, const DockTarget.join('right'));
    expect(
      find.descendant(
        of: hostOf('main'),
        matching: find.byKey(const ValueKey('fl_panel.preview')),
      ),
      findsOneWidget,
      reason: 'the host the drop lands in shades it',
    );
    expect(
      find.byKey(const ValueKey('fl_panel.preview')),
      findsOneWidget,
      reason: 'and the host the drag started in does not',
    );

    await gesture.up();
    await tester.pump();
    expect(c.drag, isNull);
    expect(tabsOf(c, 'main', 'right'), ['b', 'd']);
    expect(tabsOf(c, 'side', 'drawer'), ['d2']);
  });

  testWidgets('content keeps its state when its tab moves to another host', (
    tester,
  ) async {
    final c = controller();
    await pumpSideBySide(tester, c);
    await tester.tap(find.byKey(const ValueKey('d')));
    await tester.tap(find.byKey(const ValueKey('d')));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);

    final gesture = await grab(tester, chip('d'));
    await gesture.moveTo(tester.getCenter(find.byKey(const ValueKey('b'))));
    await gesture.up();
    await tester.pump();

    expect(tabsOf(c, 'main', 'right'), ['b', 'd']);
    expect(
      find.descendant(of: hostOf('main'), matching: find.text('2')),
      findsOneWidget,
      reason:
          'the element was carried from one host\'s Stack to the other\'s, '
          'both built inside a LayoutBuilder, not built anew at zero',
    );
  });

  testWidgets('a whole panel dragged into another host keeps its id', (
    tester,
  ) async {
    final c = controller();
    c.setRoot('side', SinglePanel(id: 'tool', tab: tab('t')));
    await pumpSideBySide(tester, c);

    final gesture = await grab(tester, find.byType(PanelHeader));
    final b = tester.getRect(find.byKey(const ValueKey('b')));
    // Toward B's right edge, outside its centre: a split, not a join.
    await gesture.moveTo(Offset(b.right - 60, b.center.dy));
    await gesture.up();
    await tester.pump();

    expect(c.rootOf('side'), isNull, reason: 'the drawer was emptied');
    expect(
      c.rootOf('main')!.find('tool'),
      isA<SinglePanel>(),
      reason: 'a moved leaf keeps its id and its form in another window too',
    );
  });

  testWidgets('a window with no tree takes a drop as its root', (tester) async {
    final c = controller(emptySide: true);
    await pumpSideBySide(tester, c);
    expect(find.byKey(const ValueKey('empty')), findsOneWidget);

    final gesture = await grab(tester, chip('b'));
    await gesture.moveTo(const Offset(200, 300));
    await tester.pump();
    expect(c.drag?.targetWindowId, 'side');
    expect(
      find.descendant(
        of: hostOf('side'),
        matching: find.byKey(const ValueKey('fl_panel.preview')),
      ),
      findsOneWidget,
    );

    await gesture.up();
    await tester.pump();
    expect(c.rootOf('side')!.tabs.map((t) => t.id), ['b']);
    expect(c.rootOf('main')!.tabs.map((t) => t.id), ['a', 'a2']);
  });

  testWidgets('the host drawn on top takes the drop where it covers another', (
    tester,
  ) async {
    final c = controller();
    // The drawer laid over the left of the dock, as a slide-over is.
    await pumpApp(
      tester,
      Stack(
        children: [
          Positioned.fill(child: host(c, 'main')),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 400,
            child: host(c, 'side'),
          ),
        ],
      ),
    );

    final gesture = await grab(tester, chip('b'));
    // Over the drawer's content, and over the dock's left group beneath it.
    await gesture.moveTo(const Offset(200, 300));
    await tester.pump();
    expect(c.drag?.targetWindowId, 'side');
    expect(c.drag?.candidate?.target, const DockTarget.join('drawer'));

    await gesture.up();
    await tester.pump();
    expect(tabsOf(c, 'side', 'drawer'), ['d', 'd2', 'b']);
  });

  testWidgets('a source host that stops taking pointers still drops', (
    tester,
  ) async {
    final c = controller();
    final ignoring = ValueNotifier(false);
    addTearDown(ignoring.dispose);
    await pumpSideBySide(tester, c, sideIgnoresPointer: ignoring);

    final gesture = await grab(tester, chip('d'));
    // What a drawer does when the drag leaves it: it gets out of the way,
    // and stays mounted.
    ignoring.value = true;
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byKey(const ValueKey('b'))));
    await gesture.up();
    await tester.pump();

    expect(tabsOf(c, 'main', 'right'), ['b', 'd']);
  });

  testWidgets('a source host removed mid-drag cancels the drag', (
    tester,
  ) async {
    final c = controller();
    final shown = ValueNotifier(true);
    addTearDown(shown.dispose);
    await pumpSideBySide(tester, c, sideShown: shown);

    final gesture = await grab(tester, chip('d'));
    expect(c.drag, isNotNull);
    shown.value = false;
    await tester.pump();
    await tester.pump();
    expect(
      c.drag,
      isNull,
      reason:
          'the gesture died with the host, and a drag nothing can end would '
          'shade a drop forever',
    );

    await gesture.moveTo(tester.getCenter(find.byKey(const ValueKey('b'))));
    await gesture.up();
    await tester.pump();
    expect(tabsOf(c, 'side', 'drawer'), ['d', 'd2']);
    expect(tabsOf(c, 'main', 'right'), ['b']);
  });

  testWidgets('a move the policy refuses lights nothing up', (tester) async {
    final c = controller(policy: const _DrawerKeepsItsOwn());
    await pumpSideBySide(tester, c);

    final gesture = await grab(tester, chip('d'));
    await gesture.moveTo(tester.getCenter(find.byKey(const ValueKey('b'))));
    await tester.pump();
    expect(c.drag?.candidate, isNull);
    expect(find.byKey(const ValueKey('fl_panel.preview')), findsNothing);

    await gesture.up();
    await tester.pump();
    expect(tabsOf(c, 'side', 'drawer'), ['d', 'd2']);
  });

  testWidgets('two hosts showing one window are reported', (tester) async {
    final c = controller(emptySide: true);
    await pumpApp(
      tester,
      Row(
        children: [
          Expanded(child: host(c, 'side')),
          Expanded(child: host(c, 'side')),
        ],
      ),
    );
    final error = tester.takeException();
    expect(error, isA<FlutterError>());
    expect('$error', contains('Window "side" is shown by 2 PanelHosts'));
  });

  testWidgets('a host replaced in one rebuild is not two hosts', (
    tester,
  ) async {
    final c = controller();
    await pumpApp(
      tester,
      KeyedSubtree(key: const ValueKey(1), child: host(c, 'main')),
    );
    // A different key: the old host is unmounted and a new one mounted in
    // the same frame, the new one first.
    await pumpApp(
      tester,
      KeyedSubtree(key: const ValueKey(2), child: host(c, 'main')),
    );
    expect(tester.takeException(), isNull);
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

/// The drawer's tools stay in the drawer.
final class _DrawerKeepsItsOwn extends DockPolicy {
  const _DrawerKeepsItsOwn();

  @override
  bool canMoveBetween(
    PanelTab moving,
    String fromWindowId,
    String toWindowId,
  ) => fromWindowId != 'side';
}
