import 'package:fl_panel/fl_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [PanelHost.solo]: one leaf over the whole host, as a way of showing the
/// layout and never an edit to it.
void main() {
  PanelTab tab(String id) =>
      PanelTab(id: id, contentId: id, metadata: {'title': id.toUpperCase()});

  /// [ A | B ] over C, with A and B tabbed and C a single panel.
  PanelController controller() {
    final controller = PanelController(
      workspace: PanelWorkspace(
        windows: [
          PanelWindow(
            id: 'main',
            root: SplitNode(
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
            ),
          ),
        ],
      ),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  Future<void> pump(
    WidgetTester tester,
    PanelController controller,
    PanelSolo? solo,
  ) async {
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: PanelHost(
          controller: controller,
          windowId: 'main',
          solo: solo,
          contentBuilder: (context, tab) => _Counter(key: ValueKey(tab.id)),
        ),
      ),
    );
  }

  Finder chip(String title) => find.descendant(
    of: find.byType(TabChip),
    matching: find.text(title.toUpperCase()),
  );
  Finder content(String id) => find.byKey(ValueKey(id));

  testWidgets('a solo leaf without chrome has the host, and the rest wait', (
    tester,
  ) async {
    final c = controller();
    await pump(tester, c, null);
    await tester.tap(content('a'));
    await tester.tap(content('a'));
    await tester.pump();
    final workspace = c.workspace;

    await pump(tester, c, const PanelSolo('left', chrome: false));
    expect(
      tester.getRect(content('a')),
      const Rect.fromLTWH(0, 0, 1000, 600),
      reason: 'no strip: the content takes the whole host',
    );
    expect(find.byType(TabChip), findsNothing);
    expect(
      find.byKey(const ValueKey('fl_panel.divider.top.0')),
      findsNothing,
      reason: 'no divider can be dragged while one leaf is shown',
    );
    expect(content('b'), findsNothing);
    expect(
      find.byKey(const ValueKey('b'), skipOffstage: false),
      findsOneWidget,
      reason: 'every other tab stays built, offstage',
    );
    expect(find.text('2'), findsOneWidget, reason: 'the counter lived');

    // Solo moves to another leaf, then away; nothing is rebuilt.
    await pump(tester, c, const PanelSolo('right', chrome: false));
    expect(tester.getRect(content('b')), const Rect.fromLTWH(0, 0, 1000, 600));
    expect(content('a'), findsNothing);
    await pump(tester, c, null);
    expect(find.text('2'), findsOneWidget, reason: 'and lives on after');
    expect(chip('b'), findsOneWidget);
    expect(
      c.workspace,
      same(workspace),
      reason: 'a way of showing the layout, never an edit to it',
    );
  });

  testWidgets('a solo leaf with chrome keeps its own strip and no other', (
    tester,
  ) async {
    final c = controller();
    await pump(tester, c, const PanelSolo('left'));
    expect(chip('a'), findsOneWidget);
    expect(chip('a2'), findsOneWidget);
    expect(chip('b'), findsNothing);
    final rect = tester.getRect(content('a'));
    expect(rect.width, 1000);
    expect(rect.bottom, 600);
    expect(rect.top, greaterThan(0), reason: 'below the strip');

    await tester.tap(chip('a2'));
    await tester.pump();
    expect(content('a2'), findsOneWidget, reason: 'the strip still works');
  });

  testWidgets('a solo host offers no drop', (tester) async {
    final c = controller();
    await pump(tester, c, const PanelSolo('left'));
    final gesture = await tester.startGesture(tester.getCenter(chip('a2')));
    await gesture.moveBy(const Offset(30, 30));
    // Where the right group is in the layout, hidden under the solo leaf.
    await gesture.moveTo(const Offset(750, 150));
    await tester.pump();
    expect(c.drag?.candidate, isNull);
    expect(find.byKey(const ValueKey('fl_panel.preview')), findsNothing);
    await gesture.up();
    await tester.pump();
    expect((c.rootOf('main')!.find('left') as TabGroup).tabs.length, 2);
  });

  testWidgets('a leaf the window does not hold shows the layout', (
    tester,
  ) async {
    final c = controller();
    await pump(tester, c, const PanelSolo('gone', chrome: false));
    expect(chip('a'), findsOneWidget);
    expect(chip('b'), findsOneWidget);
    expect(content('c'), findsOneWidget);
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
