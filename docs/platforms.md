[Home](README.md) › Platforms

# Platforms

Supported in the MVP: **Windows, macOS, Android, iOS**. Linux arrives in phase 2. There is no web build: a browser cannot open TCP sockets to IMAP, and a proxy would be a server (see [Decisions](decisions.md#native-only-no-web)).

## App identifiers

The domain is `kaamos-project.dev`, so the IDs are that domain reversed. The visible name is "Kaamos Mail" everywhere.

| Platform | ID | Why this form |
|---|---|---|
| Android | `dev.kaamos_project.mail` | A Java/Kotlin package name can't contain `-`, so the domain's hyphen becomes `_` |
| iOS, macOS | `dev.kaamos-project.mail` | A bundle ID allows only letters, digits, `-` and `.`: no `_` |

The OAuth redirect schemes come from these IDs (see [OAuth sign-in](oauth.md#registering-the-app)). A URL scheme can't contain `_`, so Android's Microsoft redirect uses the iOS form, `dev.kaamos-project.mail://auth`.

The Dart package stays `kaamos_mail` and the keychain keys keep the `kaamos_mail.` prefix: they are internal names, and changing them would gain nothing.

## Windows

- The WebView is WebView2, already present on up-to-date Windows 10/11.
- Passwords are stored in `flutter_secure_storage.dat` in the app data folder, encrypted with DPAPI: the key is tied to your Windows user.
- Building needs the Visual Studio **ATL** component.
- **Visual Studio 2026**: `flutter_inappwebview` fails with `STL1011` (`<experimental/coroutine>`). The local workaround is `add_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)` in `windows/CMakeLists.txt`, before `include(flutter/generated_plugins.cmake)` (not inside `APPLY_STANDARD_SETTINGS`, which the plugin doesn't use). It is not committed yet: we are waiting for a plugin release that fixes it.

## macOS

- The app is sandboxed with `network.client`, and the release entitlements also allow the loopback server used by [OAuth sign-in](oauth.md).
- If the keychain refuses to save, add the "Keychain Sharing" capability in Xcode (needs a signing team).

## iOS

- Passwords go in the Keychain; no special permissions.
- OAuth sign-in uses `ASWebAuthenticationSession` (in `AppDelegate.swift`), no extra package: see [OAuth sign-in](oauth.md).

## Android

- `INTERNET` permission.
- Backup is disabled, so cache and keys don't end up in Google's backup.
- The WebView also has `blockNetworkLoads`.
- The main activity is `singleTask`: OAuth sign-in opens a Custom Tab, and the redirect comes back to the same activity (see [OAuth sign-in](oauth.md#android-in-detail)).

## Linux (phase 2)

- Needs GNOME Keyring or KWallet (Secret Service). Without it the app doesn't start and explains why: see [Accounts and secrets](accounts-and-security.md#no-keychain-no-app).
- HTML mail is shown as text for now, because `flutter_inappwebview` does not support Linux: see [Reading HTML mail](html-mail.md#linux).

## See also

- [Getting started](getting-started.md)
