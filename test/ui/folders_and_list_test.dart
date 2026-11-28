import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaamos_mail/src/core/mail_errors.dart';

import '../support/app_harness.dart';
import '../support/fakes.dart';

/// Shows the folders: always visible on desktop, a page on the phone.
Future<void> openFolders(WidgetTester tester, Layout layout) async {
  if (layout == Layout.phone) await tapLabel(tester, 'Cartelle');
}

/// The list that shows [text], resolved now: rows leave the tree as it
/// scrolls, so a lazy ancestor finder would stop matching.
Finder listAround(WidgetTester tester, String text) {
  // Resolved now, by its State: the text may scroll away, and the
  // Scrollable widget may be rebuilt, but its State stays the same.
  final state = tester.state<ScrollableState>(
    find.ancestor(of: find.text(text), matching: find.byType(Scrollable)).first,
  );
  return find.byElementPredicate(
    (e) => e is StatefulElement && e.state == state,
  );
}

void main() {
  testBothLayouts('the folder list opens another folder', (
    tester,
    layout,
  ) async {
    final app = AppHarness();
    app.server.folders['Sent']!.messages[1] = summary(1, subject: 'Inviata');
    await app.addAccount();
    await app.pump(tester, layout: layout);

    await openFolders(tester, layout);
    for (final name in ['Posta in arrivo', 'Inviati', 'Archivio', 'Cestino']) {
      expect(find.text(name), findsWidgets, reason: name);
    }
    await tapText(tester, 'Inviati');
    expect(find.text('Inviata 1'), findsOneWidget);
    expect(find.text('Oggetto 5'), findsNothing);
  });

  testBothLayouts('list rows: newest first, with sender and preview', (
    tester,
    layout,
  ) async {
    final app = AppHarness(inbox: 3);
    await app.addAccount();
    await app.pump(tester, layout: layout);

    final y3 = tester.getTopLeft(find.text('Oggetto 3')).dy;
    final y1 = tester.getTopLeft(find.text('Oggetto 1')).dy;
    expect(y3, lessThan(y1), reason: 'newest on top');
    expect(find.text('Anteprima 3'), findsOneWidget);
    expect(find.text('Marta'), findsWidgets);
  });

  testBothLayouts('refresh brings new messages', (tester, layout) async {
    final app = AppHarness();
    await app.addAccount();
    await app.pump(tester, layout: layout);

    app.server.folders['INBOX']!.messages[6] = summary(6, subject: 'Nuova');
    await tapLabel(tester, 'Aggiorna');
    expect(find.text('Nuova 6'), findsOneWidget);
  });

  testBothLayouts('search filters the folder, clearing it restores', (
    tester,
    layout,
  ) async {
    final app = AppHarness();
    app.server.folders['INBOX']!.messages[6] = summary(6, subject: 'Rifugio');
    await app.addAccount();
    await app.pump(tester, layout: layout);

    final field = find.bySemanticsLabel('Cerca nella cartella');
    await tester.enterText(field, 'rifugio');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Rifugio 6'), findsOneWidget);
    expect(find.text('Oggetto 5'), findsNothing);

    await tester.enterText(field, '');
    await tester.pumpAndSettle();
    expect(find.text('Oggetto 5'), findsOneWidget);
  });

  testBothLayouts('a search with no matches shows no error', (
    tester,
    layout,
  ) async {
    // Regression: sorting the const [] returned for zero matches threw
    // "Cannot modify an unmodifiable list" (seen on Gmail).
    final app = AppHarness();
    await app.addAccount();
    await app.pump(tester, layout: layout);

    final field = find.bySemanticsLabel('Cerca nella cartella');
    await tester.enterText(field, 'prova');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Nessun messaggio trovato.'), findsOneWidget);
    expect(find.textContaining('Errore'), findsNothing);
  });

  testBothLayouts('"Carica altri" loads the next page', (tester, layout) async {
    final app = AppHarness(inbox: 55);
    await app.addAccount();
    await app.pump(tester, layout: layout);

    expect(find.text('Oggetto 5'), findsNothing, reason: 'first 50 only');
    await tester.scrollUntilVisible(
      find.text('Carica altri'),
      400,
      scrollable: listAround(tester, 'Oggetto 55'),
    );
    await tapText(tester, 'Carica altri');
    await tester.scrollUntilVisible(
      find.text('Oggetto 1'),
      400,
      scrollable: listAround(tester, 'Oggetto 6'),
    );
    expect(find.text('Oggetto 1'), findsOneWidget);
  });

  testBothLayouts('a server error shows a banner that closes', (
    tester,
    layout,
  ) async {
    final app = AppHarness();
    await app.addAccount();
    await app.pump(tester, layout: layout);

    app.server.failWith = const MailFailure(
      MailFailureKind.network,
      'Server non raggiungibile.',
    );
    await tapLabel(tester, 'Aggiorna');
    expect(find.text('Chiudi'), findsOneWidget);
    expect(find.text('Oggetto 5'), findsOneWidget, reason: 'cache stays');

    await tapText(tester, 'Chiudi');
    expect(find.text('Chiudi'), findsNothing);
  });
}
