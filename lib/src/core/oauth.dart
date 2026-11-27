import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'models.dart';

/// Everything that differs between OAuth2 providers.
///
/// Mail goes over plain IMAP and SMTP with the XOAUTH2 mechanism, like
/// Thunderbird and Apple Mail: no Gmail API or Microsoft Graph, so the rest
/// of the app does not change.
class OAuthConfig {
  /// Creates a provider configuration.
  const OAuthConfig({
    required this.provider,
    required this.label,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.scopes,
    required this.clientId,
    required this.imap,
    required this.smtp,
    this.clientSecret = '',
    this.extraAuthParams = const {},
    this.loopbackHost = '127.0.0.1',
    this.appRedirect,
  });

  /// Which provider.
  final OAuthProvider provider;

  /// Name shown on the sign-in button.
  final String label;

  /// Where the browser goes to sign in.
  final Uri authorizationEndpoint;

  /// Where the app exchanges the code and refreshes tokens.
  final Uri tokenEndpoint;

  /// What the app asks for: mail access plus `openid email` to learn the
  /// address.
  final List<String> scopes;

  /// The app's public identifier, from the provider's developer console.
  final String clientId;

  /// Google's "desktop app" clients get a secret that Google itself says is
  /// not confidential, and its token endpoint still wants it. Empty for
  /// Microsoft.
  final String clientSecret;

  /// Provider-specific parameters for the sign-in page.
  final Map<String, String> extraAuthParams;

  /// Host of the desktop redirect URI, as registered with the provider.
  /// Google accepts `127.0.0.1` for desktop clients; Microsoft's portal
  /// registers `http://localhost` and ignores the port.
  final String loopbackHost;

  /// On iOS: the redirect to a custom URL scheme of the app, which the
  /// system sign-in sheet catches. `null` on desktop (loopback).
  ///
  /// A string, not a [Uri]: `Uri` lowercases the scheme, and the provider
  /// compares the redirect character by character.
  final String? appRedirect;

  /// The provider's IMAP server.
  final ServerConfig imap;

  /// The provider's SMTP server.
  final ServerConfig smtp;

  /// The client ID is set: without it the sign-in button is disabled.
  bool get isConfigured => clientId.isNotEmpty;

  /// The sign-in page URL for one attempt.
  Uri authorizationUrl({
    required String redirectUri,
    required String state,
    required String codeChallenge,
    String? loginHint,
  }) => authorizationEndpoint.replace(
    queryParameters: {
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': redirectUri,
      'scope': scopes.join(' '),
      'state': state,
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
      'login_hint': ?loginHint,
      ...extraAuthParams,
    },
  );

  /// The form that exchanges the authorization [code] for tokens.
  Map<String, String> codeExchangeForm({
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) => {
    'grant_type': 'authorization_code',
    'code': code,
    'code_verifier': codeVerifier,
    'redirect_uri': redirectUri,
    'client_id': clientId,
    if (clientSecret.isNotEmpty) 'client_secret': clientSecret,
  };

  /// The form that gets a new access token from a refresh token.
  Map<String, String> refreshForm(String refreshToken) => {
    'grant_type': 'refresh_token',
    'refresh_token': refreshToken,
    'client_id': clientId,
    if (clientSecret.isNotEmpty) 'client_secret': clientSecret,
  };
}

/// Where the app runs: each kind of app has its own client at the provider.
enum OAuthTarget {
  /// Windows, macOS, Linux: loopback redirect.
  desktop,

  /// iOS: custom URL scheme caught by `ASWebAuthenticationSession`.
  ios,

  /// Android: custom URL scheme caught by `MainActivity` after a Custom
  /// Tab.
  android,
}

/// The iOS bundle identifier (see `ios/Runner.xcodeproj`). A bundle ID allows
/// only letters, digits, `-` and `.`, so it can't be the Android ID.
const iosBundleId = 'dev.kaamos-project.mail';

/// The Microsoft redirect on Android. Not the application ID: a URL scheme
/// can't contain `_` (RFC 3986), and `dev.kaamos_project.mail` does. It
/// matches the iOS bundle ID instead.
const androidRedirect = 'dev.kaamos-project.mail://auth';

/// Client IDs come from `--dart-define`, so a fork can use its own without
/// touching the code, e.g.
/// `flutter run --dart-define=KAAMOS_GOOGLE_CLIENT_ID=...`.
const _googleClientId = String.fromEnvironment('KAAMOS_GOOGLE_CLIENT_ID');
const _googleIosClientId = String.fromEnvironment(
  'KAAMOS_GOOGLE_IOS_CLIENT_ID',
);
const _googleAndroidClientId = String.fromEnvironment(
  'KAAMOS_GOOGLE_ANDROID_CLIENT_ID',
);
const _googleClientSecret = String.fromEnvironment(
  'KAAMOS_GOOGLE_CLIENT_SECRET',
);
const _microsoftClientId = String.fromEnvironment('KAAMOS_MICROSOFT_CLIENT_ID');

/// Google's redirect for iOS and Android clients: the client ID reversed
/// as the URL scheme (`com.googleusercontent.apps.<id>:/oauth2redirect`).
String? googleAppRedirect(String clientId) {
  const suffix = '.apps.googleusercontent.com';
  if (!clientId.endsWith(suffix)) return null;
  final id = clientId.substring(0, clientId.length - suffix.length);
  return 'com.googleusercontent.apps.$id:/oauth2redirect';
}

/// The configuration of [provider] for [target].
///
/// The token must always be refreshed with the client that issued it, so
/// sign-in and IMAP/SMTP use the same [target].
OAuthConfig oauthConfig(
  OAuthProvider provider, {
  OAuthTarget target = OAuthTarget.desktop,
}) => switch (provider) {
  OAuthProvider.google => OAuthConfig(
    provider: provider,
    label: 'Google',
    authorizationEndpoint: Uri.parse(
      'https://accounts.google.com/o/oauth2/v2/auth',
    ),
    tokenEndpoint: Uri.parse('https://oauth2.googleapis.com/token'),
    scopes: const ['https://mail.google.com/', 'openid', 'email', 'profile'],
    // iOS and Android clients have no secret: PKCE alone.
    clientId: switch (target) {
      OAuthTarget.desktop => _googleClientId,
      OAuthTarget.ios => _googleIosClientId,
      OAuthTarget.android => _googleAndroidClientId,
    },
    clientSecret: target == OAuthTarget.desktop ? _googleClientSecret : '',
    appRedirect: switch (target) {
      OAuthTarget.desktop => null,
      OAuthTarget.ios => googleAppRedirect(_googleIosClientId),
      OAuthTarget.android => googleAppRedirect(_googleAndroidClientId),
    },
    // offline + consent: without them Google gives no refresh token, and
    // the account would stop working after an hour.
    extraAuthParams: const {'access_type': 'offline', 'prompt': 'consent'},
    imap: const ServerConfig(
      host: 'imap.gmail.com',
      port: 993,
      security: ConnectionSecurity.tls,
    ),
    smtp: const ServerConfig(
      host: 'smtp.gmail.com',
      port: 465,
      security: ConnectionSecurity.tls,
    ),
  ),
  OAuthProvider.microsoft => OAuthConfig(
    provider: provider,
    label: 'Microsoft',
    // "common": personal accounts (Outlook.com) and work or school ones.
    authorizationEndpoint: Uri.parse(
      'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
    ),
    tokenEndpoint: Uri.parse(
      'https://login.microsoftonline.com/common/oauth2/v2.0/token',
    ),
    scopes: const [
      'https://outlook.office.com/IMAP.AccessAsUser.All',
      'https://outlook.office.com/SMTP.Send',
      'offline_access',
      'openid',
      'email',
      'profile',
    ],
    clientId: _microsoftClientId,
    extraAuthParams: const {'prompt': 'select_account'},
    loopbackHost: 'localhost',
    // Same client ID everywhere: one app registration, one redirect per
    // platform. On iOS the one Entra suggests for the bundle ID.
    appRedirect: switch (target) {
      OAuthTarget.desktop => null,
      OAuthTarget.ios => 'msauth.$iosBundleId://auth',
      OAuthTarget.android => androidRedirect,
    },
    imap: const ServerConfig(
      host: 'outlook.office365.com',
      port: 993,
      security: ConnectionSecurity.tls,
    ),
    smtp: const ServerConfig(
      host: 'smtp.office365.com',
      port: 587,
      security: ConnectionSecurity.startTls,
    ),
  ),
};

/// A random PKCE `code_verifier` (RFC 7636): 64 characters from the
/// unreserved set, made from 48 secure random bytes.
String createCodeVerifier([Random? random]) {
  final r = random ?? Random.secure();
  final bytes = List<int>.generate(48, (_) => r.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// The `code_challenge` for [verifier] with the S256 method.
///
/// PKCE replaces the client secret for apps that can't keep one: only who
/// started the sign-in knows the verifier, so a stolen code is useless.
String codeChallengeFor(String verifier) => base64Url
    .encode(sha256.convert(ascii.encode(verifier)).bytes)
    .replaceAll('=', '');

/// Tokens from the provider.
class OAuthTokens {
  /// Creates the tokens.
  const OAuthTokens({
    required this.accessToken,
    required this.expiresAt,
    this.refreshToken,
    this.idToken,
  });

  /// Parses a token endpoint response. [now] is when the request was sent.
  factory OAuthTokens.fromResponse(Map<String, Object?> json, DateTime now) {
    final access = json['access_token'];
    if (access is! String || access.isEmpty) {
      throw OAuthException(
        json['error_description'] as String? ??
            json['error'] as String? ??
            'Risposta senza access_token.',
      );
    }
    final seconds = switch (json['expires_in']) {
      final int n => n,
      final String s => int.tryParse(s) ?? 3600,
      _ => 3600,
    };
    return OAuthTokens(
      accessToken: access,
      expiresAt: now.add(Duration(seconds: seconds)),
      refreshToken: json['refresh_token'] as String?,
      idToken: json['id_token'] as String?,
    );
  }

  /// Goes in the XOAUTH2 login. Lives about an hour, only in memory.
  final String accessToken;

  /// When [accessToken] stops working.
  final DateTime expiresAt;

  /// Gets new access tokens. The only token saved, in the keychain.
  final String? refreshToken;

  /// Who signed in (OpenID Connect), only right after sign-in.
  final String? idToken;

  /// Still valid for at least [margin]: a token that expires during a
  /// command would fail halfway.
  bool isValid(DateTime now, {Duration margin = const Duration(minutes: 2)}) =>
      now.add(margin).isBefore(expiresAt);
}

/// The person who signed in, read from the OpenID Connect `id_token`.
typedef OAuthIdentity = ({String email, String? name});

/// Reads email and name from an `id_token`.
///
/// The signature is not checked: the token comes straight from the
/// provider's token endpoint over TLS, and it is only used to fill in the
/// address (the IMAP login fails anyway if it is wrong).
OAuthIdentity? identityFromIdToken(String? idToken) {
  final parts = idToken?.split('.');
  if (parts == null || parts.length != 3) return null;
  try {
    final payload =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
            as Map<String, Object?>;
    final email =
        payload['email'] as String? ?? payload['preferred_username'] as String?;
    if (email == null || !email.contains('@')) return null;
    return (email: email, name: payload['name'] as String?);
  } on FormatException {
    return null;
  }
}

/// A sign-in or token error, already readable.
class OAuthException implements Exception {
  /// Creates the error.
  const OAuthException(this.message);

  /// What went wrong, for the user.
  final String message;

  @override
  String toString() => 'OAuthException: $message';
}
