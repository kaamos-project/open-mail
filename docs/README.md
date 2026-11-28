# Kaamos Mail wiki

Kaamos Mail is a free (GPLv3), client-only, privacy-first email client built with Flutter. It talks directly to your IMAP/SMTP server: no Kaamos server in between, no telemetry, passwords only in the operating system keychain.

This wiki explains **how the app works and why it is built this way**. Start from the top and follow the links, or jump to the page you need.

## Pages

| Page | What you will find |
|---|---|
| [Getting started](getting-started.md) | Install Flutter, run the app, the checks CI runs |
| [Architecture](architecture.md) | The four layers (`core`, `data`, `state`, `ui`) and how they talk |
| [Error handling](error-handling.md) | Server failures (`MailFailure`) versus bugs, and where each is caught |
| [Sync and cache](sync-and-cache.md) | How a folder is refreshed, the SQLite schema, sorting by arrival date |
| [Accounts and secrets](accounts-and-security.md) | `accounts.json`, the keychain, what happens without one |
| [Google and Microsoft sign-in](oauth.md) | OAuth2 + XOAUTH2, registering the app, client IDs |
| [Reading HTML mail](html-mail.md) | The three walls: sanitizer, JavaScript off, no network |
| [Compose and send](compose-and-send.md) | Reply rules, drafts, the copy in Sent |
| [Unified Inbox](unified-inbox.md) | Every account's Inbox in one list |
| [Gmail labels](gmail-labels.md) | How Gmail's labels are read over IMAP and shown |
| [Settings](settings.md) | The app's preferences, `settings.json`, where each one applies |
| [Features](features.md) | What the app does, where each feature is on phone and desktop, which test covers it |
| [Platforms](platforms.md) | Windows, macOS, iOS, Android and Linux notes |
| [Testing](testing.md) | Fakes, what is tested and how |
| [Decisions](decisions.md) | The key choices and their trade-offs |

## Status

- **Phase 1 (MVP)**: done. One IMAP/SMTP account, folders, reading, compose, attachments, actions, server search.
- **Phase 2**: in progress. Multi-account and unified Inbox are done; OAuth2 works on desktop, iOS and Android.
- **Phase 3**: PGP, filters, snooze, templates, JMAP, calendar invites.

## Writing these pages

- One page per topic, in English, linked with relative links only.
- Every page starts with a `[Home](README.md) › Page` breadcrumb and ends with "See also".
- A pull request that changes behaviour also updates the page that describes it.
