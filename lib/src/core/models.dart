import 'package:flutter/foundation.dart';

/// Come si protegge la connessione verso un server.
enum ConnectionSecurity {
  /// TLS dall'inizio (IMAP 993, SMTP 465).
  tls,

  /// Connessione in chiaro che passa a TLS con STARTTLS (IMAP 143, SMTP 587).
  startTls,
}

/// Indirizzo, porta e sicurezza di un server IMAP o SMTP.
@immutable
class ServerConfig {
  /// Crea la configurazione di un server.
  const ServerConfig({
    required this.host,
    required this.port,
    required this.security,
  });

  /// Legge la configurazione salvata con [toJson].
  factory ServerConfig.fromJson(Map<String, Object?> json) => ServerConfig(
    host: json['host']! as String,
    port: json['port']! as int,
    security: ConnectionSecurity.values.byName(json['security']! as String),
  );

  /// Nome del server, es. `imap.esempio.it`.
  final String host;

  /// Porta TCP.
  final int port;

  /// TLS diretto o STARTTLS.
  final ConnectionSecurity security;

  /// Per salvare la configurazione su disco.
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

/// Un account email configurato a mano.
///
/// Non contiene la password: quella vive solo nel portachiavi di sistema
/// (vedi `SecretStore`). Così il file con gli account si può leggere senza
/// esporre niente di segreto.
@immutable
class Account {
  /// Crea un account.
  const Account({
    required this.id,
    required this.displayName,
    required this.email,
    required this.username,
    required this.imap,
    required this.smtp,
  });

  /// Legge un account salvato con [toJson].
  factory Account.fromJson(Map<String, Object?> json) => Account(
    id: json['id']! as String,
    displayName: json['displayName']! as String,
    email: json['email']! as String,
    username: json['username']! as String,
    imap: ServerConfig.fromJson(json['imap']! as Map<String, Object?>),
    smtp: ServerConfig.fromJson(json['smtp']! as Map<String, Object?>),
  );

  /// Identificativo locale, stabile anche se l'utente cambia indirizzo.
  final String id;

  /// Il nome che vedono i destinatari ("Alessio").
  final String displayName;

  /// L'indirizzo email.
  final String email;

  /// Il nome utente per IMAP e SMTP (di solito uguale a [email]).
  final String username;

  /// Server della posta in arrivo.
  final ServerConfig imap;

  /// Server della posta in uscita.
  final ServerConfig smtp;

  /// Per salvare l'account su disco.
  Map<String, Object?> toJson() => {
    'id': id,
    'displayName': displayName,
    'email': email,
    'username': username,
    'imap': imap.toJson(),
    'smtp': smtp.toJson(),
  };
}

/// Il ruolo speciale di una cartella (RFC 6154, SPECIAL-USE).
enum FolderRole {
  /// Posta in arrivo.
  inbox,

  /// Messaggi inviati.
  sent,

  /// Bozze.
  drafts,

  /// Archivio.
  archive,

  /// Cestino.
  trash,

  /// Spam.
  junk,

  /// Una cartella creata dall'utente.
  other,
}

/// Una cartella IMAP.
@immutable
class Folder {
  /// Crea una cartella.
  const Folder({required this.path, required this.name, required this.role});

  /// Percorso completo sul server, es. `INBOX/Fotografia`.
  final String path;

  /// Nome da mostrare.
  final String name;

  /// Ruolo speciale, se c'è.
  final FolderRole role;

  @override
  bool operator ==(Object other) =>
      other is Folder && other.path == path && other.role == role;

  @override
  int get hashCode => Object.hash(path, role);
}

/// Stato di una cartella appena aperta (risposta a SELECT).
@immutable
class FolderStatus {
  /// Crea lo stato di una cartella.
  const FolderStatus({
    required this.uidValidity,
    required this.uidNext,
    required this.exists,
  });

  /// Se cambia, gli UID che conosciamo non valgono più: la cache va svuotata.
  final int uidValidity;

  /// L'UID che avrà il prossimo messaggio: tutto ciò che è sotto esiste già.
  final int uidNext;

  /// Quanti messaggi ci sono nella cartella.
  final int exists;
}

/// Un indirizzo con il nome facoltativo.
@immutable
class Address {
  /// Crea un indirizzo.
  const Address(this.email, [this.name]);

  /// L'indirizzo, es. `marta@esempio.org`.
  final String email;

  /// Il nome, es. `Marta Bianchi`.
  final String? name;

  /// Il nome se c'è, altrimenti l'indirizzo.
  String get label => (name == null || name!.trim().isEmpty) ? email : name!;

  /// Forma `Nome <indirizzo>`.
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

/// Una riga della lista messaggi: quello che serve senza scaricare il corpo.
@immutable
class MessageSummary {
  /// Crea il riassunto di un messaggio.
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

  /// UID IMAP, unico nella cartella finché `UIDVALIDITY` non cambia.
  final int uid;

  /// Mittente.
  final Address? from;

  /// Destinatari principali.
  final List<Address> to;

  /// Oggetto.
  final String subject;

  /// Data di invio.
  final DateTime? date;

  /// Inizio del testo, già ripulito, per l'anteprima nella lista.
  final String preview;

  /// Letto.
  final bool seen;

  /// Contrassegnato con la stella.
  final bool flagged;

  /// Già risposto.
  final bool answered;

  /// Ha almeno un allegato.
  final bool hasAttachments;

  /// Copia con alcuni campi cambiati.
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

/// Un allegato di un messaggio scaricato.
@immutable
class AttachmentInfo {
  /// Crea la descrizione di un allegato.
  const AttachmentInfo({
    required this.fetchId,
    required this.fileName,
    required this.size,
    required this.mimeType,
  });

  /// Identificativo della parte MIME, es. `2` o `1.2`.
  final String fetchId;

  /// Nome del file.
  final String fileName;

  /// Dimensione in byte, se il server la conosce.
  final int? size;

  /// Tipo, es. `application/pdf`.
  final String mimeType;
}

/// Il contenuto completo di un messaggio aperto.
@immutable
class MessageContent {
  /// Crea il contenuto di un messaggio.
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

  /// I campi della lista.
  final MessageSummary summary;

  /// Destinatari in copia.
  final List<Address> cc;

  /// Dove rispondere, se diverso dal mittente.
  final List<Address> replyTo;

  /// Header `Message-ID`, per collegare le risposte.
  final String? messageId;

  /// Header `References`, per collegare le risposte.
  final List<String> references;

  /// La parte `text/plain`, se c'è.
  final String? plainText;

  /// La parte `text/html` così come arriva: va sempre ripulita prima di
  /// mostrarla (vedi `HtmlSanitizer`).
  final String? html;

  /// Gli allegati.
  final List<AttachmentInfo> attachments;

  /// Immagini dentro il messaggio, per `Content-ID` (senza `<` `>`).
  final Map<String, InlineImage> inlineImages;
}

/// Un'immagine allegata e richiamata nell'HTML con `cid:`.
@immutable
class InlineImage {
  /// Crea un'immagine in linea.
  const InlineImage({required this.mimeType, required this.bytes});

  /// Tipo, es. `image/png`.
  final String mimeType;

  /// I byte dell'immagine.
  final Uint8List bytes;
}

/// Un file da allegare a un messaggio in uscita.
@immutable
class OutgoingAttachment {
  /// Crea un allegato in uscita.
  const OutgoingAttachment({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  /// Nome del file.
  final String fileName;

  /// Tipo MIME.
  final String mimeType;

  /// Contenuto.
  final Uint8List bytes;
}

/// Un messaggio da inviare. Solo testo semplice nell'MVP.
@immutable
class OutgoingMessage {
  /// Crea un messaggio in uscita.
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

  /// Mittente.
  final Address from;

  /// Destinatari.
  final List<Address> to;

  /// Copia.
  final List<Address> cc;

  /// Copia nascosta.
  final List<Address> bcc;

  /// Oggetto.
  final String subject;

  /// Testo semplice.
  final String body;

  /// Allegati.
  final List<OutgoingAttachment> attachments;

  /// `Message-ID` del messaggio a cui rispondo.
  final String? inReplyTo;

  /// Catena `References`.
  final List<String> references;

  /// Tutti i destinatari, per la busta SMTP.
  List<Address> get allRecipients => [...to, ...cc, ...bcc];
}
