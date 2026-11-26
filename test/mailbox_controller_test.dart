import 'package:flutter_test/flutter_test.dart';
import 'package:kaamos_mail/src/core/models.dart';
import 'package:kaamos_mail/src/data/mail_cache.dart';
import 'package:kaamos_mail/src/state/mailbox_controller.dart';

import 'support/fakes.dart';

void main() {
  late FakeMailService server;
  late MailCache cache;
  late MailboxController c;

  MailboxController make({int pageSize = 10}) => MailboxController(
    account: testAccount,
    cache: cache,
    connect: () async => server,
    pageSize: pageSize,
  );

  setUp(() {
    server = FakeMailService()..seed('INBOX', 25);
    cache = MailCache.inMemory();
    c = make();
  });

  tearDown(() {
    c.dispose();
    cache.close();
  });

  test('primo avvio: scarica solo l\'ultima pagina', () async {
    await c.start();
    expect(c.folders.first.role, FolderRole.inbox);
    expect(c.messages.map((m) => m.uid).take(3), [25, 24, 23]);
    expect(c.messages, hasLength(10));
    expect(server.fetchedSummaries, 10);
    expect(c.hasMore, isTrue);
    expect(c.error, isNull);
  });

  test(
    'secondo avvio: mostra la cache subito e scarica solo i nuovi',
    () async {
      await c.start();
      c.dispose();
      server
        ..folders['INBOX']!.messages[26] = summary(26)
        ..fetchedSummaries = 0;
      c = make();
      final shown = <int>[];
      c.addListener(() {
        if (shown.isEmpty && c.messages.isNotEmpty) {
          shown.add(c.messages.first.uid);
        }
      });
      await c.start();
      expect(shown.first, 25, reason: 'la cache arriva prima del server');
      expect(c.messages.first.uid, 26);
      expect(server.fetchedSummaries, 1);
    },
  );

  test('i messaggi spariti dal server spariscono anche qui', () async {
    await c.start();
    server.folders['INBOX']!.messages.remove(25);
    await c.refresh();
    expect(c.messages.first.uid, 24);
    expect(cache.cachedUids(testAccount.id, 'INBOX'), isNot(contains(25)));
  });

  test('UIDVALIDITY cambiata: la cache si ricostruisce', () async {
    await c.start();
    server
      ..folders['INBOX']!.uidValidity = 2
      ..fetchedSummaries = 0;
    await c.refresh();
    expect(server.fetchedSummaries, 10);
  });

  test('Carica altri allarga la finestra', () async {
    await c.start();
    await c.loadMore();
    expect(c.messages, hasLength(20));
    await c.loadMore();
    expect(c.messages, hasLength(25));
    expect(c.hasMore, isFalse);
  });

  test('aprire un messaggio lo segna letto, anche sul server', () async {
    await c.start();
    await c.open(25);
    expect(c.openMessage?.plainText, 'Testo del messaggio 25');
    expect(c.messages.first.seen, isTrue);
    expect(server.folders['INBOX']!.messages[25]!.seen, isTrue);
  });

  test('se il server rifiuta, la stella torna com\'era', () async {
    await c.start();
    server.failWith = Exception('rete giù');
    await c.setFlagged([25], flagged: true);
    expect(c.messages.first.flagged, isFalse);
    expect(c.error, isNotNull);
  });

  test('elimina sposta nel Cestino, dal Cestino cancella per sempre', () async {
    await c.start();
    await c.delete([25]);
    expect(c.messages.first.uid, 24);
    expect(server.folders['Trash']!.messages, hasLength(1));

    await c.selectFolder(c.folderWithRole(FolderRole.trash)!);
    expect(c.messages, hasLength(1));
    await c.delete([c.messages.single.uid]);

    expect(server.folders['Trash']!.messages, isEmpty);
  });

  test('archivia sposta in Archivio', () async {
    await c.start();
    await c.archive([24, 23]);
    expect(server.folders['Archive']!.messages, hasLength(2));
    expect(c.messages.map((m) => m.uid), isNot(contains(24)));
  });

  test('invio: copia in Inviati come letta, originale risposto', () async {
    await c.start();
    await c.send(
      const OutgoingMessage(
        from: Address('alessio@esempio.org'),
        to: [Address('marta@esempio.org')],
        bcc: [Address('nascosto@esempio.org')],
        subject: 'Re: Oggetto 25',
        body: 'Ok!',
      ),
      answeredUid: 25,
    );
    await pumpEventQueue();
    expect(server.sent, hasLength(1));
    expect(server.appended.single.$1, 'Sent');
    expect(server.appended.single.$2, contains(r'\Seen'));
    expect(server.folders['INBOX']!.messages[25]!.answered, isTrue);
  });

  test('bozza in Bozze con \\Draft', () async {
    await c.start();
    final ok = await c.saveDraft(
      const OutgoingMessage(
        from: Address('alessio@esempio.org'),
        to: [],
        subject: 'Bozza',
        body: '...',
      ),
    );
    expect(ok, isTrue);
    expect(server.appended.single.$1, 'Drafts');
    expect(server.appended.single.$2, contains(r'\Draft'));
  });

  test('ricerca sul server e ritorno alla cartella', () async {
    await c.start();
    await c.search('Oggetto 7');
    expect(c.messages.map((m) => m.uid), [7]);
    await c.search('');
    expect(c.searchQuery, isNull);
    expect(c.messages, hasLength(10));
  });

  test('senza rete l\'errore si vede e la cache resta', () async {
    await c.start();
    server.failWith = Exception('offline');
    await c.refresh();
    expect(c.error, isNotNull);
    expect(c.messages, hasLength(10));
  });

  test('in Archivio conta la data, non quando l\'hai spostata', () async {
    await c.start();
    await c.archive([24]);
    await c.archive([1]); // il più vecchio, archiviato per ultimo
    await c.selectFolder(c.folderWithRole(FolderRole.archive)!);
    // UID 1 = messaggio 24 (recente), UID 2 = messaggio 1 (vecchio).
    expect(c.messages.map((m) => m.subject), ['Oggetto 24', 'Oggetto 1']);
  });
}
