import 'package:flutter_test/flutter_test.dart';
import 'package:kaamos_mail/src/core/models.dart';

import '../support/app_harness.dart';

void main() {
  testBothLayouts('opening a message marks it read', (tester, layout) async {
    final app = AppHarness();
    await app.addAccount();
    await app.pump(tester, layout: layout);

    await tapText(tester, 'Oggetto 3');
    expect(find.text('Testo del messaggio 3'), findsOneWidget);
    expect(app.server.folders['INBOX']!.messages[3]!.seen, isTrue);
  });

  testBothLayouts('star and mark unread from the toolbar', (
    tester,
    layout,
  ) async {
    final app = AppHarness();
    await app.addAccount();
    await app.pump(tester, layout: layout);
    await tapText(tester, 'Oggetto 2');

    await tapLabel(tester, 'Metti la stella');
    expect(app.server.folders['INBOX']!.messages[2]!.flagged, isTrue);
    expect(find.bySemanticsLabel('Togli la stella'), findsWidgets);

    await tapLabel(tester, 'Segna come non letto');
    expect(app.server.folders['INBOX']!.messages[2]!.seen, isFalse);
  });

  testBothLayouts('archive moves the message out of the Inbox', (
    tester,
    layout,
  ) async {
    final app = AppHarness();
    await app.addAccount();
    await app.pump(tester, layout: layout);
    await tapText(tester, 'Oggetto 4');

    await tapLabel(tester, 'Archivia');
    expect(app.server.folders['INBOX']!.messages.containsKey(4), isFalse);
    expect(
      app.server.folders['Archive']!.messages.values.map((m) => m.subject),
      contains('Oggetto 4'),
    );
    expect(find.text('Oggetto 4'), findsNothing);
  });

  testBothLayouts('trash moves the message to the Trash', (
    tester,
    layout,
  ) async {
    final app = AppHarness();
    await app.addAccount();
    await app.pump(tester, layout: layout);
    await tapText(tester, 'Oggetto 1');

    await tapLabel(tester, 'Sposta nel cestino');
    expect(app.server.folders['INBOX']!.messages.containsKey(1), isFalse);
    expect(
      app.server.folders['Trash']!.messages.values.map((m) => m.subject),
      contains('Oggetto 1'),
    );
  });

  testBothLayouts('attachments open with the system app', (
    tester,
    layout,
  ) async {
    final app = AppHarness();
    app.server.folders['INBOX']!.attachments[5] = const [
      AttachmentInfo(
        fetchId: '2',
        fileName: 'traccia.gpx',
        size: 2048,
        mimeType: 'application/gpx+xml',
      ),
    ];
    await app.addAccount();
    await app.pump(tester, layout: layout);
    await tapText(tester, 'Oggetto 5');

    await tester.tap(find.textContaining('traccia.gpx').first);
    await tester.pumpAndSettle();
    expect(app.files.openedFiles, ['traccia.gpx']);
  });

  testBothLayouts('remote images are blocked until asked', (
    tester,
    layout,
  ) async {
    final app = AppHarness();
    app.server.folders['INBOX']!.html[5] =
        '<p>Ciao</p><img src="https://tracker.example/pixel.png">';
    await app.addAccount();
    await app.pump(tester, layout: layout);
    await tapText(tester, 'Oggetto 5');

    expect(
      find.textContaining('Ho bloccato 1 immagini remote'),
      findsOneWidget,
    );
    await tapText(tester, 'Carica immagini');
    expect(find.textContaining('Ho bloccato'), findsNothing);
  });
}
