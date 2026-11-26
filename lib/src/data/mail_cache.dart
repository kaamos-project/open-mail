import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../core/mail_service.dart';
import '../core/models.dart';

/// Cache locale in SQLite: cartelle e righe della lista messaggi.
///
/// Serve a una cosa sola: aprire l'app e vedere subito la lista, mentre in
/// sottofondo si chiede al server cosa è cambiato. Il server resta la fonte
/// di verità; se cache e server non coincidono, vince il server.
///
/// I corpi dei messaggi non si salvano nell'MVP (lettura offline completa è
/// in fase 2): si scaricano quando apri il messaggio.
///
/// Perché `sqlite3` diretto e non `drift`? Niente generazione di codice e
/// SQL scritto a mano, che è anche un buon esercizio. Il prezzo: le query
/// non sono controllate a compile time, quindi i test della cache contano.
/// Le query sono sincrone sul thread della UI: con pagine da 50 righe
/// costano frazioni di millisecondo. Se un giorno diventano pesanti (ricerca
/// full-text in fase 2) si spostano in un isolate.
class MailCache {
  MailCache._(this._db) {
    _migrate();
  }

  /// Apre (o crea) il database nel file [path].
  factory MailCache.open(String path) => MailCache._(sqlite3.open(path));

  /// Database in memoria, per i test.
  factory MailCache.inMemory() => MailCache._(sqlite3.openInMemory());

  final Database _db;

  static const _schemaVersion = 1;

  void _migrate() {
    _db.execute('PRAGMA journal_mode = WAL');
    final version = _db.select('PRAGMA user_version').first.columnAt(0) as int;
    if (version >= _schemaVersion) return;
    _db.execute('''
      CREATE TABLE IF NOT EXISTS folders (
        account_id TEXT NOT NULL,
        path TEXT NOT NULL,
        name TEXT NOT NULL,
        role TEXT NOT NULL,
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
        PRIMARY KEY (account_id, path, uid)
      ) STRICT, WITHOUT ROWID;
      PRAGMA user_version = $_schemaVersion;
    ''');
  }

  /// Sostituisce l'elenco delle cartelle, tenendo lo `UIDVALIDITY` di quelle
  /// che esistono ancora.
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
        INSERT INTO folders (account_id, path, name, role) VALUES (?, ?, ?, ?)
        ON CONFLICT (account_id, path) DO UPDATE SET
          name = excluded.name, role = excluded.role
      ''');
      for (final f in folders) {
        stmt.execute([accountId, f.path, f.name, f.role.name]);
      }
      stmt.close();
    });
  }

  /// Le cartelle salvate, già ordinate.
  List<Folder> loadFolders(String accountId) {
    final rows = _db.select(
      'SELECT path, name, role FROM folders WHERE account_id = ?',
      [accountId],
    );
    final folders = [
      for (final r in rows)
        Folder(
          path: r['path'] as String,
          name: r['name'] as String,
          role: FolderRole.values.byName(r['role'] as String),
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
      ..execute('DELETE FROM folders WHERE account_id = ? AND path = ?', [
        accountId,
        path,
      ]);
  }

  /// Confronta lo `UIDVALIDITY` del server con quello salvato. Se è
  /// cambiato, gli UID in cache indicano altri messaggi (o nessuno): la
  /// cache della cartella si svuota. Restituisce `true` se l'ha svuotata.
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
          '''INSERT INTO folders (account_id, path, name, role, uid_validity)
             VALUES (?, ?, ?, 'other', ?)
             ON CONFLICT (account_id, path) DO UPDATE SET
               uid_validity = excluded.uid_validity''',
          [accountId, path, path, uidValidity],
        );
    });
    return stored != null;
  }

  /// Salva o aggiorna delle righe.
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
          date_ms, preview, seen, flagged, answered, has_attachments
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
        ]);
      }
      stmt.close();
    });
  }

  /// Le righe più recenti per data. A parità di data (o senza data) vince
  /// l'UID più alto, cioè l'ultimo arrivato.
  List<MessageSummary> loadSummaries(
    String accountId,
    String path, {
    int limit = 200,
  }) {
    final rows = _db.select(
      '''SELECT * FROM messages WHERE account_id = ? AND path = ?
         ORDER BY COALESCE(date_ms, 0) DESC, uid DESC LIMIT ?''',
      [accountId, path, limit],
    );
    return [for (final r in rows) _rowToSummary(r)];
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
    );
  }

  /// Tutti gli UID in cache per la cartella, crescenti.
  List<int> cachedUids(String accountId, String path) => [
    for (final r in _db.select(
      'SELECT uid FROM messages WHERE account_id = ? AND path = ? ORDER BY uid',
      [accountId, path],
    ))
      r['uid'] as int,
  ];

  /// Aggiorna solo i flag.
  void updateFlags(
    String accountId,
    String path,
    Map<int, MessageFlagsState> flags,
  ) {
    if (flags.isEmpty) return;
    _transaction(() {
      final stmt = _db.prepare('''
        UPDATE messages SET seen = ?, flagged = ?, answered = ?
        WHERE account_id = ? AND path = ? AND uid = ?
      ''');
      for (final MapEntry(key: uid, value: f) in flags.entries) {
        stmt.execute([
          f.seen ? 1 : 0,
          f.flagged ? 1 : 0,
          f.answered ? 1 : 0,
          accountId,
          path,
          uid,
        ]);
      }
      stmt.close();
    });
  }

  /// Toglie dalla cache i messaggi spariti dal server (o spostati).
  void removeUids(String accountId, String path, Iterable<int> uids) {
    final list = uids.toList();
    if (list.isEmpty) return;
    _transaction(() {
      final stmt = _db.prepare(
        'DELETE FROM messages WHERE account_id = ? AND path = ? AND uid = ?',
      );
      for (final uid in list) {
        stmt.execute([accountId, path, uid]);
      }
      stmt.close();
    });
  }

  /// Cancella tutto quello che riguarda un account (quando lo rimuovi).
  void deleteAccount(String accountId) {
    _transaction(() {
      _db
        ..execute('DELETE FROM messages WHERE account_id = ?', [accountId])
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

  /// Chiude il database.
  void close() => _db.close();
}
