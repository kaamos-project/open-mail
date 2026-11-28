[Home](README.md) › Error handling

# Error handling

The app separates two kinds of errors, because the user needs to know whose fault it is.

| Kind | Examples | Type | What the user sees |
|---|---|---|---|
| **Expected failure**: the server or the network said no | Wrong password, no network, TLS handshake failed, server timeout, IMAP `NO`/`BAD`, SMTP `5xx` | `MailFailure` (`lib/src/core/mail_errors.dart`) | A sentence that says what to check |
| **Bug**: our code did something wrong | Sorting an unmodifiable list, a null where there should not be one | Anything else (`UnsupportedError`, `StateError`, …) | "Errore interno dell'app (non del server): …", and the stack trace in the local log |

## Where the translation happens

`MailService` is the boundary. `ImapMailService` runs every call through `_translated`, which uses `mailFailureFrom` to turn the exceptions it knows into a `MailFailure` with a `MailFailureKind`:

| Source exception | Kind |
|---|---|
| `OAuthException` | `auth` (keeps its own message) |
| `ImapException`, `SmtpException`, `MailException` | `auth` if the text says so (`AUTHENTICATIONFAILED`, `535`…), otherwise `server` with the server's text |
| `TlsException` / `HandshakeException` | `secureConnection` |
| `TimeoutException` | `timeout` |
| `SocketException` | `network` |

Anything else is **rethrown unchanged**, with its stack trace. This keeps enough_mail's types inside the `data` layer: `state` and `ui` only know `MailFailure`.

## Catching

Every place that calls the service catches the two kinds separately:

```dart
try {
  await service.search(path, query);
} on MailFailure catch (e) {
  error = e.message;                      // expected: show it
} catch (e, st) {
  error = describeInternalError(e, st);   // a bug: log it, say so
}
```

The second clause is not a lazy catch-all: it is the **boundary** of a user action. Without it a bug would leave the spinner on and the user without any message. It logs with `dart:developer` (visible in the debugger and in `flutter logs`); nothing leaves the device.

Inside the data layer, retry is also specific: `_withRetry` reconnects only on `ImapException` and `SocketException`, never on bugs.

## Example: the Gmail search bug

A search with no results returned `const []` from `fetchSummaries`, and the controller sorted it in place: `Unsupported operation: Cannot modify an unmodifiable list`. Before this split it was shown as "Errore del server", which pointed to the wrong place. The fix copies the list before sorting; the fake service now returns unmodifiable lists like the real one, and `folders_and_list_test` covers a search with no matches.

## Tests

- `test/mail_errors_test.dart`: what becomes a `MailFailure` and what stays a bug.
- `test/mailbox_controller_test.dart`: a bug is shown as an internal error and the spinner stops.
- Fakes fail with `MailFailure` (`FakeMailService.failWith`), like the real service.

## See also

- [Architecture](architecture.md): the four layers and the `MailService` interface.
- [Accounts and secrets](accounts-and-security.md): the connection check uses the same messages.
- [Testing](testing.md): the fakes.
