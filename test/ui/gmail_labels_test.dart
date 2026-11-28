import 'package:flutter_test/flutter_test.dart';
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

    await tapText(tester, 'Oggetto 5');
    expect(
      find.bySemanticsLabel('Etichette: Lavoro, Viaggi/Norvegia'),
      findsWidgets,
    );
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
    // In "Lavoro" every message has that label: only the others show.
    expect(
      find.bySemanticsLabel(RegExp('Etichette Viaggi/Norvegia')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('Etichette Lavoro')), findsNothing);
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
