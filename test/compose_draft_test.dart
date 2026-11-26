import 'package:flutter_test/flutter_test.dart';
import 'package:kaamos_mail/src/core/models.dart';
import 'package:kaamos_mail/src/state/compose_draft.dart';

import 'support/fakes.dart';

MessageContent _content({
  List<Address> to = const [Address('alessio@esempio.org')],
  List<Address> cc = const [],
  List<Address> replyTo = const [],
}) => MessageContent(
  summary: MessageSummary(
    uid: 9,
    from: const Address('marta@esempio.org', 'Marta'),
    to: to,
    subject: 'Gita',
    date: DateTime.utc(2026, 11, 20),
    preview: '',
    seen: true,
    flagged: false,
    answered: false,
    hasAttachments: false,
  ),
  cc: cc,
  replyTo: replyTo,
  messageId: '<m9@x>',
  references: const ['<m1@x>'],
  plainText: 'Ciao!',
  html: null,
  attachments: const [],
  inlineImages: const {},
);

void main() {
  test('Rispondi va al mittente con oggetto e catena', () {
    final d = ComposeDraft.reply(_content(), me: testAccount);
    expect(d.to.single.email, 'marta@esempio.org');
    expect(d.cc, isEmpty);
    expect(d.subject, 'Re: Gita');
    expect(d.inReplyTo, '<m9@x>');
    expect(d.references, ['<m1@x>', '<m9@x>']);
    expect(d.answeredUid, 9);
  });

  test('Reply-To vince sul mittente', () {
    final d = ComposeDraft.reply(
      _content(replyTo: const [Address('lista@esempio.org')]),
      me: testAccount,
    );
    expect(d.to.single.email, 'lista@esempio.org');
  });

  test('Rispondi a tutti: altri in Cc, senza noi e senza doppioni', () {
    final d = ComposeDraft.reply(
      _content(
        to: const [Address('ALESSIO@esempio.org'), Address('luca@esempio.org')],
        cc: const [
          Address('luca@esempio.org'),
          Address('marta@esempio.org'),
          Address('sara@esempio.org'),
        ],
      ),
      me: testAccount,
      all: true,
    );
    expect(d.to.map((a) => a.email), ['marta@esempio.org']);
    expect(d.cc.map((a) => a.email), ['luca@esempio.org', 'sara@esempio.org']);
  });

  test('la risposta ricorda la cartella del messaggio', () {
    final d = ComposeDraft.reply(_content(), me: testAccount, path: 'INBOX');
    expect(d.answeredPath, 'INBOX');
    expect(
      ComposeDraft.reply(_content(), me: testAccount).answeredPath,
      isNull,
    );
  });

  test('Inoltra: oggetto Fwd e nessun destinatario', () {
    final d = ComposeDraft.forward(_content());
    expect(d.to, isEmpty);
    expect(d.subject, 'Fwd: Gita');
    expect(d.body, contains('Messaggio inoltrato'));
    expect(d.answeredUid, isNull);
  });
}
