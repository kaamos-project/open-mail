[Home](README.md) › Getting started

# Getting started

## Requirements

- **Flutter 3.50.1** (the same version CI and the `kaamos_project_ui` library use).
- The toolchain of the platform you build for:
  - **Windows**: Visual Studio with the "Desktop development with C++" workload **and the ATL component** (needed by `flutter_secure_storage_windows`). WebView2 is already on up-to-date Windows 10/11.
  - **macOS / iOS**: Xcode.
  - **Android**: Android Studio or the Android SDK.

See [Platforms](platforms.md) for the details of each one.

## Run the app

```sh
flutter pub get
flutter run -d windows   # or macos, ios, android
```

To enable "Sign in with Google / Microsoft" you also pass the client IDs with `--dart-define`: see [Google and Microsoft sign-in](oauth.md#registering-the-app).

## Project layout

```
lib/
  main.dart     creates the real services and starts the app
  src/
    core/       pure logic, no Flutter: models, text, HTML cleaning, OAuth
    data/       IMAP/SMTP (enough_mail), SQLite cache, keychain, OAuth client
    state/      controllers (ChangeNotifier): session, mailbox, unified Inbox, drafts
    ui/         screens, views and widgets (kaamos_project_ui)
test/           unit and widget tests, with fakes in test/support/
docs/           this wiki
```

The [Architecture](architecture.md) page explains each layer.

## Checks (the same as CI)

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

CI (`.github/workflows/ci.yml`) runs these on Linux for every push to `main` and every pull request. It does **not** build native apps yet: tests don't need a WebView, a keychain or the network. See [Testing](testing.md).

## Conventions

- Code comments, commits and pull requests are in English.
- UI strings are still in Italian until i18n arrives.
- No state management library and no ORM: see [Decisions](decisions.md).

## See also

- [Architecture](architecture.md)
- [Platforms](platforms.md)
- [Testing](testing.md)
