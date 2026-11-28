import 'dart:io';
import 'dart:typed_data';

import 'package:kaamos_mail/src/core/mail_service.dart';
import 'package:kaamos_mail/src/core/models.dart';
import 'package:kaamos_mail/src/data/account_repository.dart';
import 'package:kaamos_mail/src/data/secret_store.dart';
import 'package:kaamos_mail/src/ui/environment.dart';

/// A sample account.
const testAccount = Account(
  id: 'acc1',
  displayName: 'Alessio Test',
  email: 'alessio@esempio.org',
  username: 'alessio@esempio.org',
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

/// A sample message with UID [uid].
MessageSummary summary(
  int uid, {
  String subject = 'Oggetto',
  bool seen = false,
  String from = 'marta@esempio.org',
}) => MessageSummary(
  uid: uid,
  from: Address(from, 'Marta'),
  to: const [Address('alessio@esempio.org', 'Alessio')],
  subject: '$subject $uid',
  date: DateTime.utc(2026, 11, 20, 10, uid % 60),
  preview: 'Anteprima $uid',
  seen: seen,
  flagged: false,
  answered: false,
  hasAttachments: false,
);

/// A folder of the fake server.
class FakeFolder {
  /// Creates the folder.
  FakeFolder(this.folder, {this.uidValidity = 1});

  /// The folder.
  final Folder folder;

  /// UIDVALIDITY.
  int uidValidity;

  /// Messages by UID.
  final Map<int, MessageSummary> messages = {};

  /// Message text by UID.
  final Map<int, String> bodies = {};

  /// HTML body by UID, for messages that have one.
  final Map<int, String> html = {};

  /// Attachments by UID.
  final Map<int, List<AttachmentInfo>> attachments = {};
}

/// An in-memory IMAP/SMTP server.
class FakeMailService implements MailService {
  /// Creates the server with Inbox, Sent, Drafts, Archive and Trash.
  FakeMailService() {
    for (final f in const [
      Folder(path: 'INBOX', name: 'INBOX', role: FolderRole.inbox),
      Folder(path: 'Sent', name: 'Sent', role: FolderRole.sent),
      Folder(path: 'Drafts', name: 'Drafts', role: FolderRole.drafts),
      Folder(path: 'Archive', name: 'Archive', role: FolderRole.archive),
      Folder(path: 'Trash', name: 'Trash', role: FolderRole.trash),
    ]) {
      folders[f.path] = FakeFolder(f);
    }
  }

  /// Folders by path.
  final Map<String, FakeFolder> folders = {};

  /// Sent messages.
  final List<OutgoingMessage> sent = [];

  /// Messages added with APPEND: (folder, flags).
  final List<(String, List<String>)> appended = [];

  /// How many UIDs were requested with [fetchSummaries].
  int fetchedSummaries = 0;

  /// If not null, every call fails with this error.
  Object? failWith;

  /// Set by [close].
  bool closed = false;

  /// Adds [count] messages to [path] with UIDs 1..count.
  void seed(String path, int count) {
    for (var uid = 1; uid <= count; uid++) {
      folders[path]!.messages[uid] = summary(uid);
      folders[path]!.bodies[uid] = 'Testo del messaggio $uid';
    }
  }

  void _check() {
    final e = failWith;
    if (e != null) throw e;
  }

  @override
  Future<List<Folder>> listFolders() async {
    _check();
    return [for (final f in folders.values) f.folder];
  }

  @override
  Future<FolderStatus> openFolder(String path) async {
    _check();
    final f = folders[path]!;
    final uids = f.messages.keys;
    return FolderStatus(
      uidValidity: f.uidValidity,
      uidNext: uids.isEmpty ? 1 : uids.reduce((a, b) => a > b ? a : b) + 1,
      exists: uids.length,
    );
  }

  @override
  Future<List<int>> listUids(String path) async {
    _check();
    return folders[path]!.messages.keys.toList()..sort();
  }

  /// How many arrival dates were requested.
  int fetchedDates = 0;

  @override
  Future<Map<int, DateTime>> fetchArrivalDates(
    String path,
    List<int> uids,
  ) async {
    _check();
    fetchedDates += uids.length;
    final f = folders[path]!;
    return {
      for (final u in uids)
        if (f.messages[u]?.date != null) u: f.messages[u]!.date!,
    };
  }

  @override
  Future<List<MessageSummary>> fetchSummaries(
    String path,
    List<int> uids,
  ) async {
    _check();
    fetchedSummaries += uids.length;
    final f = folders[path]!;
    return [
      for (final u in uids)
        if (f.messages[u] != null) f.messages[u]!,
    ];
  }

  @override
  Future<Map<int, MessageFlagsState>> fetchFlags(
    String path,
    List<int> uids,
  ) async {
    _check();
    final f = folders[path]!;
    return {
      for (final u in uids)
        if (f.messages[u] != null)
          u: (
            seen: f.messages[u]!.seen,
            flagged: f.messages[u]!.flagged,
            answered: f.messages[u]!.answered,
          ),
    };
  }

  @override
  Future<List<int>> search(String path, String query) async {
    _check();
    final q = query.toLowerCase();
    return [
      for (final m in folders[path]!.messages.values)
        if (m.subject.toLowerCase().contains(q)) m.uid,
    ]..sort();
  }

  @override
  Future<MessageContent> fetchMessage(String path, int uid) async {
    _check();
    final f = folders[path]!;
    return MessageContent(
      summary: f.messages[uid]!,
      cc: const [],
      replyTo: const [],
      messageId: '<m$uid@esempio.org>',
      references: const [],
      plainText: f.bodies[uid],
      html: f.html[uid],
      attachments: f.attachments[uid] ?? const [],
      inlineImages: const {},
    );
  }

  @override
  Future<Uint8List> fetchAttachment(
    String path,
    int uid,
    String fetchId,
  ) async => Uint8List.fromList([1, 2, 3]);

  void _update(
    String path,
    List<int> uids,
    MessageSummary Function(MessageSummary) change,
  ) {
    final f = folders[path]!;
    for (final u in uids) {
      final m = f.messages[u];
      if (m != null) f.messages[u] = change(m);
    }
  }

  @override
  Future<void> setSeen(
    String path,
    List<int> uids, {
    required bool seen,
  }) async {
    _check();
    _update(path, uids, (m) => m.copyWith(seen: seen));
  }

  @override
  Future<void> setFlagged(
    String path,
    List<int> uids, {
    required bool flagged,
  }) async {
    _check();
    _update(path, uids, (m) => m.copyWith(flagged: flagged));
  }

  @override
  Future<void> setAnswered(String path, List<int> uids) async {
    _check();
    _update(path, uids, (m) => m.copyWith(answered: true));
  }

  @override
  Future<void> move(String path, List<int> uids, String targetPath) async {
    _check();
    final from = folders[path]!;
    final to = folders[targetPath]!;
    var next = to.messages.keys.fold(0, (a, b) => a > b ? a : b) + 1;
    for (final u in uids) {
      final m = from.messages.remove(u);
      if (m == null) continue;
      // In the target folder the message gets a new UID.
      to.messages[next] = MessageSummary(
        uid: next,
        from: m.from,
        to: m.to,
        subject: m.subject,
        date: m.date,
        preview: m.preview,
        seen: m.seen,
        flagged: m.flagged,
        answered: m.answered,
        hasAttachments: m.hasAttachments,
      );
      to.bodies[next] = from.bodies.remove(u) ?? '';
      next++;
    }
  }

  @override
  Future<void> deletePermanently(String path, List<int> uids) async {
    _check();
    uids.forEach(folders[path]!.messages.remove);
  }

  @override
  Future<void> append(
    String path,
    String rawMessage, {
    List<String> flags = const [],
  }) async {
    _check();
    appended.add((path, flags));
  }

  @override
  Future<String> send(OutgoingMessage message) async {
    _check();
    sent.add(message);
    return render(message);
  }

  @override
  String render(OutgoingMessage message) =>
      'Subject: ${message.subject}\r\n\r\n${message.body}';

  @override
  Future<void> close() async => closed = true;
}

/// Always creates the same [FakeMailService].
class FakeMailServiceFactory implements MailServiceFactory {
  /// Creates the factory.
  FakeMailServiceFactory(this.service);

  /// The fake server.
  final FakeMailService service;

  /// Result of [check].
  ConnectionCheckResult checkResult = const ConnectionCheckResult(
    folderCount: 5,
  );

  @override
  Future<MailService> connect(Account account, String password) async =>
      service;

  @override
  Future<ConnectionCheckResult> check(Account account, String password) async =>
      checkResult;
}

/// Fake files: no plugins.
class FakeFileActions implements FileActions {
  /// Opened links.
  final List<Uri> opened = [];

  /// Names of the attachments opened.
  final List<String> openedFiles = [];

  /// What the next [pickAttachments] returns.
  List<OutgoingAttachment> toPick = const [];

  @override
  Future<void> openAttachment(String fileName, Uint8List bytes) async =>
      openedFiles.add(fileName);

  @override
  Future<void> openLink(Uri uri) async => opened.add(uri);

  @override
  Future<List<OutgoingAttachment>> pickAttachments() async => toPick;
}

/// In-memory accounts: in widget tests real file I/O never completes (time is
/// fake), so we replace the repository.
class MemoryAccountRepository implements AccountRepository {
  /// Creates the repository with [initial] already saved.
  MemoryAccountRepository(this.secrets, [List<Account> initial = const []])
    : _accounts = [...initial];

  final List<Account> _accounts;

  @override
  final SecretStore secrets;

  @override
  File get file => throw UnimplementedError();

  @override
  Future<List<Account>> load() async => List.of(_accounts);

  @override
  Future<void> save(Account account, String password) async {
    await secrets.write('pwd.${account.id}', password);
    _accounts
      ..removeWhere((a) => a.id == account.id)
      ..add(account);
  }

  @override
  Future<String?> password(String accountId) => secrets.read('pwd.$accountId');

  @override
  Future<void> updatePassword(String accountId, String secret) =>
      secrets.write('pwd.$accountId', secret);

  @override
  Future<void> remove(String accountId) async {
    await secrets.delete('pwd.$accountId');
    _accounts.removeWhere((a) => a.id == accountId);
  }
}
