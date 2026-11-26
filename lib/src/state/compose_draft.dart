import '../core/models.dart';
import '../core/text_utils.dart';

/// How the compose screen was reached.
enum ComposeKind {
  /// New message.
  fresh,

  /// Reply.
  reply,

  /// Reply all.
  replyAll,

  /// Forward.
  forward,
}

/// The starting point of a message to write.
///
/// It is pure logic (no widgets): so the "Reply all" rules (who goes in To, who
/// in Cc, removing yourself) can be checked with a test.
class ComposeDraft {
  /// Creates a draft.
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

  /// Reply draft to [original] for the account [me]. [path] is the folder of
  /// [original].
  ///
  /// Replies go to `Reply-To` if present, otherwise to the sender. With [all]
  /// the other recipients go in Cc, without duplicates and without ourselves.
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
    // If we wrote the message ourselves (e.g. from Sent) replying to ourselves
    // makes no sense: keep the list only if it would end up empty.
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

  /// Forward draft of [original].
  factory ComposeDraft.forward(MessageContent original) => ComposeDraft(
    kind: ComposeKind.forward,
    subject: forwardSubject(original.summary.subject),
    body: forwardBody(original),
  );

  /// Draft kind.
  final ComposeKind kind;

  /// Recipients.
  final List<Address> to;

  /// Cc.
  final List<Address> cc;

  /// Subject.
  final String subject;

  /// Plain text body.
  final String body;

  /// `Message-ID` of the message being answered.
  final String? inReplyTo;

  /// Chain of the conversation's `Message-ID`s.
  final List<String> references;

  /// UID of the message to mark as "answered" after sending.
  final int? answeredUid;

  /// Folder of [answeredUid]. `null`: the open one. Needed when replying from
  /// the unified Inbox while the account shows another folder.
  final String? answeredPath;
}
