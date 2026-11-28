[Home](README.md) › Settings

# Settings

The app's own preferences: how remote images are handled, how the desktop lays out the mail, and how compose opens on desktop. They are not per account: one set for the whole app, on this device.

## Where they are

| | Phone | Desktop |
|---|---|---|
| Entry | "Impostazioni" row at the bottom of the folders drawer | Gear button to the right of the account row, at the bottom of the folders column |
| Page | Full page, "Indietro" goes back | Same: a full page over the mail, centred (at most 640 px), no card |

Every choice applies at once: there is no "Save" button.

## The choices

| Setting | Values (default first) | What changes |
|---|---|---|
| Immagini remote | `ask` "Chiedi ogni volta", `always` "Carica sempre" | `always` starts every message with remote images allowed, so the "Carica immagini" banner never shows. The sanitizer still runs: only the image loading changes (see [Reading HTML mail](html-mail.md)) |
| Disposizione su desktop | `split` "Lista e lettura affiancate", `list` "Solo lista" | `list`, like classic Gmail: the list takes the whole area right of the folders; opening a message replaces it, and "Indietro" brings the list back. As wide as the window, the list shows one line per message like Gmail: sender in a 200 px column, label chips (at most 240 px, no wrap), subject and preview cut with "…", date at the right |
| Scrittura su desktop | `window` "Finestra flottante", `page` "Pagina" | `page`: compose takes the area right of the folders, with "Chiudi", instead of the floating window at the bottom right |

On the phone the list, the message and compose are always pages, so the last two settings only matter from 900 px up (`desktopBreakpoint`).

## How it is built

```
core/settings.dart          AppSettings (immutable) + the three enums
data/settings_store.dart    SettingsStore: FileSettingsStore (settings.json), MemorySettingsStore (tests)
state/settings_controller   SettingsController (ChangeNotifier): load() at start, update() on every change
ui/environment.dart         MailEnvironment.settings, so any widget can read them
ui/screens/settings_screen  The page
```

- **File.** `settings.json` sits next to `accounts.json` in the app's support folder. It holds no secrets, so it is a plain file (passwords and tokens stay in the keychain, see [Accounts and secrets](accounts-and-security.md)). It is written to `settings.json.tmp` and renamed, so a crash mid-write never leaves half a file.
- **Format.** `{"version": 1, "remoteImages": "ask", "layout": "split", "compose": "window"}`, with enum names, not indexes, so reordering an enum doesn't change saved choices. An unknown value, a missing key or a broken file gives the default instead of an error: a bad settings file must never stop the mail from opening.
- **Updates.** `update()` notifies first and saves after, so the UI changes without waiting for the disk.
- **Who listens.** `MailHome` rebuilds the desktop on a settings change (a `ListenableBuilder`). The message body reads `remoteImages` once when a message opens: changing it doesn't reload the message already on screen.
- **"Solo lista" and "Pagina" keep the list alive.** The hidden list stays in the tree under `Offstage` (and `TickerMode` off), so going back finds it scrolled where it was, without a reload.

## Why not shared_preferences

`shared_preferences` would be one more plugin with a different backend on every platform (the registry on Windows, `NSUserDefaults` on Apple, XML on Android). A small JSON file works the same everywhere, is easy to read and back up, and keeps tests free of plugin mocks. See [Decisions](decisions.md).

## Tests

- `test/settings_test.dart`: JSON round trip, fallbacks, the file store (atomic write, broken file).
- `test/ui/settings_test.dart`: the page opens from the gear and from the drawer and saves; "Carica sempre"; "Solo lista" (one-line rows); switching layout at once; compose as a page.

## See also

- [Features](features.md)
- [Reading HTML mail](html-mail.md)
- [Architecture](architecture.md)
- [Home](README.md)
