import '../core/models.dart';
import '../core/text_utils.dart';

/// Come si è arrivati alla schermata di scrittura.
enum ComposeKind {
  /// Messaggio nuovo.
  fresh,

  /// Rispondi.
  reply,

  /// Rispondi a tutti.
  replyAll,

  /// Inoltra.
  forward,
}

/// Il punto di partenza di un messaggio da scrivere.
///
/// È logica pura (niente widget): così le regole di "Rispondi a tutti"
/// (chi va in A, chi in Cc, togliere se stessi) si provano con un test.
class ComposeDraft {
  /// Crea una bozza.
  const ComposeDraft({
    this.kind = ComposeKind.fresh,
    this.to = const [],
    this.cc = const [],
    this.subject = '',
    this.body = '',
    this.inReplyTo,
    this.references = const [],
    this.answeredUid,
    this.answeredPath,
  });

  /// Bozza di risposta a [original] per l'account [me]. [path] è la
  /// cartella di [original].
  ///
  /// Si risponde a `Reply-To` se c'è, altrimenti al mittente. Con [all] gli
  /// altri destinatari vanno in Cc, senza doppioni e senza noi stessi.
  factory ComposeDraft.reply(
    MessageContent original, {
    required Account me,
    bool all = false,
    String? path,
  }) {
    final s = original.summary;
    final mine = me.email.toLowerCase();
    final to = original.replyTo.isNotEmpty ? original.replyTo : [?s.from];
    final seen = <String>{mine, ...to.map((a) => a.email.toLowerCase())};
    final cc = <Address>[];
    if (all) {
      for (final a in [...s.to, ...original.cc]) {
        if (seen.add(a.email.toLowerCase())) cc.add(a);
      }
    }
    // Se il messaggio l'abbiamo scritto noi (es. dagli Inviati) non ha senso
    // rispondere a noi stessi: teniamo la lista solo se resta vuota.
    final others = to.where((a) => a.email.toLowerCase() != mine).toList();
    final refs = [
      ...original.references,
      if (original.messageId != null) original.messageId!,
    ];
    return ComposeDraft(
      kind: all ? ComposeKind.replyAll : ComposeKind.reply,
      to: others.isEmpty ? to : others,
      cc: cc,
      subject: replySubject(s.subject),
      body: replyBody(original),
      inReplyTo: original.messageId,
      references: refs,
      answeredUid: s.uid,
      answeredPath: path,
    );
  }

  /// Bozza di inoltro di [original].
  factory ComposeDraft.forward(MessageContent original) => ComposeDraft(
    kind: ComposeKind.forward,
    subject: forwardSubject(original.summary.subject),
    body: forwardBody(original),
  );

  /// Tipo di bozza.
  final ComposeKind kind;

  /// Destinatari.
  final List<Address> to;

  /// Copia.
  final List<Address> cc;

  /// Oggetto.
  final String subject;

  /// Corpo in testo semplice.
  final String body;

  /// `Message-ID` del messaggio a cui si risponde.
  final String? inReplyTo;

  /// Catena dei `Message-ID` della conversazione.
  final List<String> references;

  /// UID del messaggio da segnare come "risposto" dopo l'invio.
  final int? answeredUid;

  /// Cartella di [answeredUid]. `null`: quella aperta. Serve quando si
  /// risponde dall'Inbox unificata mentre l'account guarda un'altra
  /// cartella.
  final String? answeredPath;
}
