import 'dart:developer' as developer;

/// What kind of expected failure happened while talking to a mail server.
enum MailFailureKind {
  /// The server refused the username, password or token.
  auth,

  /// The server could not be reached (no network, wrong host or port).
  network,

  /// The TLS handshake failed (wrong security setting, bad certificate).
  secureConnection,

  /// The server did not answer in time.
  timeout,

  /// The server answered, but with an error (a NO or BAD reply, a 5xx code).
  server,
}

/// An expected failure of a [MailService] call: the server or the network
/// said no. Its [message] is a sentence for the user, in Italian.
///
/// The data layer turns protocol and socket exceptions into this type, so
/// the rest of the app catches one type and never depends on enough_mail.
/// Anything else that escapes a service call is a bug in the app: see
/// [describeInternalError].
class MailFailure implements Exception {
  /// Creates a failure.
  const MailFailure(this.kind, this.message, {this.cause});

  /// What went wrong.
  final MailFailureKind kind;

  /// The sentence shown to the user.
  final String message;

  /// The original exception, for logs and debugging.
  final Object? cause;

  @override
  String toString() => 'MailFailure(${kind.name}): $message';
}

/// Logs an unexpected error (a bug, not a server failure) and returns the
/// sentence shown to the user.
///
/// The log stays on the device (`dart:developer`, visible in the debugger
/// and in `flutter logs`): nothing is sent anywhere.
String describeInternalError(Object error, StackTrace stackTrace) {
  developer.log(
    'Unexpected error',
    name: 'kaamos_mail',
    error: error,
    stackTrace: stackTrace,
  );
  return "Errore interno dell'app (non del server): $error";
}
