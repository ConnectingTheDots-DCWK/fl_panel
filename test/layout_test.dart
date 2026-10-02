import 'package:fl_panel/model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PanelTab tab(String id, {double minWidth = 0, double minHeight = 0}) =>
      PanelTab(id: id, contentId: id, minWidth: minWidth, minHeight: minHeight);
  SinglePanel panel(String id, {double minWidth = 0, double minHeight = 0}) =>
      SinglePanel(
        id: 'p.$id',
        tab: tab(id, minWidth: minWidth, minHeight: minHeight),
      );
  SplitNode row(List<LayoutNode> children, {List<PanelExtent>? sizes}) =>
      SplitNode(
        id: 'row',
        axis: PanelAxis.horizontal,
        children: children,
        sizes: sizes,
      );

  const solver = PanelSolver(dividerThickness: 10);
  const bounds = PanelRect(0, 0, 1000, 500);

  group('distribute', () {
    test('flex children share by weight after fixed ones take theirs', () {
      final tree = row(
        [panel('a'), panel('b'), panel('c')],
        sizes: const [
          PanelExtent.fixed(200),
          PanelExtent.flex(1),
          PanelExtent.flex(3),
        ],
      );
      final result = solver.layout(tree, bounds);
      // 1000 - 2 dividers of 10 = 980; 200 fixed; 780 split 1:3.
      expect(result.rectOf('p.a'), const PanelRect(0, 0, 200, 500));
      expect(result.rectOf('p.b'), const PanelRect(210, 0, 195, 500));
      expect(result.rectOf('p.c'), const PanelRect(415, 0, 585, 500));
      expect(result.dividers.map((d) => d.rect.left), [200, 405]);
    });

    test('a child below its minimum is held there at the others\' expense', () {
      final tree = row(
        [panel('a', minWidth: 400), panel('b'), panel('c')],
        sizes: const [
          PanelExtent.flex(1),
          PanelExtent.flex(1),
          PanelExtent.flex(1),
        ],
      );
      final sizes = solver.distribute(tree, 980);
      expect(sizes[0], 400);
      expect(sizes[1], 290);
      expect(sizes[2], 290, reason: 'the remainder is shared by weight');
    });

    test('over-constrained, every child scales down together', () {
      final tree = row([panel('a', minWidth: 600), panel('b', minWidth: 600)]);
      final sizes = solver.distribute(tree, 990);
      expect(sizes, [495, 495]);
    });

    test('a greedy fixed child gives back for a flex minimum', () {
      final tree = row(
        [panel('a', minWidth: 100), panel('b', minWidth: 300)],
        sizes: const [PanelExtent.fixed(800), PanelExtent.flex(1)],
      );
      final sizes = solver.distribute(tree, 990);
      expect(sizes[1], 300, reason: 'the flex minimum is honoured first');
      expect(sizes[0], 690, reason: 'the fixed child is what gives');
    });

    test('a fixed child is never laid out below its content minimum', () {
      final tree = row(
        [panel('a', minWidth: 300), panel('b')],
        sizes: const [PanelExtent.fixed(100), PanelExtent.flex(1)],
      );
      expect(solver.distribute(tree, 990), [300, 690]);
    });

    test('with no flex child the fixed ones stretch to fill', () {
      final tree = row(
        [panel('a'), panel('b')],
        sizes: const [PanelExtent.fixed(100), PanelExtent.fixed(300)],
      );
      expect(solver.distribute(tree, 800), [200, 600]);
    });

    test(
      'a nested split\'s minimum is the sum along its axis and the max across',
      () {
        final inner = SplitNode(
          id: 'inner',
          axis: PanelAxis.horizontal,
          children: [
            panel('b', minWidth: 100, minHeight: 50),
            panel('c', minWidth: 150, minHeight: 80),
          ],
        );
        expect(inner.minAlong(PanelAxis.horizontal, 10), 260);
        expect(inner.minAlong(PanelAxis.vertical, 10), 80);
      },
    );
  });

  group('resize', () {
    test('the two neighbours trade pixels and nobody else moves', () {
      final tree = row([panel('a'), panel('b'), panel('c')]);
      final before = solver.distribute(tree, 990); // 330 each
      final sizes = solver.resize(tree, before, 0, 60);
      final after = solver.distribute(tree.copyWith(sizes: sizes), 990);
      expect(after.map((v) => v.round()), [390, 270, 330]);
    });

    test('is clamped at the neighbours\' minimums', () {
      final tree = row([panel('a', minWidth: 100), panel('b', minWidth: 100)]);
      final before = solver.distribute(tree, 990);
      final sizes = solver.resize(tree, before, 0, -10000);
      final after = solver.distribute(tree.copyWith(sizes: sizes), 990);
      expect(after.map((v) => v.round()), [100, 890]);
    });

    test('a fixed child stays fixed at its new size', () {
      final tree = row(
        [panel('a'), panel('b')],
        sizes: const [PanelExtent.fixed(200), PanelExtent.flex(1)],
      );
      final sizes = solver.resize(tree, [200, 790], 0, 40);
      expect(sizes.first, const PanelExtent.fixed(240));
      expect(sizes.last, isA<FlexExtent>());
    });

    test('a zero delta hands back the same extents', () {
      final tree = row([panel('a'), panel('b')]);
      expect(
        identical(solver.resize(tree, [495, 495], 0, 0), tree.sizes),
        isTrue,
      );
    });
  });

  group('dock resolver', () {
    final tree = row([panel('a'), panel('b')]);
    final layout = solver.layout(tree, bounds);
    const resolver = DockResolver(edgeBand: 24);

    DockCandidate? at(
      double x,
      double y, {
      DockSource source = const DockSource.tab('a'),
    }) {
      final leaf = layout.leafAt(tree, x, y);
      return resolver.resolve(
        root: tree,
        layout: layout,
        source: source,
        hit: leaf == null ? const DockHit.none() : DockHit.leaf(leaf.id, x, y),
        preferredForm: SurfaceForm.tabbed,
      );
    }

    test('the centre of a leaf joins it', () {
      final candidate = at(750, 250)!;
      expect(candidate.target, const DockTarget.join('p.b'));
      expect(candidate.preview, layout.rectOf('p.b'));
    });

    test('the edges of a leaf split it, previewing the half', () {
      final top = at(750, 60)!;
      expect(top.target, const DockTarget.split('p.b', DockSide.top));
      expect(top.preview, const PanelRect(505, 0, 495, 250));
      final left = at(540, 250)!;
      expect(left.target, const DockTarget.split('p.b', DockSide.left));
    });

    test('the window edge splits the root', () {
      final candidate = at(990, 250)!;
      expect(candidate.target, const DockTarget.root(DockSide.right));
      expect(candidate.preview, const PanelRect(750, 0, 250, 500));
    });

    test('a drop that changes nothing offers nothing', () {
      expect(
        at(100, 250, source: const DockSource.leaf('p.a')),
        isNull,
        reason: 'a joining itself',
      );
      expect(
        at(50, 250, source: const DockSource.leaf('p.a')),
        isNull,
        reason: 'a splitting itself',
      );
    });

    test('a refused form falls back to the other', () {
      final result = resolver.resolve(
        root: tree,
        layout: layout,
        source: DockSource.fresh([
          PanelTab(
            id: 'x',
            contentId: 'x',
            allowedForms: const {SurfaceForm.tabbed},
          ),
        ]),
        hit: const DockHit.leaf('p.b', 750, 60),
        preferredForm: SurfaceForm.single,
      )!;
      expect(result.target, const DockTarget.split('p.b', DockSide.top));
    });

    test('a strip hit inserts at the index', () {
      final grouped = row([
        TabGroup(id: 'g', tabs: [tab('a'), tab('b')]),
        panel('c'),
      ]);
      final result = resolver.resolve(
        root: grouped,
        layout: solver.layout(grouped, bounds),
        source: const DockSource.tab('c'),
        hit: const DockHit.strip('g', 1),
        preferredForm: SurfaceForm.single,
      )!;
      expect(result.target, const DockTarget.join('g', index: 1));
      expect((result.result as TabGroup).tabs.map((t) => t.id), [
        'a',
        'c',
        'b',
      ]);
    });
  });
}
