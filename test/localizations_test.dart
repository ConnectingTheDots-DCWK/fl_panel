import 'package:fl_panel/fl_panel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every word bracketed, the way a pseudo-locale marks what went through
/// the localizations — so a label that did not shows up plain.
class _Bracketed extends DefaultPanelLocalizations {
  const _Bracketed();

  @override
  String get closeTab => '[${super.closeTab}]';
  @override
  String get closeOtherTabs => '[${super.closeOtherTabs}]';
  @override
  String get closeTabsAfter => '[${super.closeTabsAfter}]';
  @override
  String get closeAllTabs => '[${super.closeAllTabs}]';
  @override
  String get closePanel => '[${super.closePanel}]';
  @override
  String get split => '[${super.split}]';
  @override
  String get moveToEdge => '[${super.moveToEdge}]';
  @override
  String get equalise => '[${super.equalise}]';
  @override
  String swapSides(PanelAxis axis) => '[${super.swapSides(axis)}]';
  @override
  String dockSide(DockSide side) => '[${super.dockSide(side)}]';
}

class _BracketedDelegate extends LocalizationsDelegate<PanelLocalizations> {
  const _BracketedDelegate();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<PanelLocalizations> load(Locale locale) =>
      SynchronousFuture<PanelLocalizations>(const _Bracketed());
  @override
  bool shouldReload(_BracketedDelegate old) => false;
}

void main() {
  PanelTab tab(String id, {bool closable = true}) => PanelTab(
    id: id,
    contentId: id,
    metadata: {'title': 'T$id'},
    closable: closable,
  );

  /// [ tools(files) | editors(a, b) ] — every one of the four targets.
  PanelController controller() {
    final c = PanelController(
      workspace: PanelWorkspace(
        windows: [
          PanelWindow(
            id: 'w',
            root: SplitNode(
              id: 'root',
              axis: PanelAxis.horizontal,
              sizes: const [PanelExtent.flex(3), PanelExtent.flex(7)],
              children: [
                SinglePanel(id: 'tools', tab: tab('files', closable: false)),
                TabGroup(id: 'editors', tabs: [tab('a'), tab('b')]),
              ],
            ),
          ),
        ],
      ),
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Every default entry of every target, flattened through submenus.
  List<PanelMenuEntry> everyEntry(
    PanelController c, {
    PanelLocalizations? localizations,
  }) {
    final root = c.rootOf('w')!;
    final editors = root.find('editors') as TabGroup;
    final divider = const PanelSolver()
        .layout(root, const PanelRect(0, 0, 1000, 400))
        .dividers
        .single;
    final targets = <PanelMenuTarget>[
      PanelMenuTabTarget(editors.tabs.first, editors),
      PanelMenuStripTarget(editors),
      PanelMenuHeaderTarget(root.find('tools') as SinglePanel),
      PanelMenuDividerTarget(divider),
    ];
    List<PanelMenuEntry> flatten(List<PanelMenuEntry> entries) => [
      for (final e in entries)
        if (!e.isSeparator) ...[e, ...flatten(e.children)],
    ];
    return [
      for (final target in targets)
        ...flatten(
          PanelMenus.defaultEntries(
            localizations == null
                ? PanelMenuRequest(
                    controller: c,
                    windowId: 'w',
                    target: target,
                    globalPosition: Offset.zero,
                  )
                : PanelMenuRequest(
                    controller: c,
                    windowId: 'w',
                    target: target,
                    globalPosition: Offset.zero,
                    localizations: localizations,
                  ),
          ),
        ),
    ];
  }

  test(
    'every default label comes from the localizations, and keeps its id',
    () {
      final c = controller();
      final english = everyEntry(c);
      final bracketed = everyEntry(c, localizations: const _Bracketed());
      expect(
        bracketed.map((e) => e.label),
        everyElement(startsWith('[')),
        reason: 'a label that skipped the localizations would be plain',
      );
      expect(
        bracketed.map((e) => e.id),
        english.map((e) => e.id),
        reason: 'a translation must not change which entry is which',
      );
      expect(
        english.map((e) => e.id),
        everyElement(isNotNull),
        reason: 'every built-in entry is identifiable without its label',
      );
    },
  );

  test('a request built by hand is in English', () {
    final labels = everyEntry(controller()).map((e) => e.label);
    expect(labels, contains('Close to the right'));
    expect(labels, contains('Swap left and right'));
  });

  test('a builder finds a default by id, whatever it says', () {
    final c = controller();
    final editors = c.rootOf('w')!.find('editors') as TabGroup;
    final menus = PanelMenus(
      build: (request, defaults) => [
        for (final e in defaults)
          if (e.id != PanelMenuEntryId.closeTabsAfter)
            e.id == PanelMenuEntryId.closeTab ? e.copyWith(label: 'Shut') : e,
      ],
    );
    final entries = menus.entriesFor(
      PanelMenuRequest(
        controller: c,
        windowId: 'w',
        target: PanelMenuTabTarget(editors.tabs.first, editors),
        globalPosition: Offset.zero,
        localizations: const _Bracketed(),
      ),
    );
    expect(entries.first.label, 'Shut');
    expect(entries.first.id, PanelMenuEntryId.closeTab, reason: 'copyWith');
    expect(
      entries.map((e) => e.id),
      isNot(contains(PanelMenuEntryId.closeTabsAfter)),
    );
  });

  group('the host', () {
    Future<void> rightClickChip(
      WidgetTester tester,
      PanelController c, {
      List<LocalizationsDelegate<Object>> delegates = const [],
    }) async {
      tester.view.physicalSize = const Size(1000, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: delegates,
          home: PanelHost(
            controller: c,
            windowId: 'w',
            contextMenus: const PanelMenus(),
            contentBuilder: (context, tab) => Text('body ${tab.id}'),
          ),
        ),
      );
      await tester.tapAt(
        tester.getCenter(find.text('Ta')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('says what the delegate in scope says', (tester) async {
      await rightClickChip(
        tester,
        controller(),
        delegates: const [_BracketedDelegate()],
      );
      expect(find.text('[Close others]'), findsOneWidget);
      expect(find.text('Close others'), findsNothing);
    });

    testWidgets('the default delegate is the English', (tester) async {
      await rightClickChip(
        tester,
        controller(),
        delegates: const [DefaultPanelLocalizations.delegate],
      );
      expect(find.text('Close others'), findsOneWidget);
    });
  });
}
