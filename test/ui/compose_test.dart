import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaamos_mail/src/core/models.dart';

import '../support/app_harness.dart';
import '../support/fakes.dart';

/// Opens a new message: the floating button on the phone, the button in the
/// folders on desktop. Both are labelled "Scrivi".
Future<void> startCompose(WidgetTester tester) => tapLabel(tester, 'Scrivi');

Future<void> fill(WidgetTester tester, String label, String text) async {
  await tester.enterText(find.bySemanticsLabel(label).first, text);
  await tester.pump();
}

void main() {
  testBothLayouts('a new message is sent with Cc and Bcc', (
    tester,
    layout,
  ) async {
    final app = AppHarness();
    await app.addAccount();
    await app.pump(tester, layout: layout);
    await startCompose(tester);
    expect(find.text('Nuovo messaggio'), findsOneWidget);

    await fill(tester, 'Destinatari A', 'marta@esempio.org');
    expect(find.bySemanticsLabel('Destinatari Cc'), findsNothing);
    await tapLabel(tester, 'Cc Ccn');
    await fill(tester, 'Destinatari Cc', 'luca@esempio.org');
    await fill(tester, 'Destinatari Ccn', 'nascosto@esempio.org');
    await fill(tester, 'Oggetto', 'Gita al rifugio');
    await fill(tester, 'Testo del messaggio', 'Partiamo alle 7.');
    await tapText(tester, 'Invia');

    final sent = app.server.sent.single;
    expect(sent.from.email, testAccount.email);
    expect(sent.to.single.email, 'marta@esempio.org');
    expect(sent.cc.single.email, 'luca@esempio.org');
    expect(sent.bcc.single.email, 'nascosto@esempio.org');
    expect(sent.subject, 'Gita al rifugio');
    expect(sent.body, contains('Partiamo alle 7.'));
    expect(find.text('Nuovo messaggio'), findsNothing, reason: 'closed');
  });

  testBothLayouts('attached files are sent and can be removed', (
    tester,
    layout,
  ) async {
    final app = AppHarness();
    app.files.toPick = [
      OutgoingAttachment(
        fileName: 'traccia.gpx',
        mimeType: 'application/gpx+xml',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
      OutgoingAttachment(
        fileName: 'foto.jpg',
        mimeType: 'image/jpeg',
        bytes: Uint8List.fromList([4, 5]),
      ),
    ];
    await app.addAccount();
    await app.pump(tester, layout: layout);
    await startCompose(tester);

    await tapLabel(tester, 'Allega file');
    expect(find.textContaining('traccia.gpx'), findsOneWidget);
    await tapLabel(tester, 'Togli foto.jpg');
    expect(find.textContaining('foto.jpg'), findsNothing);

    await fill(tester, 'Destinatari A', 'marta@esempio.org');
    await tapText(tester, 'Invia');
    expect(app.server.sent.single.attachments.map((a) => a.fileName), [
      'traccia.gpx',
    ]);
  });

  testBothLayouts('closing with text asks: save goes to Drafts', (
    tester,
    layout,
  ) async {
    final app = AppHarness();
    await app.addAccount();
    await app.pump(tester, layout: layout);
    await startCompose(tester);
    await fill(tester, 'Testo del messaggio', 'Da finire');

    await tapLabel(tester, 'Chiudi');
    expect(find.text('Salvare la bozza?'), findsOneWidget);
    await tapText(tester, 'Continua a scrivere');
    expect(find.text('Nuovo messaggio'), findsOneWidget);

    await tapLabel(tester, 'Chiudi');
    await tapText(tester, 'Salva');
    expect(app.server.appended.single.$1, 'Drafts');
    expect(find.text('Nuovo messaggio'), findsNothing);
  });

  testBothLayouts('closing with text: delete saves nothing', (
    tester,
    layout,
  ) async {
    final app = AppHarness();
    await app.addAccount();
    await app.pump(tester, layout: layout);
    await startCompose(tester);
    await fill(tester, 'Oggetto', 'Bozza');

    await tapLabel(tester, 'Chiudi');
    await tapText(tester, 'Elimina');
    expect(app.server.appended, isEmpty);
    expect(find.text('Nuovo messaggio'), findsNothing);
  });

  testBothLayouts('an empty message closes without asking', (
    tester,
    layout,
  ) async {
    final app = AppHarness();
    await app.addAccount();
    await app.pump(tester, layout: layout);
    await startCompose(tester);

    await tapLabel(tester, 'Chiudi');
    expect(find.text('Salvare la bozza?'), findsNothing);
    expect(find.text('Nuovo messaggio'), findsNothing);
  });

  testBothLayouts('reply goes to the sender with "Re:"', (
    tester,
    layout,
  ) async {
    final app = AppHarness();
    await app.addAccount();
    await app.pump(tester, layout: layout);
    await tapText(tester, 'Oggetto 5');

    await tapLabel(tester, 'Rispondi');
    expect(
      find.bySemanticsLabel('Togli marta@esempio.org da A'),
      findsOneWidget,
    );
    await tapText(tester, 'Invia');
    expect(app.server.sent.single.to.single.email, 'marta@esempio.org');
    expect(app.server.sent.single.subject, 'Re: Oggetto 5');
    expect(app.server.folders['INBOX']!.messages[5]!.answered, isTrue);
  });

  testBothLayouts('an invalid address blocks sending', (tester, layout) async {
    final app = AppHarness();
    await app.addAccount();
    await app.pump(tester, layout: layout);
    await startCompose(tester);

    await fill(tester, 'Destinatari A', 'non-valido');
    await tapText(tester, 'Invia');
    expect(find.text('Alcuni indirizzi non sono validi.'), findsOneWidget);
    expect(app.server.sent, isEmpty);
  });

  testBothLayouts('reply all and forward fill the message', (
    tester,
    layout,
  ) async {
    final app = AppHarness();
    final m = summary(5);
    app.server.folders['INBOX']!.messages[5] = MessageSummary(
      uid: 5,
      from: m.from,
      to: const [
        Address('alessio@esempio.org', 'Alessio'),
        Address('luca@esempio.org', 'Luca'),
      ],
      subject: m.subject,
      date: m.date,
      preview: m.preview,
      seen: false,
      flagged: false,
      answered: false,
      hasAttachments: false,
    );
    await app.addAccount();
    await app.pump(tester, layout: layout);
    await tapText(tester, 'Oggetto 5');

    await tapLabel(tester, 'Rispondi a tutti');
    expect(
      find.bySemanticsLabel('Togli marta@esempio.org da A'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('Togli luca@esempio.org')), findsOne);
    expect(
      find.bySemanticsLabel(RegExp('Togli alessio@esempio.org')),
      findsNothing,
      reason: 'not to myself',
    );
    await tapLabel(tester, 'Chiudi');
    // A reply already has text (the quote): drop it.
    if (find.text('Salvare la bozza?').evaluate().isNotEmpty) {
      await tapText(tester, 'Elimina');
    }

    await tapLabel(tester, 'Inoltra');
    // The desktop window's title is the subject, as in Gmail.
    expect(
      find.text(layout == Layout.phone ? 'Inoltra' : 'Fwd: Oggetto 5'),
      findsWidgets,
    );
    expect(find.bySemanticsLabel('Togli marta@esempio.org da A'), findsNothing);
    await fill(tester, 'Destinatari A', 'luca@esempio.org');
    await tapText(tester, 'Invia');
    expect(app.server.sent.single.subject, 'Fwd: Oggetto 5');
  });
}
