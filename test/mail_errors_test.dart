import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaamos_mail/src/core/mail_errors.dart';
import 'package:kaamos_mail/src/core/oauth.dart';
import 'package:kaamos_mail/src/data/imap_mail_service.dart';

void main() {
  MailFailureKind? kindOf(Object e) => mailFailureFrom(e)?.kind;

  test('network, TLS and timeouts become failures with their own kind', () {
    expect(
      kindOf(const SocketException('Failed host lookup')),
      MailFailureKind.network,
    );
    expect(
      kindOf(const HandshakeException('bad cert')),
      MailFailureKind.secureConnection,
    );
    expect(kindOf(TimeoutException('slow')), MailFailureKind.timeout);
  });

  test('an OAuth error keeps its own message', () {
    final failure = mailFailureFrom(const OAuthException('Accesso annullato.'));
    expect(failure?.kind, MailFailureKind.auth);
    expect(failure?.message, 'Accesso annullato.');
  });

  test('bugs are not server failures', () {
    // The Gmail search bug: sorting a const list.
    expect(mailFailureFrom(UnsupportedError('unmodifiable list')), isNull);
    expect(mailFailureFrom(StateError('oops')), isNull);
    expect(mailFailureFrom(const FormatException('bad')), isNull);
  });

  test('an internal error says it is not the server', () {
    final text = describeInternalError(StateError('oops'), StackTrace.empty);
    expect(text, startsWith("Errore interno dell'app (non del server)"));
  });
}
