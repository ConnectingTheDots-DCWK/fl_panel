import 'package:fl_panel/fl_panel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [PanelDecorations.titleScroll]: a title too long for its chip scrolls
/// under a resting pointer, and only when the host asked for it.
void main() {
  const long = 'the_long_night_at_the_ferryman_s_crossing.loc.narr.bdl';

  PanelController controller() {
    final controller = PanelController(
      workspace: PanelWorkspace(
        windows: [
          PanelWindow(
            id: 'main',
            root: TabGroup(
              id: 'docs',
              tabs: [
                PanelTab(id: 'a', contentId: 'a', metadata: {'title': long}),
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
    PanelTitleScroll? scroll,
  ) async {
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: PanelHost(
          controller: controller,
          windowId: 'main',
          decorations: PanelDecorations(titleScroll: scroll),
          contentBuilder: (context, tab) => const SizedBox.expand(),
        ),
      ),
    );
  }

  testWidgets('a long title scrolls after the delay, and only when asked', (
    tester,
  ) async {
    final c = controller();
    final moving = find.descendant(
      of: find.byType(TabChip),
      matching: find.byType(ClipRect),
    );
    const scroll = PanelTitleScroll();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);

    // Off, the default: the chip is what it always was.
    await pump(tester, c, null);
    await mouse.moveTo(tester.getCenter(find.text(long)));
    await tester.pump(const Duration(seconds: 2));
    expect(moving, findsNothing, reason: 'no titleScroll, no motion');

    await mouse.moveTo(Offset.zero);
    await pump(tester, c, scroll);
    await mouse.moveTo(tester.getCenter(find.text(long)));
    await tester.pump(scroll.delay - const Duration(milliseconds: 50));
    expect(moving, findsNothing, reason: 'a pointer passing by moves nothing');

    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 500));
    expect(moving, findsOneWidget);
    final shift = tester
        .widget<Transform>(
          find.descendant(of: moving, matching: find.byType(Transform)),
        )
        .transform
        .getTranslation()
        .x;
    expect(shift, lessThan(0), reason: 'the end of the title comes in');

    // Leaving puts it back at rest at once.
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(moving, findsNothing);
  });
}
