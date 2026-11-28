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
- `MailLabels` (in `ui/widgets/common.dart`) shows them as badges on the list row and under the subject in the reader. It leaves out the label of the open folder: in "Lavoro" every message has "Lavoro".
- The folder list puts labels in their own "Etichette" section, after the system folders. A label is an IMAP folder, so opening it works like any folder.

## Cache

Labels are saved in `messages.labels_json`, and the label flag in `folders.is_label` (schema version 3). Labels change on other devices just like flags do, so every refresh that re-reads the flags also re-reads the labels. When a server reports no labels (`MessageFlagsState.labels` is null), the saved ones are kept.

## Not yet

- **Adding and removing labels**, and Gmail-style archive and delete (step 2).
- **No duplicates**: a message with two labels is cached once per folder. `X-GM-MSGID`, the same in every folder, will join them together with threading (`X-GM-THRID`).
- **Label colours**: Gmail does not expose them over IMAP, so the badges are neutral.

## See also

- [Sync and cache](sync-and-cache.md)
- [Features](features.md#gmail-labels)
