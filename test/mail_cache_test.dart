import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaamos_mail/src/core/models.dart';
import 'package:kaamos_mail/src/data/mail_cache.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/fakes.dart';

void main() {
  late MailCache cache;

  setUp(() => cache = MailCache.inMemory());
  tearDown(() => cache.close());

  test('saves and reads back messages, newest first', () {
    cache.upsertSummaries('a', 'INBOX', [summary(1), summary(3), summary(2)]);
    final list = cache.loadSummaries('a', 'INBOX');
    expect(list.map((m) => m.uid), [3, 2, 1]);
    expect(list.first.subject, 'Oggetto 3');
    expect(list.first.from?.email, 'marta@esempio.org');
    expect(list.first.to.single.email, 'alessio@esempio.org');
  });

  test('limit takes only the latest N', () {
    cache.upsertSummaries('a', 'INBOX', [
      for (var i = 1; i <= 10; i++) summary(i),
    ]);
    expect(cache.loadSummaries('a', 'INBOX', limit: 3).map((m) => m.uid), [
      10,
      9,
      8,
    ]);
  });

  test('a different UIDVALIDITY clears the folder', () {
    expect(cache.checkUidValidity('a', 'INBOX', 7), isFalse);
    cache.upsertSummaries('a', 'INBOX', [summary(1)]);
    expect(cache.checkUidValidity('a', 'INBOX', 7), isFalse);
    expect(cache.cachedUids('a', 'INBOX'), [1]);
    expect(cache.checkUidValidity('a', 'INBOX', 8), isTrue);
    expect(cache.cachedUids('a', 'INBOX'), isEmpty);
  });

  test('updates flags and removes vanished UIDs', () {
    cache.upsertSummaries('a', 'INBOX', [summary(1), summary(2)]);
    cache.updateFlags('a', 'INBOX', {
      1: (seen: true, flagged: true, answered: false, labels: null),
    });
    cache.removeUids('a', 'INBOX', [2]);
    final list = cache.loadSummaries('a', 'INBOX');
    expect(list, hasLength(1));
    expect(list.single.seen, isTrue);
    expect(list.single.flagged, isTrue);
  });

  test('folders come back sorted and accounts are separate', () {
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

  test('sorts by date, not by UID', () {
    final old = summary(1);
    final moved = MessageSummary(
      uid: 99, // high UID: it just entered the folder
      from: old.from,
      to: old.to,
      subject: 'vecchio',
      date: DateTime.utc(2020),
      preview: '',
      seen: true,
      flagged: false,
      answered: false,
      hasAttachments: false,
    );
    cache.upsertSummaries('a', 'Archive', [summary(5), moved, summary(3)]);
    expect(cache.loadSummaries('a', 'Archive').map((m) => m.uid), [5, 3, 99]);
  });

  test('date index: order, and cleanup together with messages', () {
    cache.saveArrivalDates('a', 'INBOX', {
      1: DateTime.utc(2026, 3),
      2: DateTime.utc(2026, 1),
      3: DateTime.utc(2026, 2),
    });
    expect(cache.uidsByArrival('a', 'INBOX'), [2, 3, 1]);
    expect(cache.datedUids('a', 'INBOX'), {1, 2, 3});
    cache.removeUids('a', 'INBOX', [3]);
    expect(cache.uidsByArrival('a', 'INBOX'), [2, 1]);
    cache.checkUidValidity('a', 'INBOX', 5);
    expect(cache.datedUids('a', 'INBOX'), isEmpty);
  });

  test('a version 1 cache is recreated from scratch', () async {
    final dir = await Directory.systemTemp.createTemp('kaamos_cache');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/mail.db';
    sqlite3.open(path)
      ..execute('CREATE TABLE messages (uid INTEGER); PRAGMA user_version = 1;')
      ..close();
    final upgraded = MailCache.open(path);
    addTearDown(upgraded.close);
    upgraded.upsertSummaries('a', 'INBOX', [summary(1)]);
    upgraded.saveArrivalDates('a', 'INBOX', {1: DateTime.utc(2026)});
    expect(upgraded.loadSummaries('a', 'INBOX').single.uid, 1);
  });

  test('Gmail labels are saved and refreshed with the flags', () {
    cache.upsertSummaries('a', 'INBOX', [
      summary(1, labels: [r'\Inbox', 'Lavoro']),
      summary(2),
    ]);
    expect(cache.loadSummaries('a', 'INBOX').last.labels, [
      r'\Inbox',
      'Lavoro',
    ]);

    cache.updateFlags('a', 'INBOX', {
      1: (seen: true, flagged: false, answered: false, labels: ['Viaggi']),
      // Null: a server without labels, keep what is saved.
      2: (seen: true, flagged: false, answered: false, labels: null),
    });
    final byUid = {for (final m in cache.loadSummaries('a', 'INBOX')) m.uid: m};
    expect(byUid[1]!.labels, ['Viaggi']);
    expect(byUid[2]!.labels, isEmpty);
  });

  test('label folders keep their flag', () {
    cache.saveFolders('a', const [
      Folder(path: 'INBOX', name: 'INBOX', role: FolderRole.inbox),
      Folder(
        path: 'Lavoro',
        name: 'Lavoro',
        role: FolderRole.other,
        isLabel: true,
      ),
    ]);
    final folders = cache.loadFolders('a');
    expect(folders.firstWhere((f) => f.path == 'Lavoro').isLabel, isTrue);
    expect(folders.firstWhere((f) => f.path == 'INBOX').isLabel, isFalse);
  });
}
