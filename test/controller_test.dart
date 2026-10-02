import 'package:fl_panel/fl_panel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PanelTab tab(String id) =>
      PanelTab(id: id, contentId: id, metadata: {'title': id});

  /// [ A(a, a2) | B(b) ] over C(c).
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

  PanelController controller({CloseGuard? guard, String? focused}) {
    final c = PanelController(
      workspace: PanelWorkspace(
        windows: [PanelWindow(id: 'w', root: tree(), focusedLeafId: focused)],
      ),
      closeGuard: guard,
    );
    addTearDown(c.dispose);
    return c;
  }

  List<PanelEvent> record(PanelController c) {
    final events = <PanelEvent>[];
    c.events.listen(events.add);
    return events;
  }

  group('focus', () {
    test('the focused leaf defaults to the first and follows activation', () {
      final c = controller();
      expect(c.focusedLeaf('w')!.id, 'left');
      c.activate('b');
      expect(c.focusedLeaf('w')!.id, 'right');
    });

    test('a recorded leaf that is gone falls back to the first', () {
      final c = controller(focused: 'right');
      c.close('b');
      expect(c.focusedLeaf('w')!.id, 'left');
    });

    test('focus activates, focuses and issues a reveal', () {
      final c = controller();
      var notified = 0;
      c.addListener(() => notified++);
      c.focus('a2', keyboard: true);
      expect((c.rootOf('w')!.find('left') as TabGroup).activeTab!.id, 'a2');
      expect(c.focusedLeaf('w')!.id, 'left');
      expect(c.reveal?.tabId, 'a2');
      expect(c.reveal?.keyboard, isTrue);
      final first = c.reveal!.nonce;
      c.focus('a2');
      expect(c.reveal!.nonce, greaterThan(first), reason: 'each focus is new');
      expect(notified, greaterThan(0));
    });

    test('focusLeaf alone does not change the active tab', () {
      final c = controller();
      c.focusLeaf('w', 'right');
      expect(c.focusedLeaf('w')!.id, 'right');
      expect((c.rootOf('w')!.find('left') as TabGroup).activeTab!.id, 'a');
    });

    test('open defaults to the focused leaf and focuses the new tab', () {
      final c = controller(focused: 'right');
      c.open('w', [tab('n')]);
      final right = c.rootOf('w')!.find('right') as TabGroup;
      expect(right.tabs.map((t) => t.id), ['b', 'n']);
      expect(right.activeTab!.id, 'n');
      expect(c.reveal?.tabId, 'n');
    });

    test('open falls back when the focused leaf refuses', () {
      final c = PanelController(
        workspace: PanelWorkspace(
          windows: [
            PanelWindow(
              id: 'w',
              focusedLeafId: 'solo',
              root: SplitNode(
                id: 'root',
                axis: PanelAxis.horizontal,
                children: [
                  SinglePanel(
                    id: 'solo',
                    tab: PanelTab(
                      id: 's',
                      contentId: 's',
                      allowedForms: const {SurfaceForm.single},
                    ),
                  ),
                  TabGroup(id: 'g', tabs: [tab('g1')]),
                ],
              ),
            ),
          ],
        ),
      );
      addTearDown(c.dispose);
      expect(c.open('w', [tab('n')]), isTrue);
      expect(
        (c.rootOf('w')!.find('g') as TabGroup).tabs.map((t) => t.id),
        ['g1', 'n'],
        reason: 'the single panel cannot take a tab; the next leaf can',
      );
    });

    test('the focused leaf round-trips through JSON', () {
      final c = controller(focused: 'right');
      final other = PanelController();
      addTearDown(other.dispose);
      other.load(c.toJson());
      expect(other.window('w')!.focusedLeafId, 'right');
    });

    test('next and previous wrap within the focused group', () {
      final c = controller(focused: 'left');
      c.nextTab('w');
      expect(c.focusedLeaf('w')!.activeTab!.id, 'a2');
      c.nextTab('w');
      expect(c.focusedLeaf('w')!.activeTab!.id, 'a');
      c.previousTab('w');
      expect(c.focusedLeaf('w')!.activeTab!.id, 'a2');
    });
  });

  group('events', () {
    test('a close is a TabClosed with where it was', () async {
      final c = controller();
      final events = record(c);
      await c.close('a2');
      final closed = events.whereType<TabClosed>().single;
      expect(closed.tab.id, 'a2');
      expect(closed.leafId, 'left');
    });

    test('a dock is a TabMoved from one placement to another', () {
      final c = controller();
      final events = record(c);
      c.dock('w', const DockSource.tab('a'), const DockTarget.join('right'));
      final moved = events.whereType<TabMoved>().single;
      expect(moved.from.leafId, 'left');
      expect(moved.to.leafId, 'right');
      expect(events.whereType<TabClosed>(), isEmpty);
      expect(events.whereType<TabOpened>(), isEmpty);
    });

    test('a tab dragged into a new leaf reports the new leaf id', () {
      final c = controller();
      final events = record(c);
      c.dock(
        'w',
        const DockSource.tab('a'),
        const DockTarget.split('right', DockSide.bottom),
      );
      final moved = events.whereType<TabMoved>().single;
      expect(moved.to.leafId, isNot('left'));
      expect(c.rootOf('w')!.find(moved.to.leafId), isA<TabGroup>());
    });

    test('open is a TabOpened; load is a diff and then LayoutReplaced', () {
      final c = controller();
      final events = record(c);
      c.open('w', [tab('n')]);
      expect(events.whereType<TabOpened>().single.tab.id, 'n');

      events.clear();
      final other = PanelController(
        workspace: PanelWorkspace(
          windows: [
            PanelWindow(
              id: 'w',
              root: TabGroup(id: 'g', tabs: [tab('a'), tab('z')]),
            ),
          ],
        ),
      );
      addTearDown(other.dispose);
      c.load(other.toJson());
      expect(events.whereType<TabClosed>().map((e) => e.tab.id).toSet(), {
        'a2',
        'b',
        'c',
        'n',
      });
      expect(events.whereType<TabOpened>().single.tab.id, 'z');
      expect(
        events.whereType<TabMoved>().single.tab.id,
        'a',
        reason: 'a survived in a different leaf',
      );
      expect(events.last, isA<LayoutReplaced>());
    });

    test('activation and focus are reported, and not as settles', () {
      var settled = 0;
      final c = controller();
      c.onSettled = () => settled++;
      final events = record(c);
      c.activate('a2');
      c.focusLeaf('w', 'right');
      expect(events.whereType<TabActivated>().single.tab.id, 'a2');
      expect(
        events.whereType<LeafFocused>().map((e) => e.leafId),
        ['left', 'right'],
        reason: 'activating a2 focused left first',
      );
      expect(settled, 0);
    });
  });

  group('close guard', () {
    test('a refusing guard keeps the tab', () async {
      final c = controller(guard: (tab) async => tab.id != 'a');
      expect(await c.close('a'), isFalse);
      expect(await c.close('a2'), isTrue);
      expect(c.tab('a'), isNotNull);
      expect(c.tab('a2'), isNull);
    });

    test('the group verbs ask per tab', () async {
      final asked = <String>[];
      final c = controller(
        guard: (tab) async {
          asked.add(tab.id);
          return tab.id != 'a2';
        },
      );
      c.open('w', [tab('a3')], target: const DockTarget.join('left'));
      await c.closeOthers('a');
      expect(asked, ['a2', 'a3']);
      expect((c.rootOf('w')!.find('left') as TabGroup).tabs.map((t) => t.id), [
        'a',
        'a2',
      ]);
    });

    test('closeToTheRight closes what follows in the strip', () async {
      final c = controller();
      c.open('w', [tab('a3')], target: const DockTarget.join('left'));
      await c.closeToTheRight('a');
      expect((c.rootOf('w')!.find('left') as TabGroup).tabs.map((t) => t.id), [
        'a',
      ]);
    });

    test('closeActive closes the focused group\'s active tab', () async {
      final c = controller(focused: 'right');
      expect(await c.closeActive('w'), isTrue);
      expect(c.rootOf('w')!.find('right'), isNull);
    });
  });

  group('focus policy', () {
    PanelController tools() {
      final c = PanelController(
        policy: const _EditorsOnly(),
        workspace: PanelWorkspace(
          windows: [
            PanelWindow(
              id: 'w',
              focusedLeafId: 'tools',
              root: SplitNode(
                id: 'root',
                axis: PanelAxis.horizontal,
                children: [
                  TabGroup(id: 'tools', tabs: [tab('files')]),
                  TabGroup(id: 'editors', tabs: [tab('a')], persistent: true),
                ],
              ),
            ),
          ],
        ),
      );
      addTearDown(c.dispose);
      return c;
    }

    test('a leaf that takes no focus is never the focused one', () {
      final c = tools();
      expect(
        c.focusedLeaf('w')!.id,
        'editors',
        reason: 'the recorded tools leaf is passed over',
      );
      c.focusLeaf('w', 'tools');
      c.activate('files');
      expect(c.focusedLeaf('w')!.id, 'editors');
      expect(c.window('w')!.focusedLeafId, 'tools', reason: 'untouched');
      c.open('w', [tab('n')]);
      expect(c.rootOf('w')!.leafOf('n')!.id, 'editors');
    });
  });

  group('closable', () {
    test('an unclosable tab refuses the verbs and keeps its leaf', () async {
      var asked = 0;
      final c = controller(
        guard: (tab) async {
          asked++;
          return true;
        },
      );
      c.updateTab('b', (tab) => tab.copyWith(closable: false));
      expect(await c.close('b'), isFalse);
      expect(asked, 0, reason: 'the guard is never consulted for it');
      await c.closeLeaf('w', 'right');
      expect(c.tab('b'), isNotNull);
      expect(c.rootOf('w')!.find('right'), isA<TabGroup>());
      c.focusLeaf('w', 'right');
      expect(await c.closeActive('w'), isFalse);
    });

    test('closeActive on an empty persistent group is a no-op', () async {
      final c = PanelController(
        workspace: PanelWorkspace(
          windows: [
            PanelWindow(
              id: 'w',
              root: TabGroup(id: 'g', tabs: const [], persistent: true),
            ),
          ],
        ),
      );
      addTearDown(c.dispose);
      expect(await c.closeActive('w'), isFalse);
      c.nextTab('w');
      expect(c.open('w', [tab('n')]), isTrue, reason: 'open lands in it');
      expect((c.rootOf('w')!.find('g') as TabGroup).activeTab!.id, 'n');
    });
  });

  group('updateTab', () {
    test('replaces the tab in place and reports it', () {
      final c = controller();
      final events = record(c);
      var settled = 0;
      c.onSettled = () => settled++;
      c.updateTab(
        'a',
        (tab) => tab.copyWith(metadata: {'title': 'renamed', 'dirty': true}),
      );
      expect(c.tab('a')!.metadata['title'], 'renamed');
      expect(
        (c.rootOf('w')!.find('left') as TabGroup).tabs.first.metadata['dirty'],
        isTrue,
      );
      final updated = events.whereType<TabUpdated>().single;
      expect(updated.before.metadata['title'], 'a');
      expect(settled, 1, reason: 'a title is worth persisting');
    });

    test('an unchanged tab is a no-op', () {
      final c = controller();
      var notified = 0;
      c.addListener(() => notified++);
      c.updateTab('a', (tab) => tab);
      expect(notified, 0);
    });
  });
}

final class _EditorsOnly extends DockPolicy {
  const _EditorsOnly();

  @override
  bool canBeFocusedLeaf(LeafNode leaf) => leaf is TabGroup && leaf.persistent;
}
