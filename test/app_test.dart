import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaamos_mail/src/app.dart';
import 'package:kaamos_mail/src/data/mail_cache.dart';
import 'package:kaamos_mail/src/data/secret_store.dart';

import 'mail_session_test.dart' show secondAccount;
import 'support/fakes.dart';

void main() {
  late FakeMailService server;
  late MailCache cache;
  late MemorySecretStore secrets;

  setUp(() {
    server = FakeMailService()..seed('INBOX', 5);
    cache = MailCache.inMemory();
    secrets = MemorySecretStore();
  });
  tearDown(() => cache.close());

  Future<void> pumpApp(
    WidgetTester tester, {
    required MemoryAccountRepository accounts,
    Size size = const Size(1400, 900),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      KaamosMailApp(
        accounts: accounts,
        secrets: secrets,
        cache: cache,
        services: FakeMailServiceFactory(server),
        files: FakeFileActions(),
        htmlBody: (context, doc, onLink) => const Text('HTML'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('senza portachiavi l\'app non parte e lo spiega', (tester) async {
    secrets = MemorySecretStore(available: false);
    await pumpApp(tester, accounts: MemoryAccountRepository(secrets));
    expect(find.text('Serve il portachiavi di sistema'), findsOneWidget);

    secrets.available = true;
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.text('Aggiungi un account'), findsOneWidget);
  });

  testWidgets('primo avvio: schermata per aggiungere l\'account', (
    tester,
  ) async {
    await pumpApp(tester, accounts: MemoryAccountRepository(secrets));
    expect(find.text('Aggiungi un account'), findsOneWidget);
  });

  testWidgets('desktop: tre colonne, apro un messaggio e rispondo', (
    tester,
  ) async {
    final accounts = MemoryAccountRepository(secrets);
    await accounts.save(testAccount, 'p');
    await pumpApp(tester, accounts: accounts);

    expect(find.text('Posta in arrivo'), findsWidgets);
    expect(find.text('Oggetto 5'), findsOneWidget);
    expect(find.text('Scegli un messaggio da leggere'), findsOneWidget);

    await tester.tap(find.text('Oggetto 5'));
    await tester.pumpAndSettle();
    expect(find.text('Testo del messaggio 5'), findsOneWidget);
    expect(server.folders['INBOX']!.messages[5]!.seen, isTrue);

    await tester.tap(find.bySemanticsLabel('Rispondi'));
    await tester.pumpAndSettle();
    expect(find.text('Rispondi'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Togli marta@esempio.org da A'),
      findsOneWidget,
      reason: 'chip del mittente',
    );

    await tester.tap(find.text('Invia'));
    await tester.pumpAndSettle();
    expect(server.sent.single.to.single.email, 'marta@esempio.org');
    expect(server.sent.single.subject, 'Re: Oggetto 5');
  });

  testWidgets('scrivere: indirizzo non valido blocca l\'invio', (tester) async {
    final accounts = MemoryAccountRepository(secrets);
    await accounts.save(testAccount, 'p');
    await pumpApp(tester, accounts: accounts);

    await tester.tap(find.text('Scrivi'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsLabel('Destinatari A'),
      'non-valido',
    );
    await tester.tap(find.text('Invia'));
    await tester.pumpAndSettle();
    expect(find.text('Alcuni indirizzi non sono validi.'), findsOneWidget);
    expect(server.sent, isEmpty);
  });

  testWidgets('mobile: lista, poi il messaggio in una pagina', (tester) async {
    final accounts = MemoryAccountRepository(secrets);
    await accounts.save(testAccount, 'p');
    await pumpApp(tester, accounts: accounts, size: const Size(400, 800));

    expect(find.text('Scegli un messaggio da leggere'), findsNothing);
    await tester.tap(find.text('Oggetto 4'));
    await tester.pumpAndSettle();
    expect(find.text('Testo del messaggio 4'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Indietro'));
    await tester.pumpAndSettle();
    expect(find.text('Testo del messaggio 4'), findsNothing);
    expect(find.text('Oggetto 4'), findsOneWidget);
  });

  testWidgets('più account: cambio account e aggiunta annullabile', (
    tester,
  ) async {
    final accounts = MemoryAccountRepository(secrets);
    await accounts.save(testAccount, 'p');
    await accounts.save(secondAccount, 'p');
    await pumpApp(tester, accounts: accounts);

    expect(find.text(testAccount.email), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Account ${testAccount.email}'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Lavoro, ${secondAccount.email}'));
    await tester.pumpAndSettle();
    expect(find.text(secondAccount.email), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Account ${secondAccount.email}'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aggiungi account'));
    await tester.pumpAndSettle();
    expect(find.text('Aggiungi un account'), findsOneWidget);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(find.text(secondAccount.email), findsOneWidget);
  });

  testWidgets('più account: tutte le caselle insieme', (tester) async {
    final accounts = MemoryAccountRepository(secrets);
    await accounts.save(testAccount, 'p');
    await accounts.save(secondAccount, 'p');
    await pumpApp(tester, accounts: accounts);

    await tester.tap(find.bySemanticsLabel('Tutte le caselle'));
    await tester.pumpAndSettle();
    // Lo stesso server finto per i due account: ogni messaggio c'è due
    // volte, una per account, con l'indirizzo sotto.
    expect(find.text('Oggetto 5'), findsNWidgets(2));
    expect(find.text(secondAccount.email), findsWidgets);

    await tester.tap(find.text('Oggetto 5').last);
    await tester.pumpAndSettle();
    expect(find.text('Testo del messaggio 5'), findsOneWidget);

    // Una cartella riporta alle cartelle dell'account.
    await tester.tap(find.bySemanticsLabel('Posta in arrivo'));
    await tester.pumpAndSettle();
    expect(find.text('Oggetto 5'), findsOneWidget);
  });
}
