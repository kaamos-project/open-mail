import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../core/mail_service.dart';
import '../core/models.dart';

/// Local SQLite cache: folders and message list rows.
///
/// It serves a single purpose: open the app and see the list immediately, while
/// the server is asked in the background what changed. The server stays the
/// source of truth; if cache and server disagree, the server wins.
///
/// Message bodies are not stored in the MVP (full offline reading is phase 2):
/// they are downloaded when you open the message.
///
/// Why plain `sqlite3` and not `drift`? No code generation and hand-written
/// SQL, which is also good practice. The price: queries aren't checked at
/// compile time, so the cache tests matter. Queries run synchronously on the UI
/// thread: with 50-row pages they cost fractions of a millisecond. If they ever
/// get heavy (full-text search in phase 2) they move to an isolate.
class MailCache {
  MailCache._(this._db) {
    _migrate();
  }

  /// Opens (or creates) the database in the file [path].
  factory MailCache.open(String path) => MailCache._(sqlite3.open(path));

  /// In-memory database, for tests.
  factory MailCache.inMemory() => MailCache._(sqlite3.openInMemory());

  final Database _db;

  static const _schemaVersion = 3;

  void _migrate() {
    _db.execute('PRAGMA journal_mode = WAL');
    final version = _db.select('PRAGMA user_version').first.columnAt(0) as int;
    if (version >= _schemaVersion) return;
    // It's a cache: instead of migrating data we start over and download
    // everything again from the server. Much simpler and risk free.
    _db.execute('''
      DROP TABLE IF EXISTS messages;
      DROP TABLE IF EXISTS folders;
      DROP TABLE IF EXISTS arrival_dates;
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS folders (
        account_id TEXT NOT NULL,
        path TEXT NOT NULL,
        name TEXT NOT NULL,
        role TEXT NOT NULL,
        is_label INTEGER NOT NULL DEFAULT 0,
        uid_validity INTEGER,
        PRIMARY KEY (account_id, path)
      ) STRICT;
      CREATE TABLE IF NOT EXISTS messages (
        account_id TEXT NOT NULL,
        path TEXT NOT NULL,
        uid INTEGER NOT NULL,
        from_email TEXT,
        from_name TEXT,
        to_json TEXT NOT NULL,
        subject TEXT NOT NULL,
        date_ms INTEGER,
        preview TEXT NOT NULL,
        seen INTEGER NOT NULL,
        flagged INTEGER NOT NULL,
        answered INTEGER NOT NULL,
        has_attachments INTEGER NOT NULL,
        labels_json TEXT NOT NULL DEFAULT '[]',
        PRIMARY KEY (account_id, path, uid)
      ) STRICT, WITHOUT ROWID;
      -- Indice leggero di TUTTI i messaggi della cartella (anche quelli
      -- mai mostrati): uid -> data di arrivo, per ordinare e paginare per
      -- data su qualsiasi server.
      CREATE TABLE IF NOT EXISTS arrival_dates (
        account_id TEXT NOT NULL,
        path TEXT NOT NULL,
        uid INTEGER NOT NULL,
        arrival_ms INTEGER NOT NULL,
        PRIMARY KEY (account_id, path, uid)
      ) STRICT, WITHOUT ROWID;
      CREATE INDEX IF NOT EXISTS arrival_order
        ON arrival_dates (account_id, path, arrival_ms, uid);
      PRAGMA user_version = $_schemaVersion;
    ''');
  }

  /// Replaces the folder list, keeping the `UIDVALIDITY` of the folders that
  /// still exist.
  void saveFolders(String accountId, List<Folder> folders) {
    _transaction(() {
      final keep = folders.map((f) => f.path).toSet();
      for (final row in _db.select(
        'SELECT path FROM folders WHERE account_id = ?',
        [accountId],
      )) {
        final path = row['path'] as String;
        if (!keep.contains(path)) _forgetFolder(accountId, path);
      }
      final stmt = _db.prepare('''
        INSERT INTO folders (account_id, path, name, role, is_label)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT (account_id, path) DO UPDATE SET
          name = excluded.name, role = excluded.role,
          is_label = excluded.is_label
      ''');
      for (final f in folders) {
        stmt.execute([
          accountId,
          f.path,
          f.name,
          f.role.name,
          if (f.isLabel) 1 else 0,
        ]);
      }
      stmt.close();
    });
  }

  /// The saved folders, already sorted.
  List<Folder> loadFolders(String accountId) {
    final rows = _db.select(
      'SELECT path, name, role, is_label FROM folders WHERE account_id = ?',
      [accountId],
    );
    final folders = [
      for (final r in rows)
        Folder(
          path: r['path'] as String,
          name: r['name'] as String,
          role: FolderRole.values.byName(r['role'] as String),
          isLabel: r['is_label'] == 1,
        ),
    ];
    folders.sort((a, b) {
      final byRole = a.role.index.compareTo(b.role.index);
      return byRole != 0
          ? byRole
          : a.path.toLowerCase().compareTo(b.path.toLowerCase());
    });
    return folders;
  }

  void _forgetFolder(String accountId, String path) {
    _db
      ..execute('DELETE FROM messages WHERE account_id = ? AND path = ?', [
        accountId,
        path,
      ])
      ..execute('DELETE FROM arrival_dates WHERE account_id = ? AND path = ?', [
        accountId,
        path,
      ])
      ..execute('DELETE FROM folders WHERE account_id = ? AND path = ?', [
        accountId,
        path,
      ]);
  }

  /// Compares the server's `UIDVALIDITY` with the saved one. If it changed, the
  /// cached UIDs point to other messages (or none): the folder cache is
  /// cleared. Returns `true` if it was cleared.
  bool checkUidValidity(String accountId, String path, int uidValidity) {
    final rows = _db.select(
      'SELECT uid_validity FROM folders WHERE account_id = ? AND path = ?',
      [accountId, path],
    );
    final stored = rows.isEmpty ? null : rows.first['uid_validity'] as int?;
    if (stored == uidValidity) return false;
    _transaction(() {
      _db
        ..execute('DELETE FROM messages WHERE account_id = ? AND path = ?', [
          accountId,
          path,
        ])
        ..execute(
          'DELETE FROM arrival_dates WHERE account_id = ? AND path = ?',
          [accountId, path],
        )
        ..execute(
          '''INSERT INTO folders (account_id, path, name, role, uid_validity)
             VALUES (?, ?, ?, 'other', ?)
             ON CONFLICT (account_id, path) DO UPDATE SET
               uid_validity = excluded.uid_validity''',
          [accountId, path, path, uidValidity],
        );
    });
    return stored != null;
  }

  /// Saves or updates rows.
  void upsertSummaries(
    String accountId,
    String path,
    List<MessageSummary> summaries,
  ) {
    if (summaries.isEmpty) return;
    _transaction(() {
      final stmt = _db.prepare('''
        INSERT OR REPLACE INTO messages (
          account_id, path, uid, from_email, from_name, to_json, subject,
          date_ms, preview, seen, flagged, answered, has_attachments,
          labels_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''');
      for (final s in summaries) {
        stmt.execute([
          accountId,
          path,
          s.uid,
          s.from?.email,
          s.from?.name,
          jsonEncode([
            for (final a in s.to) {'e': a.email, 'n': a.name},
          ]),
          s.subject,
          s.date?.millisecondsSinceEpoch,
          s.preview,
          s.seen ? 1 : 0,
          s.flagged ? 1 : 0,
          s.answered ? 1 : 0,
          s.hasAttachments ? 1 : 0,
          jsonEncode(s.labels),
        ]);
      }
      stmt.close();
    });
  }

  /// The newest rows by arrival date (from the index; if missing, the mail's
  /// date). On a tie the higher UID wins.
  List<MessageSummary> loadSummaries(
    String accountId,
    String path, {
    int limit = 200,
  }) => [for (final (m, _) in loadSorted(accountId, path, limit: limit)) m];

  /// Like [loadSummaries], with the date used for sorting (milliseconds): the
  /// unified Inbox uses it to merge several accounts in the same order.
  List<(MessageSummary, int)> loadSorted(
    String accountId,
    String path, {
    int limit = 200,
  }) {
    final rows = _db.select(
      '''SELECT m.*, COALESCE(d.arrival_ms, m.date_ms, 0) AS sort_ms
         FROM messages m
         LEFT JOIN arrival_dates d USING (account_id, path, uid)
         WHERE m.account_id = ? AND m.path = ?
         ORDER BY sort_ms DESC, m.uid DESC
         LIMIT ?''',
      [accountId, path, limit],
    );
    return [for (final r in rows) (_rowToSummary(r), r['sort_ms'] as int)];
  }

  /// The saved rows for these UIDs (the ones that exist).
  List<MessageSummary> summariesFor(
    String accountId,
    String path,
    Iterable<int> uids,
  ) {
    final stmt = _db.prepare(
      'SELECT * FROM messages WHERE account_id = ? AND path = ? AND uid = ?',
    );
    final result = <MessageSummary>[];
    for (final uid in uids) {
      for (final r in stmt.select([accountId, path, uid])) {
        result.add(_rowToSummary(r));
      }
    }
    stmt.close();
    return result;
  }

  static MessageSummary _rowToSummary(Row r) {
    final fromEmail = r['from_email'] as String?;
    final dateMs = r['date_ms'] as int?;
    return MessageSummary(
      uid: r['uid'] as int,
      from: fromEmail == null
          ? null
          : Address(fromEmail, r['from_name'] as String?),
      to: [
        for (final a
            in (jsonDecode(r['to_json'] as String) as List<Object?>)
                .cast<Map<String, Object?>>())
          Address(a['e']! as String, a['n'] as String?),
      ],
      subject: r['subject'] as String,
      date: dateMs == null ? null : DateTime.fromMillisecondsSinceEpoch(dateMs),
      preview: r['preview'] as String,
      seen: r['seen'] == 1,
      flagged: r['flagged'] == 1,
      answered: r['answered'] == 1,
      hasAttachments: r['has_attachments'] == 1,
      labels: (jsonDecode(r['labels_json'] as String) as List<Object?>)
          .cast<String>(),
    );
  }

  /// All cached UIDs for the folder, ascending.
  List<int> cachedUids(String accountId, String path) => [
    for (final r in _db.select(
      'SELECT uid FROM messages WHERE account_id = ? AND path = ? ORDER BY uid',
      [accountId, path],
    ))
      r['uid'] as int,
  ];

  /// The UIDs that already have an arrival date in the index.
  Set<int> datedUids(String accountId, String path) => {
    for (final r in _db.select(
      'SELECT uid FROM arrival_dates WHERE account_id = ? AND path = ?',
      [accountId, path],
    ))
      r['uid'] as int,
  };

  /// Saves arrival dates in the index.
  void saveArrivalDates(
    String accountId,
    String path,
    Map<int, DateTime> dates,
  ) {
    if (dates.isEmpty) return;
    _transaction(() {
      final stmt = _db.prepare('''
        INSERT INTO arrival_dates (account_id, path, uid, arrival_ms)
        VALUES (?, ?, ?, ?)
        ON CONFLICT (account_id, path, uid) DO UPDATE SET
          arrival_ms = excluded.arrival_ms
      ''');
      for (final MapEntry(key: uid, value: date) in dates.entries) {
        stmt.execute([accountId, path, uid, date.millisecondsSinceEpoch]);
      }
      stmt.close();
    });
  }

  /// The UIDs in the index from oldest to newest by arrival date.
  List<int> uidsByArrival(String accountId, String path) => [
    for (final r in _db.select(
      '''SELECT uid FROM arrival_dates WHERE account_id = ? AND path = ?
         ORDER BY arrival_ms, uid''',
      [accountId, path],
    ))
      r['uid'] as int,
  ];

  /// Updates only the flags.
  void updateFlags(
    String accountId,
    String path,
    Map<int, MessageFlagsState> flags,
  ) {
    if (flags.isEmpty) return;
    _transaction(() {
      final stmt = _db.prepare('''
        UPDATE messages SET seen = ?, flagged = ?, answered = ?,
          labels_json = COALESCE(?, labels_json)
        WHERE account_id = ? AND path = ? AND uid = ?
      ''');
      for (final MapEntry(key: uid, value: f) in flags.entries) {
        final labels = f.labels;
        stmt.execute([
          f.seen ? 1 : 0,
          f.flagged ? 1 : 0,
          f.answered ? 1 : 0,
          // Null: the server has no labels, keep what is saved.
          labels == null ? null : jsonEncode(labels),
          accountId,
          path,
          uid,
        ]);
      }
      stmt.close();
    });
  }

  /// Removes from the cache (rows and date index) the messages that disappeared
  /// from the server (or were moved).
  void removeUids(String accountId, String path, Iterable<int> uids) {
    final list = uids.toList();
    if (list.isEmpty) return;
    _transaction(() {
      final messages = _db.prepare(
        'DELETE FROM messages WHERE account_id = ? AND path = ? AND uid = ?',
      );
      final dates = _db.prepare(
        'DELETE FROM arrival_dates '
        'WHERE account_id = ? AND path = ? AND uid = ?',
      );
      for (final uid in list) {
        messages.execute([accountId, path, uid]);
        dates.execute([accountId, path, uid]);
      }
      messages.close();
      dates.close();
    });
  }

  /// Deletes everything about an account (when you remove it).
  void deleteAccount(String accountId) {
    _transaction(() {
      _db
        ..execute('DELETE FROM messages WHERE account_id = ?', [accountId])
        ..execute('DELETE FROM arrival_dates WHERE account_id = ?', [accountId])
        ..execute('DELETE FROM folders WHERE account_id = ?', [accountId]);
    });
  }

  void _transaction(void Function() body) {
    _db.execute('BEGIN');
    try {
      body();
      _db.execute('COMMIT');
    } on Object {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Closes the database.
  void close() => _db.close();
}
