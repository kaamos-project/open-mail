[Home](README.md) › Features

# Features

What the app does, where each feature lives on a **phone** (narrower than 900 px) and on **desktop** (900 px or more, see `desktopBreakpoint` in `ui/screens/mail_home.dart`), and which UI test covers it.

This page is the spec: when a feature moves or changes, update the row and its test together. "—" in the Test column means there is no UI test yet. The logic underneath may still be tested in the unit tests (see [Testing](testing.md)).

## Layouts at a glance

| | Phone | Desktop |
|---|---|---|
| Structure | One page at a time: list → message → compose | Three columns: folders (240 px), list (340 px, 400 px from 1200 px), reader |
| Folders | "Cartelle" button opens them as a page | Always visible on the left |
| Compose | Its own page | In the reader column, beside the list |

## Start and accounts

| Feature | Phone | Desktop | Test |
|---|---|---|---|
| No keychain: the app explains and offers "Riprova" | Full screen | Full screen | `app_test`: without a keychain |
| First start: add-account screen | One column | Two columns (from 720 px) | `app_test`: first start |
| Sign in with Google / Microsoft (disabled without client ID) | Top of the add-account screen | Same | `app_test`: sign-in buttons |
| Manual IMAP and SMTP with a check before saving | Below the sign-in buttons | Same, servers side by side | — |
| Form errors (address, password, servers, ports, duplicate account) | Under the form | Same | — |
| Account panel: switch, add, remove (with confirmation) | From the account button in the folders | Same | `app_test`: switch account, cancellable add (remove: —) |

## Folders and list

| Feature | Phone | Desktop | Test |
|---|---|---|---|
| Folder list with the account's folders | "Cartelle" page | Left column | — |
| "Tutte le caselle": every account's Inbox together | Row in the folders | Same | `app_test`: all inboxes together (desktop only) |
| Message list, newest first by arrival date | Main page | Middle column | `app_test`: desktop, mobile |
| Row: sender, subject, preview, unread, star, attachments, account (in the unified Inbox) | Same | Same | — |
| Refresh | Button in the list header | Same | — |
| Search in the folder | Field in the list header | Same | — |
| "Carica altri" at the bottom | Same | Same | — |
| Error banner with "Chiudi" | Over the list | Same | — |

## Reading

| Feature | Phone | Desktop | Test |
|---|---|---|---|
| Open a message (marks it read) | Its own page, "Indietro" goes back | Right column; "Scegli un messaggio da leggere" when none | `app_test`: desktop, mobile |
| HTML mail in a locked-down WebView; text on Linux | Same | Same | Sanitizer: `html_sanitizer_test` (UI: —) |
| Remote images blocked, "Carica immagini" | Banner above the body | Same | — |
| Attachments: list, open with the system app | Below the body | Same | — |
| Actions: reply, reply all, forward | Message toolbar | Same | `app_test`: reply on desktop (others: —) |
| Actions: star, mark unread, archive, trash / delete forever | Message toolbar | Same | Logic: `mailbox_controller_test` (UI: —) |

## Writing

| Feature | Phone | Desktop | Test |
|---|---|---|---|
| New message from "Scrivi" | Floating button on the list | Button at the top of the folders | `app_test`: invalid address |
| To, Cc / Bcc (shown on request), From, subject, body | Compose page | Reader column | Partly: `app_test` |
| Address chips, invalid address blocks sending | Same | Same | `app_test`: invalid address |
| Attach files | Toolbar | Same | — |
| Send | Toolbar | Same | `app_test`: reply on desktop |
| Close with unsaved text: delete, keep writing, save as draft | Dialog | Same | — |

## See also

- [Testing](testing.md)
- [Architecture](architecture.md)
