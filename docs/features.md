[Home](README.md) › Features

# Features

What the app does, where each feature lives on a **phone** (narrower than 900 px) and on **desktop** (900 px or more, see `desktopBreakpoint` in `ui/screens/mail_home.dart`), and which UI test covers it.

This page is the spec: when a feature moves or changes, update the row and its test together. Every UI test in `test/ui/` runs twice, at 390×844 (phone) and at 1280×800 (desktop): see [Testing](testing.md#ui-tests-in-both-layouts). "—" means there is no UI test yet.

## Layouts at a glance

| | Phone | Desktop |
|---|---|---|
| Structure | One page at a time: list → message → compose | Three columns: folders (240 px), list (340 px, 400 px from 1200 px), reader |
| Folders | "Cartelle" button opens them as a page | Always visible on the left |
| Account | Avatar at the right of the search bar (of the title in "Tutte le caselle"), like Google's apps | Row at the bottom of the folders column, always visible |
| Compose | Its own page | In the reader column, beside the list |

## Start and accounts

| Feature | Phone | Desktop | Test (`test/ui/`) |
|---|---|---|---|
| No keychain: the app explains and offers "Riprova" | Full screen | Full screen | `start_test`: without a keychain |
| First start: the add-account form on the page itself (no card), no "Annulla"; after saving, the mail | One column | Two columns (from 720 px), centred | `start_test`: first start |
| Adding another account: the same form in a card, with "Annulla" | Full screen | Centred card | `accounts_test`: same address twice |
| Sign in with Google / Microsoft (disabled without client ID) | Top of the add-account screen | Same | `start_test`: sign-in buttons (a successful sign-in: —) |
| Manual IMAP and SMTP, checked before saving | Below the sign-in buttons | Same, servers side by side | `accounts_test`: manual account |
| Servers suggested from the address | Server fields | Same | `accounts_test`: servers suggested |
| Form errors, one at a time (address, password, servers, ports, duplicate) | Under the form | Same | `accounts_test`: form says what is missing, same address twice |
| Account button | Avatar at the right of the search bar; not in the folders page | Row with avatar, name and address at the bottom of the folders column | `accounts_test`: the account button |
| Account panel (a pop-up): switch, add, remove (with confirmation) | From the avatar | From the row | `accounts_test`: switching, removing, same address twice |

## Folders and list

| Feature | Phone | Desktop | Test (`test/ui/`) |
|---|---|---|---|
| Folder list: Posta in arrivo, Inviati, Bozze, Archivio, Cestino, others | "Cartelle" page | Left column | `folders_and_list_test`: folder list |
| "Tutte le caselle": every account's Inbox together | Row in the folders | Same | `accounts_test`: "Tutte le caselle" |
| Message list, newest first by arrival date | Main page | Middle column | `folders_and_list_test`: list rows |
| Row: sender, subject, preview (unread, star, attachments, account: —) | Same | Same | `folders_and_list_test`: list rows |
| Refresh | Button in the list header | Same | `folders_and_list_test`: refresh |
| Search in the folder; clearing it shows the folder again | Field in the list header | Same | `folders_and_list_test`: search |
| "Carica altri" at the bottom (50 at a time) | Same | Same | `folders_and_list_test`: "Carica altri" |
| Error banner with "Chiudi"; the cached list stays | Over the list | Same | `folders_and_list_test`: server error |

## Reading

| Feature | Phone | Desktop | Test (`test/ui/`) |
|---|---|---|---|
| Open a message (marks it read) | Its own page, "Indietro" goes back | Right column; "Scegli un messaggio da leggere" when none | `reading_test`: opening a message |
| HTML mail in a locked-down WebView; text on Linux | Same | Same | Sanitizer: `html_sanitizer_test`. The WebView itself can't run in widget tests |
| Remote images blocked, "Carica immagini" | Banner above the body | Same | `reading_test`: remote images |
| Attachments: chips, open with the system app | Below the header | Same | `reading_test`: attachments |
| Reply, reply all (only with other recipients, never to yourself), forward | Message toolbar | Same | `compose_test`: reply, reply all and forward |
| Star, mark unread | Message toolbar | Same | `reading_test`: star and mark unread |
| Archive, move to Trash | Message toolbar | Same | `reading_test`: archive, trash |
| Delete forever (in the Trash) | Message toolbar | Same | — (logic: `mailbox_controller_test`) |

## Writing

| Feature | Phone | Desktop | Test (`test/ui/`) |
|---|---|---|---|
| New message from "Scrivi" | Floating button on the list | Button at the top of the folders | `compose_test`: new message |
| To, Cc / Bcc (shown on request), subject, body | Compose page | Reader column | `compose_test`: new message (From with several accounts: —) |
| Address chips; an invalid address blocks sending | Same | Same | `compose_test`: invalid address |
| Attach files, remove them before sending | Toolbar, chips below the subject | Same | `compose_test`: attached files |
| Send | Toolbar | Same | `compose_test`: new message, reply |
| Close: empty closes at once; with text asks (delete, keep writing, save to Drafts) | Dialog | Same | `compose_test`: closing with text, empty message |

## See also

- [Testing](testing.md)
- [Architecture](architecture.md)
