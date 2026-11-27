[Home](README.md) › Accounts and secrets

# Accounts and secrets

An account lives in **two places**, on purpose:

| What | Where | Why |
|---|---|---|
| Servers, ports, address, name, optional `oauth` provider | `accounts.json` in the app data folder | Harmless to copy or back up |
| Password (or OAuth2 refresh token) | System keychain, key `kaamos_mail.account.<id>.password` | Must never be on disk in plain text |

The app data folder comes from `path_provider` (`getApplicationSupportDirectory()`): for example `%APPDATA%` on Windows or Application Support on macOS/iOS. It also holds the cache `mail.db` (see [Sync and cache](sync-and-cache.md)).

## `AccountRepository`

`data/account_repository.dart`:

- **`save`** writes the password to the keychain **first**, then the JSON. If the keychain fails, no account is left without credentials.
- **`_write`** is atomic: it writes `accounts.json.tmp` and then renames it. If the app quits halfway, the old file stays intact.
- **`remove`** deletes the keychain entry and the JSON entry. `MailSession` also deletes the account's cache.
- **`updatePassword`** replaces the secret, used when Microsoft rotates a refresh token.

The JSON has a `version` field (currently `1`) so the format can evolve.

## `SecretStore` and the keychain

`data/secret_store.dart` defines a small interface (`isAvailable`, `read`, `write`, `delete`) with two implementations:

- **`SystemSecretStore`** uses `flutter_secure_storage`:
  - Windows: a DPAPI-encrypted file, whose key is tied to your Windows user;
  - macOS and iOS: Keychain;
  - Android: Keystore;
  - Linux: Secret Service (GNOME Keyring or KWallet).
- **`MemorySecretStore`** is for tests. With `available: false` it simulates Linux without Secret Service.

There is no "is there a keychain?" API, so `isAvailable()` writes, reads back and deletes a probe value.

## No keychain, no app

If `isAvailable()` is false, the app shows `KeychainMissingScreen`, which explains what to install, and does not start. Storing passwords in plain text as a fallback was rejected: see [Decisions](decisions.md#no-keychain-the-app-does-not-start).

## Adding an account

`AccountSetupScreen` asks for IMAP and SMTP settings (or offers Google / Microsoft sign-in), then calls `MailServiceFactory.check()`. It tests **both** servers with the real credentials and shows a readable error for each before saving anything. `describeMailError` turns network and protocol errors into sentences for the user.

## OAuth2 accounts

For Google and Microsoft the keychain slot holds the **refresh token** instead of a password. The access token lives only in memory and is refreshed shortly before it expires. Details in [Google and Microsoft sign-in](oauth.md).

## Other privacy measures

- No telemetry, no Kaamos server.
- On Android, backup is disabled so cache and keys don't end up in Google's backup.
- Bcc recipients never go in the headers: see [Compose and send](compose-and-send.md).
- Remote content in HTML mail is blocked: see [Reading HTML mail](html-mail.md).

## See also

- [Google and Microsoft sign-in](oauth.md)
- [Platforms](platforms.md)
