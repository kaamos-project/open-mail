[Home](README.md) › Gmail labels

# Gmail labels

Gmail has labels, not folders: one message can have several, and archiving just removes the Inbox label. Over IMAP Gmail shows every label as a folder, so a message with two labels appears in two folders, with a different UID in each. Kaamos Mail reads Gmail's IMAP extensions to show the labels the way Gmail does.

## How it is read

When the server announces the `X-GM-EXT-1` capability (`ImapMailService._isGmail`):

- every `FETCH` of summaries, flags and full messages also asks for `X-GM-LABELS`. `enough_mail` parses it into `MimeMessage.xGmLabels`;
- labels arrive in IMAP's *modified UTF-7*, like folder names, and `decodeModifiedUtf7` (in `core/text_utils.dart`) decodes them, so `Caff&AOg-` becomes "Caffè";
- in `listFolders`, a folder is a **label** (`Folder.isLabel`) when it has no special role and is not one of Gmail's own folders (`[Gmail]/…` or `[Google Mail]/…`: All Mail, Starred, Important…).

Other servers are not affected: the extra items are only requested from Gmail.

## What is shown

- `MessageSummary.labels` holds every label, system ones included (`\Inbox`, `\Important`, `\Sent`…). `userLabels` keeps only the user's labels, the ones a person created.
- `MailLabels` (in `ui/widgets/common.dart`) shows them as `KaamosChip`s: small on the list row, medium under the subject in the reader. It shows every user label, also the one of the open folder: a message can have several, and in "Lavoro" you still want to see and remove "Lavoro" (Alessio's choice, November 2026; it first hid it).
- They used to be `KaamosBadge`s, which nearly vanished on the dark canvas (the badge fill is almost the canvas colour). A chip has a white 8% fill and a 16% border.
- The folder list puts labels in their own "Etichette" section, after the system folders. A label is an IMAP folder, so opening it works like any folder.

## Removing a label

In the open message each chip has an X ("Togli etichetta …"). The rows have none: removing by mistake from the list is too easy.

- `MailboxController.removeLabel` is optimistic like the star: the chip disappears at once (screen and cache), then `MailService.storeLabels` runs `UID STORE <uid> -X-GM-LABELS.SILENT ("<label>")` on the open folder. If the server refuses, the label comes back and the error shows (on the phone, in a banner on the message page).
- Labels are kept decoded in the app, so they are encoded back with `encodeModifiedUtf7` and quoted with `imapQuote`.
- **enough_mail's private API.** `uidStore` can only write `FLAGS`, and enough_mail has no public way to send another STORE item. `storeLabels` uses its `Command` and `GenericParser` from `src/private`, with an `ignore: implementation_imports`. If an update of enough_mail breaks it, it breaks in that one method; an upstream PR that adds a public way would remove the import.
- Removing the label of the open folder makes the message leave that folder, as in Gmail. `removeLabel` sees it (`isFolderLabel`, which compares the decoded folder path) and takes the message out of the list like a move; on the phone the message page goes back to the list, like after Archive.

## Cache

Labels are saved in `messages.labels_json`, and the label flag in `folders.is_label` (schema version 3). Labels change on other devices just like flags do, so every refresh that re-reads the flags also re-reads the labels. When a server reports no labels (`MessageFlagsState.labels` is null), the saved ones are kept.

## Not yet

- **Adding labels** (it needs a label picker), and Gmail-style archive and delete (step 2).
- **No duplicates**: a message with two labels is cached once per folder. `X-GM-MSGID`, the same in every folder, will join them together with threading (`X-GM-THRID`).
- **Label colours**: Gmail does not expose them over IMAP, so the chips are neutral. A colour derived from the name would not match what you see on the web.

## See also

- [Sync and cache](sync-and-cache.md)
- [Features](features.md#gmail-labels)
