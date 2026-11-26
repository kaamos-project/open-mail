import 'package:flutter_test/flutter_test.dart';
import 'package:kaamos_mail/src/core/models.dart';
import 'package:kaamos_mail/src/data/mail_cache.dart';
import 'package:kaamos_mail/src/data/secret_store.dart';
import 'package:kaamos_mail/src/state/mail_session.dart';
import 'package:kaamos_mail/src/state/mailbox_controller.dart';
import 'package:kaamos_mail/src/state/unified_inbox.dart';

import 'mail_session_test.dart' show secondAccount;
import 'support/fakes.dart';

void main() {
  late MailCache cache;
  late FakeMailService personal;
  late FakeMailService work;
  late MailboxController a;
  late MailboxController b;
  late UnifiedInbox unified;

  List<String> order() => [
    for (final i in unified.items) '${i.account.id}:${i.summary.uid}',
  ];

  setUp(() async {
    cache = MailCache.inMemory();
    // Personale: UID 1-3 (minuti 1-3). Lavoro: UID 3-5 (minuti 3-5).
    personal = FakeMailService()..seed('INBOX', 3);
    work = FakeMailService()..seed('INBOX', 5);
    work.folders['INBOX']!.messages
      ..remove(1)
      ..remove(2);
    a = MailboxController(
      account: testAccount,
      cache: cache,
      connect: () async => personal,
    );
    b = MailboxController(
      account: secondAccount,
      cache: cache,
      connect: () async => work,
    );
    await Future.wait([a.start(), b.start()]);
    unified = UnifiedInbox(controllers: [a, b]);
  });

  tearDown(() {
    unified.dispose();
    a.dispose();
    b.dispose();
    cache.close();
  });

  test('mescola le Inbox per data di arrivo', () {
    expect(order(), [
      'acc2:5',
      'acc2:4',
      // Stessa data: prima l'account con l'id più piccolo.
      'acc1:3',
      'acc2:3',
      'acc1:2',
      'acc1:1',
    ]);
  });

  test(
    'le azioni vanno nella Inbox anche se l\'account guarda altro',
    () async {
      final sent = a.folderWithRole(FolderRole.sent)!;
      await a.selectFolder(sent);
      final item = unified.items.firstWhere((i) => i.account.id == 'acc1');

      await unified.openItem(item);
      expect(a.openPath, 'INBOX');
      expect(a.openMessage?.plainText, 'Testo del messaggio 3');
      expect(personal.folders['INBOX']!.messages[3]!.seen, isTrue);

      await a.setFlagged([3], flagged: true, path: a.openPath);
      expect(personal.folders['INBOX']!.messages[3]!.flagged, isTrue);
      expect(
        unified.items.firstWhere((i) => i.summary.uid == 3).summary.flagged,
        isTrue,
        reason: 'la vista si rilegge dalla cache',
      );

      await a.delete([3], path: a.openPath);
      expect(personal.folders['INBOX']!.messages.containsKey(3), isFalse);
      expect(personal.folders['Trash']!.messages, hasLength(1));
      expect(order(), isNot(contains('acc1:3')));
      expect(a.openUid, isNull, reason: 'il messaggio aperto è sparito');
      expect(a.current.path, sent.path, reason: 'la cartella aperta resta');
    },
  );

  test('se il server rifiuta, il messaggio torna nella vista', () async {
    personal.failWith = StateError('giù');
    await a.archive([2], path: 'INBOX');
    expect(order(), contains('acc1:2'));
    expect(unified.error, startsWith(testAccount.email));
  });

  test('aggiorna le Inbox senza cambiare cartella', () async {
    final sent = a.folderWithRole(FolderRole.sent)!;
    await a.selectFolder(sent);
    personal.folders['INBOX']!.messages[9] = summary(9);
    await unified.refresh();
    expect(order().first, 'acc1:9');
    expect(a.current.path, sent.path);
    expect(a.messages, isEmpty, reason: 'la lista resta quella di Inviati');
  });

  test(
    'aprire un messaggio di un altro account chiude il precedente',
    () async {
      await unified.openItem(
        unified.items.firstWhere((i) => i.controller == a),
      );
      await unified.openItem(
        unified.items.firstWhere((i) => i.controller == b),
      );
      expect(a.openUid, isNull);
      expect(unified.openController, same(b));
      expect(unified.open, (accountId: 'acc2', uid: 5));
    },
  );

  group('MailSession', () {
    late MailSession session;

    setUp(() async {
      final repo = MemoryAccountRepository(MemorySecretStore());
      await repo.save(testAccount, 'p1');
      await repo.save(secondAccount, 'p2');
      session = MailSession(
        repository: repo,
        cache: cache,
        services: FakeMailServiceFactory(FakeMailService()..seed('INBOX', 3)),
      );
      await session.load();
    });

    tearDown(() => session.dispose());

    test('entra ed esce dalla vista unificata', () async {
      expect(session.canUnify, isTrue);
      session.showUnified();
      expect(session.unified?.controllers, hasLength(2));
      session.select(testAccount.id);
      expect(session.unified, isNull, reason: 'scegliere un account esce');
      session.showUnified();
      session.leaveUnified();
      expect(session.unified, isNull);
    });

    test('con un account solo la vista unificata si chiude', () async {
      session.showUnified();
      await session.remove(secondAccount.id);
      expect(session.canUnify, isFalse);
      expect(session.unified, isNull);
      session.showUnified();
      expect(session.unified, isNull);
    });
  });
}
