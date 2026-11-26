import 'package:flutter_test/flutter_test.dart';
import 'package:kaamos_mail/src/core/models.dart';
import 'package:kaamos_mail/src/data/mail_cache.dart';

import 'support/fakes.dart';

void main() {
  late MailCache cache;

  setUp(() => cache = MailCache.inMemory());
  tearDown(() => cache.close());

  test('salva e rilegge i messaggi, i più recenti prima', () {
    cache.upsertSummaries('a', 'INBOX', [summary(1), summary(3), summary(2)]);
    final list = cache.loadSummaries('a', 'INBOX');
    expect(list.map((m) => m.uid), [3, 2, 1]);
    expect(list.first.subject, 'Oggetto 3');
    expect(list.first.from?.email, 'marta@esempio.org');
    expect(list.first.to.single.email, 'alessio@esempio.org');
  });

  test('limit prende solo gli ultimi N', () {
    cache.upsertSummaries('a', 'INBOX', [
      for (var i = 1; i <= 10; i++) summary(i),
    ]);
    expect(cache.loadSummaries('a', 'INBOX', limit: 3).map((m) => m.uid), [
      10,
      9,
      8,
    ]);
  });

  test('UIDVALIDITY diversa svuota la cartella', () {
    expect(cache.checkUidValidity('a', 'INBOX', 7), isFalse);
    cache.upsertSummaries('a', 'INBOX', [summary(1)]);
    expect(cache.checkUidValidity('a', 'INBOX', 7), isFalse);
    expect(cache.cachedUids('a', 'INBOX'), [1]);
    expect(cache.checkUidValidity('a', 'INBOX', 8), isTrue);
    expect(cache.cachedUids('a', 'INBOX'), isEmpty);
  });

  test('aggiorna i flag e toglie gli UID spariti', () {
    cache.upsertSummaries('a', 'INBOX', [summary(1), summary(2)]);
    cache.updateFlags('a', 'INBOX', {
      1: (seen: true, flagged: true, answered: false),
    });
    cache.removeUids('a', 'INBOX', [2]);
    final list = cache.loadSummaries('a', 'INBOX');
    expect(list, hasLength(1));
    expect(list.single.seen, isTrue);
    expect(list.single.flagged, isTrue);
  });

  test('le cartelle tornano in ordine e gli account sono separati', () {
    cache.saveFolders('a', const [
      Folder(path: 'Trash', name: 'Trash', role: FolderRole.trash),
      Folder(path: 'INBOX', name: 'INBOX', role: FolderRole.inbox),
    ]);
    cache.upsertSummaries('b', 'INBOX', [summary(1)]);
    expect(cache.loadFolders('a').first.role, FolderRole.inbox);
    expect(cache.loadSummaries('a', 'INBOX'), isEmpty);
    cache.deleteAccount('b');
    expect(cache.loadSummaries('b', 'INBOX'), isEmpty);
  });
}
