[Home](README.md) › Decisions

# Decisions

The key choices behind Kaamos Mail, each with the alternatives and the trade-off. Lightweight ADRs: when a decision changes, update its entry and say why.

## Client only, no Kaamos server

**Decision**: the app talks directly to the user's IMAP/SMTP server. A Kaamos mail server, if it ever exists, is a separate project.
**Why**: privacy (nobody in the middle sees your mail or credentials) and nothing to host.
**Trade-off**: no server-side push or search; everything the client can't do with IMAP it doesn't do.

## Native only, no web

**Decision**: Windows, macOS, Android, iOS (Linux in phase 2). No Flutter web build until JMAP.
**Why**: a browser can't open TCP sockets to IMAP; a WebSocket proxy would be a server, which breaks the decision above.

## Cache: SQLite shown first

**Decision**: show the SQLite cache immediately, then refresh from IMAP using `UIDVALIDITY` and the UID list ("option A").
**Why**: the app opens instantly even offline; the server stays the source of truth.
**Trade-off**: more code than "always ask the server", and the cache must be kept consistent. Details in [Sync and cache](sync-and-cache.md).

## Sorting by `INTERNALDATE` with a local index

**Decision**: keep an `arrival_dates` index of every UID and sort locally. No IMAP `SORT`.
**Why**: `SORT` is not available on Gmail; sorting by UID puts moved old mail on top.
**Trade-off**: the first sync of a big folder fetches every arrival date (in chunks of about 100 KB).

## SQLite without an ORM

**Decision**: `sqlite3` directly, hand-written SQL, no `drift`.
**Why**: few tables and simple queries, no code generation, and writing SQL is good practice.
**Trade-off**: queries aren't checked at compile time, so the cache has thorough tests. The schema is recreated instead of migrated, because it's only a cache.

## State: `ChangeNotifier`, no library

**Decision**: `ChangeNotifier` + `ListenableBuilder`, services via an `InheritedWidget` (`MailEnvironment`).
**Why**: enough for the app's size, no extra dependency, same approach as `kaamos_project_ui`.
**Trade-off**: if the state grows a lot, a library (Riverpod, Bloc) may become worth it.

## IMAP library: `enough_mail`

**Decision**: use `enough_mail`'s low-level IMAP client, not write our own and not its high-level `MailClient`.
**Why**: the most used and tested Dart IMAP/SMTP library (MPL-2.0); the low-level client gives us control over UIDs and `UIDVALIDITY`.

## No keychain, the app does not start

**Decision**: passwords only in the system keychain via `flutter_secure_storage`. If it is missing (Linux without Secret Service), the app explains why and stops.
**Why**: never store passwords in plain text, not even as a fallback.
**Trade-off**: some minimal Linux setups need GNOME Keyring or KWallet installed. See [Accounts and secrets](accounts-and-security.md).

## HTML mail: system WebView, locked down

**Decision**: one system WebView (WebView2, WKWebView, Android WebView) via `flutter_inappwebview`, with an allow-list sanitizer, JavaScript off, CSP `default-src 'none'` and all navigation cancelled. Always on a light background (no dark mode for mail).
**Why**: faithful rendering of real-world HTML, with the attack surface closed.
**Trade-off**: `flutter_inappwebview` doesn't support Linux, so Linux shows text for now. `webview_all` (MIT, WebKitGTK on Linux) was evaluated; we wait for the next `flutter_inappwebview` release first. See [Reading HTML mail](html-mail.md).

## Compose in plain text

**Decision**: plain-text compose only; HTML compose maybe much later.
**Why**: simpler, safer and smaller messages.

## Desktop compose in a floating window

**Decision** (November 2026, replacing "compose in the side pane"): on desktop, compose is a window at the bottom right over the columns, like Gmail's, with minimize and expand. One window at a time.
**Why**: you can keep reading other messages, or copy from them, while writing.
**Trade-off**: one window covers most uses with half the state to manage. Several side-by-side windows can come later without rework, because the window's state (`ComposeWindowControls`) is already outside `ComposeView`.

## Settings in a JSON file

**Decision** (November 2026): the app's settings live in `settings.json`, not in `shared_preferences`.
**Why**: one format on every platform, readable and easy to back up, no plugin to mock in tests. It holds no secrets.
**Trade-off**: we write the file ourselves (atomically, via a temporary file and a rename). See [Settings](settings.md).

## Compose "as a page" stays inside the app

**Decision** (November 2026, Alessio's choice): the "Pagina" compose mode on desktop opens inside the main window, in place of the list and the reader. Not a separate operating-system window like Outlook's.
**Why**: Flutter's desktop multi-window support is not stable yet, and a second window would need its own copy of the app's state.
**Trade-off**: you can't put the message being written side by side with the mail; the floating window covers that need. A real second window can come once Flutter supports it.

## Gmail and Outlook over IMAP + OAuth2

**Decision**: XOAUTH2 over IMAP/SMTP with PKCE and a loopback redirect, like Thunderbird and Apple Mail. No Gmail API, no Microsoft Graph.
**Why**: one code path for every provider, no proprietary APIs.
**Trade-off**: Google's `https://mail.google.com/` scope is restricted: at most 100 test users until a paid verification. See [Google and Microsoft sign-in](oauth.md).

## Design system as a git dependency

**Decision**: `kaamos_project_ui` comes from `open-ui-flutter` as a git dependency pinned to a commit (a tag once `v0.1.0` exists). No pub.dev for now.
**Why**: the library evolves together with the app; a pinned ref keeps builds reproducible.

## Icons: Lucide from the design system

**Decision** (November 2026): every icon is a Lucide icon from `KaamosIcons` (re-exported by `kaamos_project_ui`), shown with `KaamosIcon`. `MailIconButton` takes a widget (`icon: const KaamosIcon(KaamosIcons.reply)`) and sets size and colour through `IconTheme`. The app's own `CustomPaint` icons (`MailIcon`) are gone.
**Why**: one consistent set shared by every Kaamos app; release builds keep only the glyphs used.
**Trade-off**: Lucide has no filled icons and a font can't fill a shape, so the starred-message icon is `FilledStarIcon` (`lib/src/ui/widgets/mail_icons.dart`): a painted fill under Lucide's star outline. Icons must stay `const` for tree-shaking. In tests icons are Ahem boxes, like the text, because the tests don't load fonts.

## License: GPLv3

**Decision**: GPL-3.0.
**Why**: the app and its forks stay free software.

## See also

- [Architecture](architecture.md)
- [Home](README.md)
