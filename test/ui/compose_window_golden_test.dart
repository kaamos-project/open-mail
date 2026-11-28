import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';

/// Pixel checks of the desktop compose window: the border must be drawn
/// all around, over the title bar too, with no wide shadow around it.
///
/// Goldens are generated on Linux, like CI's runner:
/// `flutter test --update-goldens test/ui/compose_window_golden_test.dart`.
void main() {
  testLayout(Layout.desktop, 'compose window border and shadow', (
    tester,
  ) async {
    final app = AppHarness();
    await app.addAccount();
    await app.pump(tester);
    await tapText(tester, 'Scrivi');

    await expectLater(
      find.byType(WidgetsApp),
      matchesGoldenFile('goldens/compose_window.png'),
    );
  });

  testLayout(Layout.desktop, 'the border is painted over the content', (
    tester,
  ) async {
    final app = AppHarness();
    await app.addAccount();
    await app.pump(tester);
    await tapText(tester, 'Scrivi');

    final window = tester.widget<Container>(
      find.byKey(const ValueKey('compose-window')),
    );
    // A border in `decoration` sits behind the title bar, which covers it.
    expect((window.decoration! as BoxDecoration).border, isNull);
    final front = window.foregroundDecoration! as BoxDecoration;
    expect(front.border, isNotNull);
    expect(
      front.borderRadius,
      (window.decoration! as BoxDecoration).borderRadius,
    );
    expect(window.clipBehavior, isNot(Clip.none));
  });
}
