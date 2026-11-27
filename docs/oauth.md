[Home](README.md) › Google and Microsoft sign-in

# Google and Microsoft sign-in (OAuth2)

Kaamos Mail uses IMAP and SMTP for Gmail and Outlook too, like Thunderbird and Apple Mail. Instead of the password it sends an *access token* with the XOAUTH2 mechanism. No Gmail API, no Microsoft Graph, so the rest of the app does not change.

## How it works

```mermaid
sequenceDiagram
    participant App
    participant Browser as System browser
    participant P as Provider (Google / Microsoft)
    participant K as Keychain

    App->>App: create PKCE code_verifier + state
    App->>Browser: open sign-in page (code_challenge)
    Browser->>P: user signs in (password, 2FA)
    P->>Browser: redirect to http://127.0.0.1:<random port>?code=…
    Browser->>App: loopback server receives code, checks state
    App->>P: exchange code + code_verifier
    P-->>App: access token + refresh token
    App->>K: save refresh token only
    App->>App: IMAP/SMTP login with XOAUTH2 (access token)
```

1. "Sign in with Google" opens the provider's page in the **system browser** (on iOS in a system sheet, `ASWebAuthenticationSession`; on Android in a Custom Tab). The app never sees your password or second factor.
2. The provider sends a code back (RFC 8252):
   - on desktop the app listens on `127.0.0.1` (or `localhost`) on a random port, and the browser comes back there ("loopback redirect", the diagram above);
   - on iOS the page redirects to an app URL scheme and the sheet closes by itself;
   - on Android the same redirect opens the app again through an intent-filter, and the Custom Tab closes.
3. The app exchanges the code for tokens using PKCE (RFC 7636): only whoever started the sign-in knows the `code_verifier`, so a stolen code is useless.
4. Only the **refresh token** goes in the keychain. The access token lasts about an hour and stays in memory; when it expires the app asks for a new one. One refresh serves concurrent IMAP and SMTP logins. If Microsoft sends a new refresh token, it replaces the old one.

It works on Windows, macOS, Linux, iOS and Android.

### Android in detail

- `MainActivity.kt` opens the page in a Custom Tab (`androidx.browser`). The tab uses the browser's cookies and saved passwords, never the app's memory.
- The redirect scheme is caught by an intent-filter in `AndroidManifest.xml`. The activity is `singleTask`, so the redirect closes the tab and arrives in `onNewIntent`.
- If the user closes the tab, the activity resumes without a redirect: that counts as "canceled".
- Google's scheme depends on the client ID, so `build.gradle.kts` reads `KAAMOS_GOOGLE_ANDROID_CLIENT_ID` from the `--dart-define`s and puts it in the manifest.
- Unlike iOS, another app could register the same scheme. PKCE is what makes a stolen code useless.

### Code map

| File | Role |
|---|---|
| `core/oauth.dart` | Provider config (endpoints, scopes, client IDs from `--dart-define`), PKCE helpers, token parsing |
| `data/oauth_client.dart` | The loopback (desktop) and app-session (iOS, Android) sign-in flows, token exchange and refresh |
| `data/imap_mail_service.dart` | `ImapMailServiceFactory` builds the XOAUTH2 login and saves rotated refresh tokens |
| `ui/platform.dart` | `platformOAuthSignIn()`: loopback on desktop, the native sheet on iOS and Android |
| `ios/Runner/AppDelegate.swift` | `AuthSessionPlugin`: shows `ASWebAuthenticationSession` on the `dev.kaamos_project.mail/oauth` channel |
| `android/app/src/main/kotlin/.../MainActivity.kt` | The same channel on Android: Custom Tab, redirect in `onNewIntent` |

## Registering the app

Client IDs are not secrets, but every build needs one. Pass them with `--dart-define`:

```sh
# Desktop
flutter run -d windows \
  --dart-define=KAAMOS_GOOGLE_CLIENT_ID=xxxx.apps.googleusercontent.com \
  --dart-define=KAAMOS_GOOGLE_CLIENT_SECRET=GOCSPX-xxxx \
  --dart-define=KAAMOS_MICROSOFT_CLIENT_ID=00000000-0000-0000-0000-000000000000

# iOS: Google needs a separate client, Microsoft reuses the same one
flutter run -d ios \
  --dart-define=KAAMOS_GOOGLE_IOS_CLIENT_ID=yyyy.apps.googleusercontent.com \
  --dart-define=KAAMOS_MICROSOFT_CLIENT_ID=00000000-0000-0000-0000-000000000000

# Android: another Google client, the same Microsoft one
flutter run -d android \
  --dart-define=KAAMOS_GOOGLE_ANDROID_CLIENT_ID=zzzz.apps.googleusercontent.com \
  --dart-define=KAAMOS_MICROSOFT_CLIENT_ID=00000000-0000-0000-0000-000000000000
```

Without them the buttons stay disabled and the screen says which one is missing. A fork can use its own IDs without touching the code.

### Google

1. In the [Google Cloud Console](https://console.cloud.google.com/) create a project.
2. In "Google Auth Platform" configure the consent screen: type **External**, app name, support email.
3. In "Data access" add the scope `https://mail.google.com/`. It is a *restricted* scope.
4. In "Audience" leave the app in **Testing** and add the test users (at most 100).
5. In "Clients" create a client of type **Desktop app**. You get a client ID and a client secret. For desktop clients Google says the secret is not confidential, but its token endpoint still requires it.
6. For iOS create a second client of type **iOS** with bundle ID `dev.kaamos-project.mail`. It has no secret. The redirect is the reversed client ID (`com.googleusercontent.apps.yyyy:/oauth2redirect`) and the app works it out by itself.
7. For Android create a third client of type **Android** with package name `dev.kaamos_project.mail` and the SHA-1 of your signing key (`keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android` for debug builds). In its "Advanced settings" turn on **Enable custom URI scheme**: the app uses `com.googleusercontent.apps.zzzz:/oauth2redirect`, like on iOS.

Good to know:

- While the app is in Testing, Google expires refresh tokens after 7 days. Then you have to remove and add the account again.
- Leaving Testing with a restricted scope requires Google's verification, with a paid yearly security assessment.

### Microsoft

1. In [Microsoft Entra](https://entra.microsoft.com/) go to "App registrations" and choose "New registration".
2. In "Supported account types" choose accounts in any organization and **personal Microsoft accounts**.
3. As redirect URI choose the platform **Public client/native (mobile & desktop)** with value `http://localhost`. Microsoft ignores the port for loopback addresses.
   For iOS add the **iOS / macOS** platform with bundle ID `dev.kaamos-project.mail`. Entra creates the redirect `msauth.dev.kaamos-project.mail://auth`, which is the one the app uses.
   For Android add a custom redirect `dev.kaamos-project.mail://auth` under **Mobile and desktop applications**. It is not the package name, because a URL scheme can't contain `_`: it is the iOS bundle ID.
4. In "API permissions" add the delegated permissions:
   - `IMAP.AccessAsUser.All` and `SMTP.Send` from Office 365 Exchange Online (`https://outlook.office.com`);
   - `offline_access`, `openid`, `email` and `profile`.
5. The client ID is the "Application (client) ID". No secret is needed, on desktop or mobile.

Good to know: on work accounts the administrator may have turned off IMAP or SMTP AUTH. In that case sign-in succeeds but the server check fails.

## See also

- [Accounts and secrets](accounts-and-security.md)
- [Decisions](decisions.md#gmail-and-outlook-over-imap--oauth2)
