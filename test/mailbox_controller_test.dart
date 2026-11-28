import 'package:flutter_test/flutter_test.dart';
import 'package:kaamos_mail/src/core/mail_errors.dart';
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

  test('first start: downloads only the latest page', () async {
    await c.start();
    expect(c.folders.first.role, FolderRole.inbox);
    expect(c.messages.map((m) => m.uid).take(3), [25, 24, 23]);
    expect(c.messages, hasLength(10));
    expect(server.fetchedSummaries, 10);
    expect(c.hasMore, isTrue);
    expect(c.error, isNull);
  });

  test(
    'second start: shows the cache at once and downloads only new ones',
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
      expect(shown.first, 25, reason: 'the cache arrives before the server');
      expect(c.messages.first.uid, 26);
      expect(server.fetchedSummaries, 1);
    },
  );

  test('messages gone from the server disappear here too', () async {
    await c.start();
    server.folders['INBOX']!.messages.remove(25);
    await c.refresh();
    expect(c.messages.first.uid, 24);
    expect(cache.cachedUids(testAccount.id, 'INBOX'), isNot(contains(25)));
  });

  test('UIDVALIDITY changed: the cache is rebuilt', () async {
    await c.start();
    server
      ..folders['INBOX']!.uidValidity = 2
      ..fetchedSummaries = 0;
    await c.refresh();
    expect(server.fetchedSummaries, 10);
  });

  test('load more widens the window', () async {
    await c.start();
    await c.loadMore();
    expect(c.messages, hasLength(20));
    await c.loadMore();
    expect(c.messages, hasLength(25));
    expect(c.hasMore, isFalse);
  });

  test('opening a message marks it read, on the server too', () async {
    await c.start();
    await c.open(25);
    expect(c.openMessage?.plainText, 'Testo del messaggio 25');
    expect(c.messages.first.seen, isTrue);
    expect(server.folders['INBOX']!.messages[25]!.seen, isTrue);
  });

  test('if the server refuses, the star goes back', () async {
    await c.start();
    server.failWith = const MailFailure(
      MailFailureKind.network,
      'Server non raggiungibile.',
    );
    await c.setFlagged([25], flagged: true);
    expect(c.messages.first.flagged, isFalse);
    expect(c.error, isNotNull);
  });

  test('delete moves to Trash, from Trash deletes for good', () async {
    await c.start();
    await c.delete([25]);
    expect(c.messages.first.uid, 24);
    expect(server.folders['Trash']!.messages, hasLength(1));

    await c.selectFolder(c.folderWithRole(FolderRole.trash)!);
    expect(c.messages, hasLength(1));
    await c.delete([c.messages.single.uid]);

    expect(server.folders['Trash']!.messages, isEmpty);
  });

  test('archive moves to Archive', () async {
    await c.start();
    await c.archive([24, 23]);
    expect(server.folders['Archive']!.messages, hasLength(2));
    expect(c.messages.map((m) => m.uid), isNot(contains(24)));
  });

  test('send: copy in Sent as read, original answered', () async {
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

  test('draft in Drafts with \\Draft', () async {
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

  test('server search and back to the folder', () async {
    await c.start();
    await c.search('Oggetto 7');
    expect(c.messages.map((m) => m.uid), [7]);
    await c.search('');
    expect(c.searchQuery, isNull);
    expect(c.messages, hasLength(10));
  });

  test('a bug is shown as an internal error, not a server one', () async {
    await c.start();
    server.failWith = StateError('bug');
    await c.refresh();
    expect(c.error, startsWith("Errore interno dell'app"));
    expect(c.syncing, isFalse);
  });

  test('without network the error shows and the cache stays', () async {
    await c.start();
    server.failWith = const MailFailure(
      MailFailureKind.network,
      'Server non raggiungibile.',
    );
    await c.refresh();
    expect(c.error, isNotNull);
    expect(c.messages, hasLength(10));
  });

  test('in Archive the date counts, not when you moved it', () async {
    await c.start();
    await c.archive([24]);
    await c.archive([1]); // the oldest, archived last
    await c.selectFolder(c.folderWithRole(FolderRole.archive)!);
    // UID 1 = message 24 (recent), UID 2 = message 1 (old).
    expect(c.messages.map((m) => m.subject), ['Oggetto 24', 'Oggetto 1']);
  });

  test('the first page is the newest by date, not by UID', () async {
    // Yet UID 1 (the lowest) is the most recent mail.
    final m = server.folders['INBOX']!.messages[1]!;
    server.folders['INBOX']!.messages[1] = MessageSummary(
      uid: 1,
      from: m.from,
      to: m.to,
      subject: 'Recentissima',
      date: DateTime.utc(2027),
      preview: '',
      seen: false,
      flagged: false,
      answered: false,
      hasAttachments: false,
    );
    await c.start();
    expect(c.messages.first.subject, 'Recentissima');
    expect(c.messages, hasLength(10));
  });

  test('dates are downloaded once, then only new ones', () async {
    await c.start();
    expect(server.fetchedDates, 25);
    server.folders['INBOX']!.messages[26] = summary(26);
    await c.refresh();
    expect(server.fetchedDates, 26);
  });
}
