import 'dart:typed_data';

import 'models.dart';

/// Everything the app asks of a mail server.
///
/// The UI and the sync talk only to this interface: they don't know whether
/// IMAP or, one day, JMAP sits underneath. Tests replace it with a fake
/// in-memory server.
abstract interface class MailService {
  /// Lists the selectable folders.
  Future<List<Folder>> listFolders();

  /// Opens (SELECT) a folder and returns its status.
  Future<FolderStatus> openFolder(String path);

  /// The UIDs of all messages in the folder, ascending.
  Future<List<int>> listUids(String path);

  /// The date the server received each message (`INTERNALDATE`). It does not
  /// change when the message is moved: it lets us sort by date on any server,
  /// even without the SORT extension (e.g. Gmail).
  Future<Map<int, DateTime>> fetchArrivalDates(String path, List<int> uids);

  /// The summaries of the messages with these [uids].
  Future<List<MessageSummary>> fetchSummaries(String path, List<int> uids);

  /// Only the flags (read, starred, answered) of the messages with these
  /// [uids]: cheap, and keeps the cache up to date.
  Future<Map<int, MessageFlagsState>> fetchFlags(String path, List<int> uids);

  /// Searches on the server (IMAP SEARCH) in sender, subject and text.
  Future<List<int>> search(String path, String query);

  /// Downloads the whole message.
  Future<MessageContent> fetchMessage(String path, int uid);

  /// Downloads an attachment.
  Future<Uint8List> fetchAttachment(String path, int uid, String fetchId);

  /// Marks as read or unread.
  Future<void> setSeen(String path, List<int> uids, {required bool seen});

  /// Adds or removes the star.
  Future<void> setFlagged(String path, List<int> uids, {required bool flagged});

  /// Adds or removes Gmail labels (decoded names, as in
  /// [MessageSummary.labels]). Only for servers with labels (Gmail).
  Future<void> storeLabels(
    String path,
    List<int> uids,
    List<String> labels, {
    required bool add,
  });

  /// Marks as answered.
  Future<void> setAnswered(String path, List<int> uids);

  /// Moves to another folder.
  Future<void> move(String path, List<int> uids, String targetPath);

  /// Deletes for good (\Deleted flag + EXPUNGE). Only used in the Trash.
  Future<void> deletePermanently(String path, List<int> uids);

  /// Adds a ready-made message (RFC 822) to a folder, e.g. a copy in Sent or a
  /// draft.
  Future<void> append(String path, String rawMessage, {List<String> flags});

  /// Sends via SMTP and returns the message as RFC 822 text, to save in Sent.
  Future<String> send(OutgoingMessage message);

  /// Builds the RFC 822 text without sending it (for drafts).
  String render(OutgoingMessage message);

  /// Closes the connections.
  Future<void> close();
}

/// The flags of a message, without the rest. [labels] is null where the
/// server has no Gmail labels.
typedef MessageFlagsState = ({
  bool seen,
  bool flagged,
  bool answered,
  List<String>? labels,
});

/// Result of the connection test on the "Add account" screen.
class ConnectionCheckResult {
  /// Creates the result.
  const ConnectionCheckResult({
    this.imapError,
    this.smtpError,
    this.folderCount = 0,
  });

  /// Readable IMAP error, `null` if everything is fine.
  final String? imapError;

  /// Readable SMTP error, `null` if everything is fine.
  final String? smtpError;

  /// How many folders IMAP found.
  final int folderCount;

  /// Both servers respond and accept the credentials.
  bool get ok => imapError == null && smtpError == null;
}

/// Creates the [MailService]s and tests connections. Replaced in tests.
abstract interface class MailServiceFactory {
  /// Connects an account that is already configured.
  Future<MailService> connect(Account account, String password);

  /// Tests IMAP and SMTP before saving an account.
  Future<ConnectionCheckResult> check(Account account, String password);
}
