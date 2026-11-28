import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mail_session_test.dart' show secondAccount;
import '../support/app_harness.dart';
import '../support/fakes.dart';

/// A field of the add-account form, by the label above it.
Finder field(String label, [int index = 0]) =>
    find.bySemanticsLabel(RegExp('^$label')).at(index);

Future<void> type(WidgetTester tester, Finder f, String text) async {
  await tester.enterText(f, text);
  await tester.pump();
}

Future<void> saveForm(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Verifica e salva'));
  await tapText(tester, 'Verifica e salva');
}

/// The folders: a page on the phone.
Future<void> openFolders(WidgetTester tester, Layout layout) async {
  if (layout == Layout.phone) await tapLabel(tester, 'Cartelle');
}

/// Opens the account panel. On the phone it is the avatar at the right of
/// the search bar, on desktop the row at the bottom of the folders; both are
/// labelled "Account <address>".
Future<void> openAccountPanel(WidgetTester tester, String email) =>
    tapLabel(tester, 'Account $email');

void main() {
  testBothLayouts('the form says what is missing, one thing at a time', (
    tester,
    layout,
  ) async {
    final app = AppHarness();
    await app.pump(tester, layout: layout);

    await saveForm(tester);
    expect(find.text('Inserisci un indirizzo email valido.'), findsOneWidget);
    await type(tester, field('Indirizzo email'), 'nuovo@esempio.org');
    await saveForm(tester);
    expect(
      find.text('Inserisci la password o la password per app.'),
      findsOneWidget,
    );
    await type(tester, field('Password'), 'segreta');
    await type(tester, field('Server', 0), '');
    await saveForm(tester);
    expect(find.text('Inserisci i server IMAP e SMTP.'), findsOneWidget);
  });

  testBothLayouts('the servers are suggested from the address', (
    tester,
    layout,
  ) async {
    final app = AppHarness();
    await app.pump(tester, layout: layout);

    await type(tester, field('Indirizzo email'), 'nuovo@esempio.org');
    expect(find.text('imap.esempio.org'), findsOneWidget);
    expect(find.text('smtp.esempio.org'), findsOneWidget);
  });

  testBothLayouts('a manual account is checked, saved and opened', (
    tester,
    layout,
  ) async {
    final app = AppHarness();
    await app.pump(tester, layout: layout);

    await type(tester, field('Nome visualizzato'), 'Nuovo');
    await type(tester, field('Indirizzo email'), 'nuovo@esempio.org');
    await type(tester, field('Password'), 'segreta');
    await type(tester, field('Server', 0), 'imap.esempio.org');
    await type(tester, field('Server', 1), 'smtp.esempio.org');
    await saveForm(tester);

    final saved = (await app.accounts.load()).single;
    expect(saved.email, 'nuovo@esempio.org');
    expect(saved.imap.host, 'imap.esempio.org');
    expect(await app.accounts.password(saved.id), 'segreta');
    expect(find.text('Oggetto 5'), findsOneWidget, reason: 'Inbox open');
  });

  testBothLayouts('the same address twice is refused', (tester, layout) async {
    final app = AppHarness();
    await app.addAccount();
    await app.pump(tester, layout: layout);
    await openAccountPanel(tester, testAccount.email);
    await tapText(tester, 'Aggiungi account');

    // Over an existing mailbox the form is a card, with "Annulla".
    expect(find.byKey(const ValueKey('account-setup-card')), findsOneWidget);
    expect(find.text('Annulla'), findsOneWidget);

    await type(tester, field('Indirizzo email'), testAccount.email);
    await type(tester, field('Password'), 'p');
    await type(tester, field('Server', 0), 'imap.esempio.org');
    await type(tester, field('Server', 1), 'smtp.esempio.org');
    await saveForm(tester);
    expect(find.text('Questo account c\'è già.'), findsOneWidget);
  });

  testBothLayouts('switching account from the account panel', (
    tester,
    layout,
  ) async {
    final app = AppHarness();
    await app.addAccount();
    await app.addAccount(secondAccount);
    await app.pump(tester, layout: layout);

    await openAccountPanel(tester, testAccount.email);
    await tapLabel(tester, 'Lavoro, ${secondAccount.email}');
    expect(find.bySemanticsLabel('Account ${secondAccount.email}'), findsOne);
    expect(find.bySemanticsLabel('Account ${testAccount.email}'), findsNothing);
  });

  testBothLayouts('the account button: avatar on the phone, row on desktop', (
    tester,
    layout,
  ) async {
    final app = AppHarness();
    await app.addAccount();
    await app.pump(tester, layout: layout);

    final account = find.bySemanticsLabel('Account ${testAccount.email}');
    if (layout == Layout.phone) {
      // Right of the search bar, on the same line.
      final search = tester.getRect(
        find.bySemanticsLabel('Cerca nella cartella'),
      );
      final avatar = tester.getRect(account);
      expect(avatar.left, greaterThanOrEqualTo(search.right));
      expect(avatar.center.dy, closeTo(search.center.dy, 4));
      // And no longer in the folders page.
      await openFolders(tester, layout);
      expect(find.text(testAccount.email), findsNothing);
    } else {
      // At the bottom of the folders column, under the folders.
      final avatar = tester.getRect(account);
      expect(avatar.left, lessThan(240));
      expect(
        avatar.top,
        greaterThan(tester.getRect(find.text('Cestino')).bottom),
      );
      expect(find.text(testAccount.email), findsOneWidget);
    }
  });

  testBothLayouts('removing an account asks first, then forgets it', (
    tester,
    layout,
  ) async {
    final app = AppHarness();
    await app.addAccount();
    await app.pump(tester, layout: layout);
    await openAccountPanel(tester, testAccount.email);

    await tapText(tester, 'Rimuovi ${testAccount.email}');
    await tapText(tester, 'Annulla');
    expect(await app.accounts.load(), isNotEmpty);

    await openAccountPanel(tester, testAccount.email);
    await tapText(tester, 'Rimuovi ${testAccount.email}');
    await tester.tap(find.text('Rimuovi').last);
    await tester.pumpAndSettle();
    expect(await app.accounts.load(), isEmpty);
    expect(await app.accounts.password(testAccount.id), isNull);
    expect(find.text('Aggiungi un account'), findsOneWidget);
  });

  testBothLayouts('"Tutte le caselle" merges the Inboxes', (
    tester,
    layout,
  ) async {
    final app = AppHarness();
    await app.addAccount();
    await app.addAccount(secondAccount);
    await app.pump(tester, layout: layout);
    await openFolders(tester, layout);

    await tapLabel(tester, 'Tutte le caselle');
    // One fake server for both accounts: each message appears twice.
    expect(find.text('Oggetto 5'), findsNWidgets(2));
    await tester.tap(find.text('Oggetto 5').last);
    await tester.pumpAndSettle();
    expect(find.text('Testo del messaggio 5'), findsOneWidget);
  });
}
