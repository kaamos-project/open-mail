[Home](README.md) › Compose and send

# Compose and send

## Starting a message: `ComposeDraft`

`state/compose_draft.dart` is pure logic (no widgets), so the reply rules can be tested in `test/compose_draft_test.dart`.

| Kind | To | Cc | Subject | Body |
|---|---|---|---|---|
| New | empty | empty | empty | empty |
| Reply | `Reply-To` if present, otherwise the sender | empty | `Re: …` | quoted original |
| Reply all | as Reply | every other recipient of the original, without duplicates and **without yourself** | `Re: …` | quoted original |
| Forward | empty | empty | `Fwd: …` | forwarded original |

If you reply to a message you wrote yourself (for example from Sent), replying to yourself makes no sense, so your own address is dropped unless the list would end up empty.

Replies carry `In-Reply-To` and `References` (the conversation's `Message-ID` chain), so other clients thread them correctly.

## Writing

- **Plain text only.** HTML compose may come much later.
- On **desktop** the compose view takes the place of the reader in the side pane; on **mobile** it is a new page.
- The text area is `MailTextArea` (`ui/widgets/text_area.dart`), a local widget until a `KaamosTextArea` exists in `kaamos_project_ui`.
- Attachments are picked with `file_picker` through `FileActions`.

## Sending: `MailboxController.send`

```mermaid
flowchart TD
    send["service.send() over SMTP"] --> raw["RFC 822 text"]
    raw --> gmail{"SMTP host is gmail.com?"}
    gmail -- no --> append["APPEND to Sent with \\Seen"]
    gmail -- yes --> skip["skip: Gmail saves it itself"]
    append --> answered
    skip --> answered{"Is it a reply?"}
    answered -- yes --> flag["mark original as answered (optimistic)"]
```

- If the copy in Sent fails, the mail **was** sent: the error says so explicitly.
- **Bcc never goes in the headers.** It is only added to the SMTP recipient list, otherwise every recipient would see the hidden addresses.
- When replying from the [Unified Inbox](unified-inbox.md), `answeredPath` points to the original's folder, which may not be the folder the account is showing.

## Drafts

`saveDraft` renders the message without sending it (`service.render`) and appends it to the Drafts folder with `\Draft` and `\Seen`. If the account has no Drafts folder it returns `false` and the UI says so.

## See also

- [Architecture](architecture.md#state)
- [Accounts and secrets](accounts-and-security.md)
