import 'package:flutter_test/flutter_test.dart';
import 'package:kaamos_mail/src/core/models.dart';
import 'package:kaamos_mail/src/core/text_utils.dart';

import 'support/fakes.dart';

void main() {
  group('parseAddressList', () {
    test('splits names and addresses, keeps the invalid ones aside', () {
      final r = parseAddressList(
        'Marta Bianchi <marta@esempio.org>, luca@esempio.org; non-valido',
      );
      expect(r.valid.map((a) => a.email), [
        'marta@esempio.org',
        'luca@esempio.org',
      ]);
      expect(r.valid.first.name, 'Marta Bianchi');
      expect(r.invalid, ['non-valido']);
    });

    test('empty string = nothing', () {
      final r = parseAddressList('  , ');
      expect(r.valid, isEmpty);
      expect(r.invalid, isEmpty);
    });
  });

  test('isValidEmail', () {
    expect(isValidEmail('a@b.it'), isTrue);
    expect(isValidEmail('a@b'), isFalse);
    expect(isValidEmail('a b@c.it'), isFalse);
  });

  test('Re: and Fwd: are not doubled', () {
    expect(replySubject('Ciao'), 'Re: Ciao');
    expect(replySubject('RE: Ciao'), 'RE: Ciao');
    expect(forwardSubject('Ciao'), 'Fwd: Ciao');
    expect(forwardSubject('I: Ciao'), 'I: Ciao');
  });

  test('replyBody quotes every line with >', () {
    final content = MessageContent(
      summary: summary(1),
      cc: const [],
      replyTo: const [],
      messageId: '<a@b>',
      references: const [],
      plainText: 'riga uno\n\nriga tre',
      html: null,
      attachments: const [],
      inlineImages: const {},
    );
    final body = replyBody(content);
    expect(body, contains('Marta ha scritto:'));
    expect(body, contains('> riga uno\n>\n> riga tre'));
  });

  test('htmlToText strips tags and styles', () {
    final text = htmlToText(
      '<style>p{color:red}</style><p>Ciao <b>Alessio</b></p>',
    );
    expect(text, contains('Ciao Alessio'));
    expect(text, isNot(contains('color')));
  });

  test('makePreview shortens and collapses whitespace', () {
    final p = makePreview('uno\n\n  due ${'x' * 300}', maxLength: 20);
    expect(p.length, lessThanOrEqualTo(21));
    expect(p, startsWith('uno due'));
  });

  test('formatListDate: today, yesterday, date', () {
    final now = DateTime(2026, 11, 26, 18);
    expect(formatListDate(DateTime(2026, 11, 26, 9, 5), now: now), '09:05');
    expect(formatListDate(DateTime(2026, 11, 25, 9), now: now), 'Ieri');
    expect(formatListDate(DateTime(2026, 3, 2), now: now), '2 mar');
    expect(formatListDate(DateTime(2025, 3, 2), now: now), '2 mar 2025');
  });

  test('formatSize', () {
    expect(formatSize(500), '500 B');
    expect(formatSize(2048), '2 KB');
    expect(formatSize(1258291), '1,2 MB');
  });

  test('initials', () {
    expect(initials('Marta Bianchi'), 'MB');
    expect(initials('marta@esempio.org'), 'MA');
  });

  test('folderLabel in Italian', () {
    expect(
      folderLabel(
        const Folder(path: 'INBOX', name: 'INBOX', role: FolderRole.inbox),
      ),
      'Posta in arrivo',
    );
    expect(
      folderLabel(
        const Folder(path: 'Lavoro/Foto', name: 'Foto', role: FolderRole.other),
      ),
      'Foto',
    );
  });

  test('imapQuote escapes quotes and backslashes', () {
    expect(imapQuote(r'a"b\c'), r'"a\"b\\c"');
  });

  test('parseMessageIds', () {
    expect(parseMessageIds('<a@b> <c@d>'), ['<a@b>', '<c@d>']);
    expect(parseMessageIds(null), isEmpty);
  });
}
