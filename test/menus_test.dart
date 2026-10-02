import 'package:fl_panel/fl_panel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PanelTab tab(String id, {bool closable = true}) => PanelTab(
    id: id,
    contentId: id,
    metadata: {'title': 'T$id'},
    closable: closable,
  );

  /// [ tools(files) | editors(a, b) ], sized 300 : 700.
  LayoutNode tree() => SplitNode(
    id: 'root',
    axis: PanelAxis.horizontal,
    sizes: const [PanelExtent.flex(3), PanelExtent.flex(7)],
    children: [
      SinglePanel(id: 'tools', tab: tab('files', closable: false)),
      TabGroup(id: 'editors', tabs: [tab('a'), tab('b')]),
    ],
  );

  PanelController controller() {
    final c = PanelController(
      workspace: PanelWorkspace(
        windows: [PanelWindow(id: 'w', root: tree())],
      ),
    );
    addTearDown(c.dispose);
    return c;
  }

  PanelMenuRequest request(PanelController c, PanelMenuTarget target) =>
      PanelMenuRequest(
        controller: c,
        windowId: 'w',
        target: target,
        globalPosition: Offset.zero,
      );

  PanelMenuEntry entry(List<PanelMenuEntry> entries, String label) =>
      entries.firstWhere((e) => e.label == label);

  group('default entries', () {
    test('a chip offers the close verbs and a split, greyed as they apply', () {
      final c = controller();
      final editors = c.rootOf('w')!.find('editors') as TabGroup;
      final entries = PanelMenus.defaultEntries(
        request(c, PanelMenuTabTarget(editors.tabs.last, editors)),
      );
      expect(entry(entries, 'Close').isEnabled, isTrue);
      expect(entry(entries, 'Close others').isEnabled, isTrue);
      expect(
        entry(entries, 'Close to the right').isEnabled,
        isFalse,
        reason: 'b is the last chip',
      );
      final split = entry(entries, 'Split');
      expect(split.isSubmenu, isTrue);
      expect(split.children.map((e) => e.label), [
        'Left',
        'Top',
        'Right',
        'Bottom',
      ]);
      expect(split.isEnabled, isTrue);
      split.children.first.onSelected!();
      expect(
        c.rootOf('w')!.leafOf('b')!.id,
        isNot('editors'),
        reason: 'b went into a leaf of its own on the left',
      );
    });

    test('an unclosable panel header greys Close and still offers a move', () {
      final c = controller();
      final tools = c.rootOf('w')!.find('tools') as SinglePanel;
      final entries = PanelMenus.defaultEntries(
        request(c, PanelMenuHeaderTarget(tools)),
      );
      expect(entry(entries, 'Close').isEnabled, isFalse);
      final move = entry(entries, 'Move to edge');
      expect(
        entry(move.children, 'Left').isEnabled,
        isFalse,
        reason: 'it is there',
      );
      expect(entry(move.children, 'Bottom').isEnabled, isTrue);
      entry(move.children, 'Bottom').onSelected!();
      final root = c.rootOf('w') as SplitNode;
      expect(root.axis, PanelAxis.vertical);
      expect(root.children.last.id, 'tools');
      expect(root.children.last, isA<SinglePanel>(), reason: 'form kept');
    });

    test('a divider offers equalise and a swap', () {
      final c = controller();
      final divider = const PanelSolver()
          .layout(c.rootOf('w'), const PanelRect(0, 0, 1000, 400))
          .dividers
          .single;
      var entries = PanelMenus.defaultEntries(
        request(c, PanelMenuDividerTarget(divider)),
      );
      entry(entries, 'Equalise').onSelected!();
      expect(
        (c.rootOf('w') as SplitNode).sizes,
        everyElement(const PanelExtent.flex()),
      );
      entries = PanelMenus.defaultEntries(
        request(c, PanelMenuDividerTarget(divider)),
      );
      expect(entry(entries, 'Equalise').isEnabled, isFalse, reason: 'already');
      entry(entries, 'Swap left and right').onSelected!();
      expect((c.rootOf('w') as SplitNode).children.map((n) => n.id), [
        'editors',
        'tools',
      ]);
    });

    test('the build hook sees the defaults and has the last word', () {
      final c = controller();
      final editors = c.rootOf('w')!.find('editors') as TabGroup;
      var seen = 0;
      final menus = PanelMenus(
        build: (request, defaults) {
          seen = defaults.length;
          return [const PanelMenuEntry(label: 'Mine')];
        },
      );
      final entries = menus.entriesFor(
        request(c, PanelMenuStripTarget(editors)),
      );
      expect(seen, greaterThan(0));
      expect(entries.map((e) => e.label), ['Mine']);
    });
  });

  group('on screen', () {
    Future<void> pump(
      WidgetTester tester,
      PanelController c, {
      PanelMenus? menus = const PanelMenus(),
    }) async {
      tester.view.physicalSize = const Size(1000, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: PanelHost(
            controller: c,
            windowId: 'w',
            contextMenus: menus,
            contentBuilder: (context, tab) => Text('body ${tab.id}'),
          ),
        ),
      );
    }

    testWidgets('a right click on a strip opens its menu, and a choice acts', (
      tester,
    ) async {
      final c = controller();
      await pump(tester, c);
      final strip = tester.getRect(find.byType(TabStrip));
      // The background, past the two chips.
      await tester.tapAt(
        Offset(strip.right - 8, strip.center.dy),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Close all'), findsOneWidget);
      await tester.tap(find.text('Close all'));
      await tester.pumpAndSettle();
      expect(c.rootOf('w')!.find('editors'), isNull);
      expect(find.text('Close all'), findsNothing, reason: 'closed after');
    });

    testWidgets('a right click on a divider offers equalise', (tester) async {
      final c = controller();
      await pump(tester, c);
      await tester.tapAt(
        tester.getCenter(find.byType(DividerHandle)),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Equalise'));
      await tester.pumpAndSettle();
      expect(
        (c.rootOf('w') as SplitNode).sizes,
        everyElement(const PanelExtent.flex()),
      );
    });

    testWidgets('a chip menu is the host\'s unless the decoration took it', (
      tester,
    ) async {
      final c = controller();
      await pump(tester, c);
      await tester.tapAt(
        tester.getCenter(find.text('Ta')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Close others'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Close others'), findsNothing);
    });

    testWidgets('null turns the menus off', (tester) async {
      final c = controller();
      await pump(tester, c, menus: null);
      await tester.tapAt(
        tester.getCenter(find.text('Ta')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Close others'), findsNothing);
    });
  });
}
