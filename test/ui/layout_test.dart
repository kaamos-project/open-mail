import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaamos_project_ui/kaamos_project_ui.dart';

import '../support/app_harness.dart';

/// The box of the panel (the panel itself is a full-screen Align).
Finder get drawerBox => find
    .descendant(
      of: find.byType(KaamosDrawerPanel),
      matching: find.byType(DecoratedBox),
    )
    .first;

Finder get composeWindow => find.byKey(const ValueKey('compose-window'));

Future<void> fill(WidgetTester tester, String label, String text) async {
  await tester.enterText(find.bySemanticsLabel(label).first, text);
  await tester.pump();
}

void main() {
  group('phone', () {
    testLayout(Layout.phone, 'the hamburger opens the folders in a drawer', (
      tester,
    ) async {
      final app = AppHarness();
      await app.addAccount();
      await app.pump(tester, layout: Layout.phone);

      await tapLabel(tester, 'Cartelle');
      final box = tester.getRect(drawerBox);
      expect(box.left, 0);
      expect(box.width, 320, reason: '85% of 390 is more than 320');
      // The list stays visible on the right, under the scrim.
      expect(find.text('Oggetto 5'), findsOneWidget);
      // Compose is the floating button, not in the drawer.
      expect(
        find.descendant(
          of: find.byType(KaamosDrawerPanel),
          matching: find.text('Scrivi'),
        ),
        findsNothing,
      );

      // A tap on the scrim closes it.
      await tester.tapAt(const Offset(370, 400));
      await tester.pumpAndSettle();
      expect(find.byType(KaamosDrawerPanel), findsNothing);

      // Choosing a folder closes it too.
      await tapLabel(tester, 'Cartelle');
      await tapText(tester, 'Inviati');
      expect(find.byType(KaamosDrawerPanel), findsNothing);
      expect(find.text('Inviati'), findsOneWidget, reason: 'list title');
    });

    testLayout(Layout.phone, 'the Scrivi button shrinks while scrolling down', (
      tester,
    ) async {
      final app = AppHarness(inbox: 30);
      await app.addAccount();
      await app.pump(tester, layout: Layout.phone);

      final fab = find.byType(KaamosFab);
      expect(find.descendant(of: fab, matching: find.text('Scrivi')), findsOne);
      // Resolved now: 'Oggetto 30' scrolls out of view.
      final state = tester.state<ScrollableState>(
        find
            .ancestor(
              of: find.text('Oggetto 30'),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final list = find.byElementPredicate(
        (e) => e is StatefulElement && e.state == state,
      );

      await tester.drag(list, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.getSize(fab), const Size(56, 56));
      expect(find.bySemanticsLabel('Scrivi'), findsOneWidget, reason: 'a11y');

      await tester.drag(list, const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(find.descendant(of: fab, matching: find.text('Scrivi')), findsOne);

      await tapLabel(tester, 'Scrivi');
      expect(find.text('Nuovo messaggio'), findsOneWidget);
    });
  });

  group('desktop compose window', () {
    testLayout(Layout.desktop, 'opens at the bottom right, over the reader', (
      tester,
    ) async {
      final app = AppHarness();
      await app.addAccount();
      await app.pump(tester, layout: Layout.desktop);

      await tapLabel(tester, 'Scrivi');
      final window = tester.getRect(composeWindow);
      // Floating: 16px from the right and bottom edges, like Gmail.
      expect(window.right, 1280 - 16);
      expect(window.bottom, 800 - 16);
      expect(window.width, 560);
      // A bit less than half of the window: 45% of 800 is 360.
      expect(window.height, 360);
      // The list stays usable beside it.
      expect(find.text('Oggetto 5'), findsOneWidget);
      // The title follows the subject.
      await fill(tester, 'Oggetto', 'Gita al rifugio');
      expect(
        find.descendant(
          of: composeWindow,
          matching: find.text('Gita al rifugio'),
        ),
        findsWidgets,
      );
    });

    testLayout(Layout.desktop, 'minimize keeps what was written', (
      tester,
    ) async {
      final app = AppHarness();
      await app.addAccount();
      await app.pump(tester, layout: Layout.desktop);

      await tapLabel(tester, 'Scrivi');
      await fill(tester, 'Testo del messaggio', 'Partiamo alle 7.');
      await tapLabel(tester, 'Riduci');
      expect(tester.getSize(composeWindow), const Size(320, 48));
      expect(tester.getRect(composeWindow).bottom, 800 - 16);
      expect(find.bySemanticsLabel('Testo del messaggio'), findsNothing);

      // A message can be read meanwhile, and the window stays.
      await tapText(tester, 'Oggetto 5');
      expect(composeWindow, findsOneWidget);

      await tapLabel(tester, 'Ripristina');
      expect(find.text('Partiamo alle 7.'), findsOneWidget);
    });

    testLayout(Layout.desktop, 'expand makes it large, and back', (
      tester,
    ) async {
      final app = AppHarness();
      await app.addAccount();
      await app.pump(tester, layout: Layout.desktop);

      await tapLabel(tester, 'Scrivi');
      await tapLabel(tester, 'Ingrandisci');
      final large = tester.getRect(composeWindow);
      expect(large.width, 1000);
      expect(large.height, 800 - 64);
      await tapLabel(tester, 'Dimensione normale');
      expect(tester.getSize(composeWindow).width, 560);
    });

    testLayout(Layout.desktop, 'Scrivi again brings back the open window', (
      tester,
    ) async {
      final app = AppHarness();
      await app.addAccount();
      await app.pump(tester, layout: Layout.desktop);

      await tapLabel(tester, 'Scrivi');
      await fill(tester, 'Testo del messaggio', 'Bozza a metà');
      await tapLabel(tester, 'Riduci');
      await tapLabel(tester, 'Scrivi');
      expect(find.text('Bozza a metà'), findsOneWidget);
      expect(find.text('Salvare la bozza?'), findsNothing);
    });

    testLayout(Layout.desktop, 'a reply asks about the message being written', (
      tester,
    ) async {
      final app = AppHarness();
      await app.addAccount();
      await app.pump(tester, layout: Layout.desktop);

      await tapLabel(tester, 'Scrivi');
      await fill(tester, 'Testo del messaggio', 'Bozza a metà');
      await tapText(tester, 'Oggetto 5');
      await tapLabel(tester, 'Rispondi');
      expect(find.text('Salvare la bozza?'), findsOneWidget);

      // "Continua a scrivere": the reply waits, the text stays.
      await tapText(tester, 'Continua a scrivere');
      expect(find.text('Bozza a metà'), findsOneWidget);

      await tapLabel(tester, 'Rispondi');
      await tapText(tester, 'Elimina');
      expect(find.text('Bozza a metà'), findsNothing);
      expect(find.text('Re: Oggetto 5'), findsWidgets, reason: 'the reply');
    });
  });
}
