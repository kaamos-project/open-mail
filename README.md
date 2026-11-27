# Kaamos Mail

A free (GPLv3), client-only, privacy-first email client for Windows, macOS, Android and iOS, part of **Kaamos Project**. Linux arrives in phase 2.

It talks directly to your IMAP/SMTP server: no Kaamos server in between, no telemetry. Passwords live only in the operating system keychain.

## Features

**MVP (phase 1)**

- IMAP/SMTP accounts, with a server check before saving.
- Folders, message list with "Load more", server-side search.
- Plain-text and HTML mail (a locked-down WebView), remote images blocked until you press "Load images".
- Attachments: open received ones, attach files to new ones.
- Compose, Reply, Reply all, Forward (plain text).
- Drafts saved on the server, copy in Sent (except Gmail, which does it itself).
- Star, read/unread, Archive, Trash.

**Phase 2 (in progress)**

- Multiple accounts and a unified Inbox ("Tutte le caselle").
- Sign in with Google and Microsoft (OAuth2 + XOAUTH2) on desktop.

## Quick start

Requires Flutter 3.50.1.

```sh
flutter pub get
flutter run -d windows   # or macos, ios, android
```

## Documentation

Everything about how the app works lives in the wiki in [`docs/`](docs/README.md):

- [Getting started](docs/getting-started.md)
- [Architecture](docs/architecture.md)
- [Sync and cache](docs/sync-and-cache.md)
- [Reading HTML mail](docs/html-mail.md)
- [Google and Microsoft sign-in](docs/oauth.md)
- [Decisions](docs/decisions.md)

## License

GPL-3.0. See [LICENSE](LICENSE).
