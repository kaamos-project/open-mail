import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaamos_mail/src/core/mail_errors.dart';
import 'package:kaamos_mail/src/core/models.dart';
import 'package:kaamos_mail/src/ui/views/folder_list.dart';
import 'package:kaamos_mail/src/ui/views/label_picker.dart';
import 'package:kaamos_project_ui/kaamos_project_ui.dart';

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

/// The picker's row for [label].
Finder pickerRow(String label) =>
    find.descendant(of: find.byType(LabelPicker), matching: find.text(label));

/// Whether [label] is ticked in the picker.
bool ticked(WidgetTester tester, String label) => tester
    .widget<KaamosCheckbox>(
      find.ancestor(
        of: pickerRow(label),
        matching: find.byType(KaamosCheckbox),
      ),
    )
    .value!;

Future<void> openPicker(WidgetTester tester, String subject) async {
  await tapText(tester, subject);
  await tapLabel(tester, 'Gestisci etichette');
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

  testBothLayouts('the picker adds and removes labels at once', (
    tester,
    layout,
  ) async {
    final app = gmail();
    await app.addAccount();
    await app.pump(tester, layout: layout);
    await openPicker(tester, 'Oggetto 5');

    // Every label of the account, ticked where the message has it.
    expect(ticked(tester, 'Lavoro'), isTrue);
    expect(ticked(tester, 'Viaggi/Norvegia'), isTrue);

    await tester.tap(pickerRow('Lavoro'));
    await tester.pumpAndSettle();
    expect(ticked(tester, 'Lavoro'), isFalse);
    expect(
      app.server.folders['INBOX']!.messages[5]!.labels,
      isNot(contains('Lavoro')),
    );

    await tester.tap(pickerRow('Lavoro'));
    await tester.pumpAndSettle();
    expect(ticked(tester, 'Lavoro'), isTrue);
    expect(
      app.server.folders['INBOX']!.messages[5]!.labels,
      contains('Lavoro'),
    );
    expect(
      app.cache
          .loadSummaries(testAccount.id, 'INBOX')
          .firstWhere((m) => m.uid == 5)
          .labels,
      contains('Lavoro'),
    );
  });

  testBothLayouts('the search filters, and creates a new label', (
    tester,
    layout,
  ) async {
    final app = gmail();
    await app.addAccount();
    await app.pump(tester, layout: layout);
    await openPicker(tester, 'Oggetto 3');
    final field = find.descendant(
      of: find.byType(LabelPicker),
      matching: find.byType(EditableText),
    );

    await tester.enterText(field, 'viag');
    await tester.pumpAndSettle();
    expect(pickerRow('Viaggi/Norvegia'), findsOneWidget);
    expect(pickerRow('Lavoro'), findsNothing);
    expect(find.textContaining('Crea «'), findsOneWidget);

    await tester.enterText(field, 'Montagna');
    await tester.pumpAndSettle();
    await tapText(tester, 'Crea «Montagna»');

    expect(app.server.folders['Montagna']?.folder.isLabel, isTrue);
    expect(app.server.folders['INBOX']!.messages[3]!.labels, ['Montagna']);
    // The field empties and the new label is in the list, ticked.
    expect(ticked(tester, 'Montagna'), isTrue);
  });

  testBothLayouts('if creating fails, nothing is added', (
    tester,
    layout,
  ) async {
    final app = gmail();
    await app.addAccount();
    await app.pump(tester, layout: layout);
    await openPicker(tester, 'Oggetto 3');

    await tester.enterText(
      find.descendant(
        of: find.byType(LabelPicker),
        matching: find.byType(EditableText),
      ),
      'Montagna',
    );
    await tester.pumpAndSettle();
    app.server.failWith = const MailFailure(
      MailFailureKind.server,
      'Il server ha risposto: NO',
    );
    await tapText(tester, 'Crea «Montagna»');

    expect(app.server.folders.containsKey('Montagna'), isFalse);
    expect(app.server.folders['INBOX']!.messages[3]!.labels, isEmpty);
    expect(find.textContaining('Il server ha risposto: NO'), findsWidgets);
  });

  testLayout(Layout.phone, 'on the phone the picker is a page', (tester) async {
    final app = gmail();
    await app.addAccount();
    await app.pump(tester, layout: Layout.phone);
    await openPicker(tester, 'Oggetto 5');

    expect(framedAround(find.byType(LabelPicker)), findsNothing);
    await tapLabel(tester, 'Indietro');
    expect(find.byType(LabelPicker), findsNothing);
    expect(find.bySemanticsLabel('Togli etichetta Lavoro'), findsOneWidget);
  });

  testBothLayouts('no label button on other servers', (tester, layout) async {
    final app = AppHarness();
    await app.addAccount();
    await app.pump(tester, layout: layout);
    await tapText(tester, 'Oggetto 5');
    expect(find.bySemanticsLabel('Gestisci etichette'), findsNothing);
  });
}
