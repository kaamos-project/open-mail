import 'package:flutter_test/flutter_test.dart';
import 'package:kaamos_mail/src/core/mail_errors.dart';
import 'package:kaamos_mail/src/core/models.dart';
import 'package:kaamos_mail/src/ui/views/folder_list.dart';

import '../support/app_harness.dart';
import '../support/fakes.dart';

/// A Gmail-like server: two label folders, message 5 in the Inbox with two
/// labels, and message 1 in "Lavoro".
AppHarness gmail() {
  final app = AppHarness();
  final s = app.server..gmail = true;
  for (final label in ['Lavoro', 'Viaggi/Norvegia']) {
    s.folders[label] = FakeFolder(
      Folder(path: label, name: label, role: FolderRole.other, isLabel: true),
    );
  }
  s.folders['INBOX']!.messages[5] = summary(
    5,
    labels: [r'\Inbox', r'\Important', 'Lavoro', 'Viaggi/Norvegia'],
  );
  s.folders['Lavoro']!.messages[1] = summary(
    1,
    subject: 'Riunione',
    labels: ['Lavoro', 'Viaggi/Norvegia'],
  );
  s.folders['Lavoro']!.bodies[1] = 'Ordine del giorno';
  return app;
}

Future<void> openFolders(WidgetTester tester, Layout layout) async {
  if (layout == Layout.phone) await tapLabel(tester, 'Cartelle');
}

void main() {
  testBothLayouts('labels show on the row and in the message', (
    tester,
    layout,
  ) async {
    final app = gmail();
    await app.addAccount();
    await app.pump(tester, layout: layout);

    expect(find.text('Lavoro'), findsWidgets);
    expect(find.text('Viaggi/Norvegia'), findsWidgets);
    expect(find.textContaining('Inbox'), findsNothing, reason: 'system label');
    expect(find.textContaining('Important'), findsNothing);

    // No X on the rows: removing by mistake from the list is too easy.
    expect(find.bySemanticsLabel(RegExp('^Togli etichetta')), findsNothing);

    await tapText(tester, 'Oggetto 5');
    // In the message each label has its X.
    expect(find.bySemanticsLabel('Togli etichetta Lavoro'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Togli etichetta Viaggi/Norvegia'),
      findsOneWidget,
    );
  });

  testBothLayouts('the X in the message removes the label', (
    tester,
    layout,
  ) async {
    final app = gmail();
    await app.addAccount();
    await app.pump(tester, layout: layout);
    await tapText(tester, 'Oggetto 5');

    await tapLabel(tester, 'Togli etichetta Lavoro');
    expect(find.bySemanticsLabel('Togli etichetta Lavoro'), findsNothing);
    expect(app.server.folders['INBOX']!.messages[5]!.labels, [
      r'\Inbox',
      r'\Important',
      'Viaggi/Norvegia',
    ], reason: 'only that label, system labels stay');
    expect(
      app.cache.loadSummaries(testAccount.id, 'INBOX').first.labels,
      isNot(contains('Lavoro')),
    );
  });

  testBothLayouts('if the server refuses, the label comes back', (
    tester,
    layout,
  ) async {
    final app = gmail();
    await app.addAccount();
    await app.pump(tester, layout: layout);
    await tapText(tester, 'Oggetto 5');

    app.server.failWith = const MailFailure(
      MailFailureKind.server,
      'Il server ha risposto: NO',
    );
    await tapLabel(tester, 'Togli etichetta Lavoro');
    expect(find.bySemanticsLabel('Togli etichetta Lavoro'), findsOneWidget);
    expect(find.textContaining('Il server ha risposto: NO'), findsWidgets);
  });

  testBothLayouts('labels have their own section, and open like folders', (
    tester,
    layout,
  ) async {
    final app = gmail();
    await app.addAccount();
    await app.pump(tester, layout: layout);
    await openFolders(tester, layout);

    expect(find.text('Etichette'), findsOneWidget);
    final section = tester.getRect(find.text('Etichette'));
    expect(
      tester.getRect(find.text('Cestino')).bottom,
      lessThanOrEqualTo(section.top),
      reason: 'labels after the system folders',
    );

    await tester.tap(
      find.descendant(
        of: find.byType(FolderList),
        matching: find.text('Lavoro'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Riunione 1'), findsOneWidget);
    // Every label shows, the open folder's one too (Alessio's choice).
    expect(
      find.bySemanticsLabel(RegExp('Etichette Lavoro, Viaggi/Norvegia')),
      findsOneWidget,
    );
  });

  testBothLayouts('removing the open label takes the message out of it', (
    tester,
    layout,
  ) async {
    final app = gmail();
    await app.addAccount();
    await app.pump(tester, layout: layout);
    await openFolders(tester, layout);
    await tester.tap(
      find.descendant(
        of: find.byType(FolderList),
        matching: find.text('Lavoro'),
      ),
    );
    await tester.pumpAndSettle();
    await tapText(tester, 'Riunione 1');

    // In the message, the folder's own label has its X too.
    await tapLabel(tester, 'Togli etichetta Lavoro');
    expect(find.text('Riunione 1'), findsNothing, reason: 'out of Lavoro');
    expect(app.server.folders['Lavoro']!.messages, isEmpty);
    // The phone goes back to the list, like after Archive.
    expect(find.bySemanticsLabel('Togli etichetta Lavoro'), findsNothing);
  });

  testBothLayouts('labels changed elsewhere update on refresh', (
    tester,
    layout,
  ) async {
    final app = gmail();
    await app.addAccount();
    await app.pump(tester, layout: layout);

    final inbox = app.server.folders['INBOX']!;
    inbox.messages[5] = inbox.messages[5]!.copyWith(
      labels: [r'\Inbox', 'Famiglia'],
    );
    await tapLabel(tester, 'Aggiorna');
    expect(find.bySemanticsLabel(RegExp('Etichette Famiglia')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Etichette .*Viaggi')), findsNothing);
  });

  testBothLayouts('other servers have no labels section', (
    tester,
    layout,
  ) async {
    final app = AppHarness();
    await app.addAccount();
    await app.pump(tester, layout: layout);
    await openFolders(tester, layout);
    expect(find.text('Etichette'), findsNothing);
  });
}
