import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaamos_mail/src/core/settings.dart';

import '../support/app_harness.dart';
import '../support/fakes.dart';

/// Opens the settings page: the gear next to the account on desktop, the
/// row at the bottom of the drawer on the phone.
Future<void> openSettings(WidgetTester tester, Layout layout) async {
  if (layout == Layout.phone) await tapLabel(tester, 'Cartelle');
  await tapLabel(tester, 'Impostazioni');
}

void main() {
  testBothLayouts('settings open, save the choice and close', (
    tester,
    layout,
  ) async {
    final app = AppHarness();
    await app.addAccount();
    await app.pump(tester, layout: layout);

    await openSettings(tester, layout);
    expect(find.text('Immagini remote'), findsOneWidget);
    // A page, not a pop-up.
    expect(framedAround(find.text('Immagini remote')), findsNothing);

    await tapText(tester, 'Carica sempre');
    await tapText(tester, 'Solo lista');
    await tapText(tester, 'Pagina');
    expect(
      app.settingsStore.saved,
      const AppSettings(
        remoteImages: RemoteImages.always,
        layout: MailLayout.list,
        compose: ComposeMode.page,
      ),
    );

    await tapLabel(tester, 'Indietro');
    expect(find.text('Immagini remote'), findsNothing);
    expect(find.textContaining('Oggetto 5'), findsOneWidget);
  });

  testBothLayouts('"Carica sempre" shows remote images right away', (
    tester,
    layout,
  ) async {
    final app = AppHarness();
    app.settingsStore.saved = const AppSettings(
      remoteImages: RemoteImages.always,
    );
    app.server.folders['INBOX']!.html[5] =
        '<p>Ciao</p><img src="https://tracker.example/pixel.png">';
    await app.addAccount();
    await app.pump(tester, layout: layout);

    await tapText(tester, 'Oggetto 5');
    expect(find.textContaining('Ho bloccato'), findsNothing);
  });

  testLayout(Layout.desktop, '"Solo lista": the message takes the area', (
    tester,
  ) async {
    final app = AppHarness();
    app.settingsStore.saved = const AppSettings(layout: MailLayout.list);
    await app.addAccount();
    await app.pump(tester);

    // No reader column before a message is open.
    expect(find.text('Testo del messaggio 3'), findsNothing);
    await tester.tap(find.textContaining('Oggetto 3').first);
    await tester.pumpAndSettle();
    expect(find.text('Testo del messaggio 3'), findsOneWidget);
    // The list is hidden, not gone.
    expect(find.textContaining('Oggetto 4'), findsNothing);
    expect(
      find.textContaining('Oggetto 4', skipOffstage: false),
      findsOneWidget,
    );

    await tapLabel(tester, 'Indietro');
    expect(find.text('Testo del messaggio 3'), findsNothing);
    expect(find.textContaining('Oggetto 4'), findsOneWidget);
  });

  testLayout(Layout.desktop, 'switching layout applies at once', (
    tester,
  ) async {
    final app = AppHarness();
    await app.addAccount();
    await app.pump(tester);
    await tester.tap(find.textContaining('Oggetto 3').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Oggetto 4'), findsOneWidget);

    app.settings.update(app.settings.value.copyWith(layout: MailLayout.list));
    await tester.pumpAndSettle();
    expect(find.text('Testo del messaggio 3'), findsOneWidget);
    expect(find.textContaining('Oggetto 4'), findsNothing);
  });

  testLayout(Layout.desktop, '"Pagina": compose takes the area, no window', (
    tester,
  ) async {
    final app = AppHarness();
    app.settingsStore.saved = const AppSettings(compose: ComposeMode.page);
    await app.addAccount();
    await app.pump(tester);

    await tapText(tester, 'Scrivi');
    expect(find.byKey(const ValueKey('compose-window')), findsNothing);
    expect(find.text('Nuovo messaggio'), findsOneWidget);
    expect(find.textContaining('Oggetto 5'), findsNothing);

    await tapLabel(tester, 'Chiudi');
    expect(find.text('Nuovo messaggio'), findsNothing);
    expect(find.textContaining('Oggetto 5'), findsOneWidget);
  });

  testLayout(Layout.desktop, '"Solo lista": one line per message, like Gmail', (
    tester,
  ) async {
    final app = AppHarness();
    app.settingsStore.saved = const AppSettings(layout: MailLayout.list);
    final inbox = app.server..gmail = true;
    inbox.folders['INBOX']!.messages[5] = summary(
      5,
      subject: 'Un oggetto lunghissimo ' * 20,
      labels: ['Lavoro'],
    );
    await app.addAccount();
    await app.pump(tester);

    final row = find.byKey(const ValueKey('compact-row-5'));
    expect(row, findsOneWidget);
    expect(tester.getSize(row).height, 40);
    // Sender, label, subject with preview and date all on the same line.
    final y = tester.getCenter(row).dy;
    for (final f in [
      find.descendant(of: row, matching: find.text('Marta')),
      find.descendant(of: row, matching: find.text('Lavoro')),
      find.descendant(of: row, matching: find.textContaining('Anteprima 5')),
    ]) {
      expect(f, findsOneWidget);
      expect(tester.getCenter(f).dy, moreOrLessEquals(y, epsilon: 1));
    }
    // The sender column is the same width on every row, so subjects line
    // up; the long subject ends with "…" instead of overflowing.
    final sender5 = find.descendant(of: row, matching: find.text('Marta'));
    final sender4 = find.descendant(
      of: find.byKey(const ValueKey('compact-row-4')),
      matching: find.text('Marta'),
    );
    expect(tester.getTopLeft(sender5).dx, tester.getTopLeft(sender4).dx);
    final subject = tester.widget<RichText>(
      find.descendant(
        of: row,
        matching: find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('Anteprima 5'),
        ),
      ),
    );
    expect(subject.maxLines, 1);
    expect(subject.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testLayout(Layout.desktop, 'side by side keeps the two-line rows', (
    tester,
  ) async {
    final app = AppHarness();
    await app.addAccount();
    await app.pump(tester);
    expect(find.byKey(const ValueKey('compact-row-5')), findsNothing);
    expect(find.text('Oggetto 5'), findsOneWidget);
  });
}
