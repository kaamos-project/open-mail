import 'dart:typed_data';

import 'models.dart';

/// Tutto quello che l'app chiede a un server di posta.
///
/// La UI e la sincronizzazione parlano solo con questa interfaccia: non
/// sanno se sotto c'è IMAP o, un domani, JMAP. Nei test la si sostituisce con
/// un server finto in memoria.
abstract interface class MailService {
  /// Elenca le cartelle selezionabili.
  Future<List<Folder>> listFolders();

  /// Apre (SELECT) una cartella e ne restituisce lo stato.
  Future<FolderStatus> openFolder(String path);

  /// Gli UID di tutti i messaggi della cartella, dal più vecchio al più
  /// recente per data se il server sa ordinare (SORT), altrimenti per UID.
  Future<List<int>> listUids(String path);

  /// I riassunti dei messaggi con questi [uids].
  Future<List<MessageSummary>> fetchSummaries(String path, List<int> uids);

  /// Solo i flag (letto, stella, risposto) dei messaggi con questi [uids]:
  /// costa poco e serve a tenere aggiornata la cache.
  Future<Map<int, MessageFlagsState>> fetchFlags(String path, List<int> uids);

  /// Cerca sul server (IMAP SEARCH) in mittente, oggetto e testo.
  Future<List<int>> search(String path, String query);

  /// Scarica tutto il messaggio.
  Future<MessageContent> fetchMessage(String path, int uid);

  /// Scarica un allegato.
  Future<Uint8List> fetchAttachment(String path, int uid, String fetchId);

  /// Segna come letti o non letti.
  Future<void> setSeen(String path, List<int> uids, {required bool seen});

  /// Mette o toglie la stella.
  Future<void> setFlagged(String path, List<int> uids, {required bool flagged});

  /// Segna come risposto.
  Future<void> setAnswered(String path, List<int> uids);

  /// Sposta in un'altra cartella.
  Future<void> move(String path, List<int> uids, String targetPath);

  /// Cancella davvero (flag \Deleted + EXPUNGE). Si usa solo nel Cestino.
  Future<void> deletePermanently(String path, List<int> uids);

  /// Aggiunge un messaggio già pronto (RFC 822) a una cartella, es. una copia
  /// in Inviati o una bozza.
  Future<void> append(String path, String rawMessage, {List<String> flags});

  /// Invia via SMTP e restituisce il messaggio come testo RFC 822, da
  /// salvare in Inviati.
  Future<String> send(OutgoingMessage message);

  /// Crea il testo RFC 822 senza inviarlo (per le bozze).
  String render(OutgoingMessage message);

  /// Chiude le connessioni.
  Future<void> close();
}

/// I flag di un messaggio, senza il resto.
typedef MessageFlagsState = ({bool seen, bool flagged, bool answered});

/// Esito della prova di connessione nella schermata "Aggiungi account".
class ConnectionCheckResult {
  /// Crea l'esito.
  const ConnectionCheckResult({
    this.imapError,
    this.smtpError,
    this.folderCount = 0,
  });

  /// Errore IMAP leggibile, `null` se va tutto bene.
  final String? imapError;

  /// Errore SMTP leggibile, `null` se va tutto bene.
  final String? smtpError;

  /// Quante cartelle ha trovato IMAP.
  final int folderCount;

  /// Entrambi i server rispondono e accettano le credenziali.
  bool get ok => imapError == null && smtpError == null;
}

/// Crea i [MailService] e prova le connessioni. Nei test si sostituisce.
abstract interface class MailServiceFactory {
  /// Collega un account già configurato.
  Future<MailService> connect(Account account, String password);

  /// Prova IMAP e SMTP prima di salvare un account.
  Future<ConnectionCheckResult> check(Account account, String password);
}
