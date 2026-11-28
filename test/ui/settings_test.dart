import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaamos_mail/src/core/settings.dart';

import '../support/app_harness.dart';

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
    expect(find.text('Oggetto 5'), findsOneWidget);
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
    await tapText(tester, 'Oggetto 3');
    expect(find.text('Testo del messaggio 3'), findsOneWidget);
    // The list is hidden, not gone.
    expect(find.text('Oggetto 4'), findsNothing);
    expect(find.text('Oggetto 4', skipOffstage: false), findsOneWidget);

    await tapLabel(tester, 'Indietro');
    expect(find.text('Testo del messaggio 3'), findsNothing);
    expect(find.text('Oggetto 4'), findsOneWidget);
  });

  testLayout(Layout.desktop, 'switching layout applies at once', (
    tester,
  ) async {
    final app = AppHarness();
    await app.addAccount();
    await app.pump(tester);
    await tapText(tester, 'Oggetto 3');
    expect(find.text('Oggetto 4'), findsOneWidget);

    app.settings.update(app.settings.value.copyWith(layout: MailLayout.list));
    await tester.pumpAndSettle();
    expect(find.text('Testo del messaggio 3'), findsOneWidget);
    expect(find.text('Oggetto 4'), findsNothing);
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
    expect(find.text('Oggetto 5'), findsNothing);

    await tapLabel(tester, 'Chiudi');
    expect(find.text('Nuovo messaggio'), findsNothing);
    expect(find.text('Oggetto 5'), findsOneWidget);
  });
}
