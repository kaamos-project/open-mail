import 'package:flutter_test/flutter_test.dart';
import 'package:kaamos_mail/src/core/models.dart';
import 'package:kaamos_mail/src/data/mail_cache.dart';
import 'package:kaamos_mail/src/data/secret_store.dart';
import 'package:kaamos_mail/src/state/mail_session.dart';

import 'support/fakes.dart';

const secondAccount = Account(
  id: 'acc2',
  displayName: 'Lavoro',
  email: 'alessio@lavoro.it',
  username: 'alessio@lavoro.it',
  imap: ServerConfig(
    host: 'imap.lavoro.it',
    port: 993,
    security: ConnectionSecurity.tls,
  ),
  smtp: ServerConfig(
    host: 'smtp.lavoro.it',
    port: 465,
    security: ConnectionSecurity.tls,
  ),
);

void main() {
  late MailCache cache;
  late MemoryAccountRepository repo;
  late MailSession session;

  setUp(() async {
    cache = MailCache.inMemory();
    repo = MemoryAccountRepository(MemorySecretStore());
    await repo.save(testAccount, 'p1');
    await repo.save(secondAccount, 'p2');
    session = MailSession(
      repository: repo,
      cache: cache,
      services: FakeMailServiceFactory(FakeMailService()..seed('INBOX', 3)),
    );
    await session.load();
  });

  tearDown(() {
    session.dispose();
    cache.close();
  });

  test('starts from the first account and switches with select', () {
    expect(session.active?.id, testAccount.id);
    session.select(secondAccount.id);
    expect(session.active?.id, secondAccount.id);
    expect(session.controller?.account.id, secondAccount.id);
  });

  test('one controller per account, reused', () {
    final a = session.controllerFor(testAccount);
    expect(session.controllerFor(testAccount), same(a));
    expect(session.controllerFor(secondAccount), isNot(same(a)));
  });

  test('an added account becomes the one shown', () {
    const third = Account(
      id: 'acc3',
      displayName: 'Foto',
      email: 'foto@esempio.org',
      username: 'foto@esempio.org',
      imap: ServerConfig(
        host: 'imap.esempio.org',
        port: 993,
        security: ConnectionSecurity.tls,
      ),
      smtp: ServerConfig(
        host: 'smtp.esempio.org',
        port: 465,
        security: ConnectionSecurity.tls,
      ),
    );
    session.added(third);
    expect(session.accounts, hasLength(3));
    expect(session.active?.id, 'acc3');
  });

  test('removing deletes password and cache and switches to another', () async {
    session.select(secondAccount.id);
    session.controllerFor(secondAccount); // it starts by itself
    await pumpEventQueue();
    expect(cache.loadSummaries(secondAccount.id, 'INBOX'), isNotEmpty);

    await session.remove(secondAccount.id);
    expect(session.accounts.map((a) => a.id), [testAccount.id]);
    expect(session.active?.id, testAccount.id);
    expect(await repo.password(secondAccount.id), isNull);
    expect(cache.loadSummaries(secondAccount.id, 'INBOX'), isEmpty);
  });
}
