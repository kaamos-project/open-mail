[Home](README.md) › Testing

# Testing

Tests run with `flutter test` on Linux, locally and in CI. They don't need a WebView, a keychain or the network, thanks to the interfaces described in [Architecture](architecture.md#dependency-injection-mailenvironment).

## Fakes (`test/support/fakes.dart`)

| Fake | Replaces |
|---|---|
| `FakeMailService` | An in-memory IMAP/SMTP server with Inbox, Sent, Drafts, Archive and Trash. Records sent and appended messages. |
| `MemorySecretStore` (in `lib/src/data/secret_store.dart`) | The system keychain; `available: false` simulates Linux without Secret Service |
| `MailCache.inMemory()` | The SQLite file |
| Sample builders | A sample account, a sample message with a given UID |

## What is tested

| File | Covers |
|---|---|
| `mail_cache_test.dart` | Read/write, `UIDVALIDITY` reset, sorting by date and not by UID, date index cleanup, old schema recreated |
| `mailbox_controller_test.dart` | First page only, vanished messages, `UIDVALIDITY` change, load more, open marks read, rollback of optimistic actions, delete and archive |
| `mail_session_test.dart` | One controller per account, switching, adding, removal deletes password and cache |
| `unified_inbox_test.dart` | Merging by arrival date, rollback, refreshing Inboxes without changing folder |
| `compose_draft_test.dart` | Reply / reply all / forward rules, `Reply-To`, folder of the original |
| `html_sanitizer_test.dart` | Removed tags and attributes, remote images, `cid:`, CSP and referrer, dangerous CSS, body colours |
| `imap_mail_service_test.dart` | `INTERNALDATE` parsing |
| `oauth_test.dart` | PKCE, authorization URL, Microsoft scopes, token parsing |
| `account_repository_test.dart` | JSON file + keychain, removal |
| `text_utils_test.dart` | Address parsing and validation, `Re:`/`Fwd:`, quoting, HTML to text, previews |
| `app_test.dart` | The whole app with fakes: no keychain, first start, OAuth buttons without client ID, desktop and mobile layouts, multiple accounts |

Why is the cache tested so much? Because it uses hand-written SQL with no compile-time checks: see [Decisions](decisions.md#sqlite-without-an-orm).

## Before a pull request

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

## See also

- [Getting started](getting-started.md#checks-the-same-as-ci)
- [Architecture](architecture.md)
