import 'package:flutter/foundation.dart';

/// How the connection to a server is secured.
enum ConnectionSecurity {
  /// TLS from the start (IMAP 993, SMTP 465).
  tls,

  /// Plain connection upgraded to TLS with STARTTLS (IMAP 143, SMTP 587).
  startTls,
}

/// Host, port and security of an IMAP or SMTP server.
@immutable
class ServerConfig {
  /// Creates a server configuration.
  const ServerConfig({
    required this.host,
    required this.port,
    required this.security,
  });

  /// Reads a configuration saved with [toJson].
  factory ServerConfig.fromJson(Map<String, Object?> json) => ServerConfig(
    host: json['host']! as String,
    port: json['port']! as int,
    security: ConnectionSecurity.values.byName(json['security']! as String),
  );

  /// Host name, e.g. `imap.example.com`.
  final String host;

  /// TCP port.
  final int port;

  /// Direct TLS or STARTTLS.
  final ConnectionSecurity security;

  /// For saving the configuration to disk.
  Map<String, Object?> toJson() => {
    'host': host,
    'port': port,
    'security': security.name,
  };

  @override
  bool operator ==(Object other) =>
      other is ServerConfig &&
      other.host == host &&
      other.port == port &&
      other.security == security;

  @override
  int get hashCode => Object.hash(host, port, security);
}

/// A provider that signs in with OAuth2 instead of a password.
enum OAuthProvider {
  /// Gmail and Google Workspace.
  google,

  /// Outlook.com, Hotmail and Microsoft 365.
  microsoft,
}

/// An email account.
///
/// It holds no password or token: those live only in the system keychain
/// (see `SecretStore`). This way the accounts file can be read without
/// exposing anything secret.
@immutable
class Account {
  /// Creates an account.
  const Account({
    required this.id,
    required this.displayName,
    required this.email,
    required this.username,
    required this.imap,
    required this.smtp,
    this.oauth,
  });

  /// Reads an account saved with [toJson].
  factory Account.fromJson(Map<String, Object?> json) => Account(
    id: json['id']! as String,
    displayName: json['displayName']! as String,
    email: json['email']! as String,
    username: json['username']! as String,
    imap: ServerConfig.fromJson(json['imap']! as Map<String, Object?>),
    smtp: ServerConfig.fromJson(json['smtp']! as Map<String, Object?>),
    oauth: switch (json['oauth']) {
      'google' => OAuthProvider.google,
      'microsoft' => OAuthProvider.microsoft,
      _ => null,
    },
  );

  /// Local identifier, stable even if the user changes address.
  final String id;

  /// The name recipients see ("Alessio").
  final String displayName;

  /// The email address.
  final String email;

  /// The IMAP and SMTP user name (usually the same as [email]).
  final String username;

  /// Incoming mail server.
  final ServerConfig imap;

  /// Outgoing mail server.
  final ServerConfig smtp;

  /// The OAuth2 provider, `null` for password accounts. With OAuth2 the
  /// keychain holds the refresh token instead of the password.
  final OAuthProvider? oauth;

  /// For saving the account to disk.
  Map<String, Object?> toJson() => {
    'id': id,
    'displayName': displayName,
    'email': email,
    'username': username,
    'imap': imap.toJson(),
    'smtp': smtp.toJson(),
    if (oauth != null) 'oauth': oauth!.name,
  };
}

/// The special role of a folder (RFC 6154, SPECIAL-USE).
enum FolderRole {
  /// Inbox.
  inbox,

  /// Sent messages.
  sent,

  /// Drafts.
  drafts,

  /// Archive.
  archive,

  /// Trash.
  trash,

  /// Spam.
  junk,

  /// A folder created by the user.
  other,
}

/// An IMAP folder.
@immutable
class Folder {
  /// Creates a folder.
  const Folder({required this.path, required this.name, required this.role});

  /// Full path on the server, e.g. `INBOX/Photography`.
  final String path;

  /// Display name.
  final String name;

  /// Special role, if any.
  final FolderRole role;

  @override
  bool operator ==(Object other) =>
      other is Folder && other.path == path && other.role == role;

  @override
  int get hashCode => Object.hash(path, role);
}

/// State of a folder that was just opened (the SELECT response).
@immutable
class FolderStatus {
  /// Creates a folder status.
  const FolderStatus({
    required this.uidValidity,
    required this.uidNext,
    required this.exists,
  });

  /// If it changes, the UIDs we know are no longer valid: clear the cache.
  final int uidValidity;

  /// The UID the next message will get: everything below it already exists.
  final int uidNext;

  /// How many messages the folder holds.
  final int exists;
}

/// An address with an optional name.
@immutable
class Address {
  /// Creates an address.
  const Address(this.email, [this.name]);

  /// The address, e.g. `marta@example.org`.
  final String email;

  /// The name, e.g. `Marta Bianchi`.
  final String? name;

  /// The name if present, otherwise the address.
  String get label => (name == null || name!.trim().isEmpty) ? email : name!;

  /// `Name <address>` form.
  @override
  String toString() =>
      (name == null || name!.isEmpty) ? email : '$name <$email>';

  @override
  bool operator ==(Object other) =>
      other is Address &&
      other.email.toLowerCase() == email.toLowerCase() &&
      other.name == name;

  @override
  int get hashCode => Object.hash(email.toLowerCase(), name);
}

/// A row of the message list: what is needed without downloading the body.
@immutable
class MessageSummary {
  /// Creates a message summary.
  const MessageSummary({
    required this.uid,
    required this.from,
    required this.to,
    required this.subject,
    required this.date,
    required this.preview,
    required this.seen,
    required this.flagged,
    required this.answered,
    required this.hasAttachments,
  });

  /// IMAP UID, unique in the folder as long as `UIDVALIDITY` does not change.
  final int uid;

  /// Sender.
  final Address? from;

  /// Main recipients.
  final List<Address> to;

  /// Subject.
  final String subject;

  /// Date sent.
  final DateTime? date;

  /// Start of the text, already cleaned up, for the list preview.
  final String preview;

  /// Read.
  final bool seen;

  /// Starred.
  final bool flagged;

  /// Already answered.
  final bool answered;

  /// Has at least one attachment.
  final bool hasAttachments;

  /// Copy with some fields changed.
  MessageSummary copyWith({bool? seen, bool? flagged, bool? answered}) =>
      MessageSummary(
        uid: uid,
        from: from,
        to: to,
        subject: subject,
        date: date,
        preview: preview,
        seen: seen ?? this.seen,
        flagged: flagged ?? this.flagged,
        answered: answered ?? this.answered,
        hasAttachments: hasAttachments,
      );
}

/// An attachment of a downloaded message.
@immutable
class AttachmentInfo {
  /// Creates an attachment description.
  const AttachmentInfo({
    required this.fetchId,
    required this.fileName,
    required this.size,
    required this.mimeType,
  });

  /// MIME part identifier, e.g. `2` or `1.2`.
  final String fetchId;

  /// File name.
  final String fileName;

  /// Size in bytes, if the server knows it.
  final int? size;

  /// Type, e.g. `application/pdf`.
  final String mimeType;
}

/// The full content of an opened message.
@immutable
class MessageContent {
  /// Creates a message content.
  const MessageContent({
    required this.summary,
    required this.cc,
    required this.replyTo,
    required this.messageId,
    required this.references,
    required this.plainText,
    required this.html,
    required this.attachments,
    required this.inlineImages,
  });

  /// The list fields.
  final MessageSummary summary;

  /// Cc recipients.
  final List<Address> cc;

  /// Where to reply, if different from the sender.
  final List<Address> replyTo;

  /// `Message-ID` header, to link replies.
  final String? messageId;

  /// `References` header, to link replies.
  final List<String> references;

  /// The `text/plain` part, if any.
  final String? plainText;

  /// The `text/html` part as it arrives: always clean it before showing it
  /// (see `HtmlSanitizer`).
  final String? html;

  /// The attachments.
  final List<AttachmentInfo> attachments;

  /// Images inside the message, by `Content-ID` (without `<` `>`).
  final Map<String, InlineImage> inlineImages;
}

/// An attached image referenced in the HTML with `cid:`.
@immutable
class InlineImage {
  /// Creates an inline image.
  const InlineImage({required this.mimeType, required this.bytes});

  /// Type, e.g. `image/png`.
  final String mimeType;

  /// The image bytes.
  final Uint8List bytes;
}

/// A file to attach to an outgoing message.
@immutable
class OutgoingAttachment {
  /// Creates an outgoing attachment.
  const OutgoingAttachment({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  /// File name.
  final String fileName;

  /// MIME type.
  final String mimeType;

  /// Content.
  final Uint8List bytes;
}

/// A message to send. Plain text only in the MVP.
@immutable
class OutgoingMessage {
  /// Creates an outgoing message.
  const OutgoingMessage({
    required this.from,
    required this.to,
    this.cc = const [],
    this.bcc = const [],
    required this.subject,
    required this.body,
    this.attachments = const [],
    this.inReplyTo,
    this.references = const [],
  });

  /// Sender.
  final Address from;

  /// Recipients.
  final List<Address> to;

  /// Cc.
  final List<Address> cc;

  /// Bcc.
  final List<Address> bcc;

  /// Subject.
  final String subject;

  /// Plain text.
  final String body;

  /// Attachments.
  final List<OutgoingAttachment> attachments;

  /// `Message-ID` of the message being answered.
  final String? inReplyTo;

  /// `References` chain.
  final List<String> references;

  /// All recipients, for the SMTP envelope.
  List<Address> get allRecipients => [...to, ...cc, ...bcc];
}
