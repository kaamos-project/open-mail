import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/oauth.dart';

/// Sends a form (`application/x-www-form-urlencoded`) and returns status
/// code and body. A function instead of a client, so tests can fake it.
typedef FormPost =
    Future<(int status, String body)> Function(
      Uri url,
      Map<String, String> form,
    );

/// [FormPost] with `dart:io`: no extra HTTP package for two requests.
Future<(int, String)> ioFormPost(Uri url, Map<String, String> form) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final request = await client.postUrl(url);
    request.headers
      ..contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      )
      ..set(HttpHeaders.acceptHeader, 'application/json');
    request.write(Uri(queryParameters: form).query);
    final response = await request.close().timeout(const Duration(seconds: 30));
    final body = await response.transform(utf8.decoder).join();
    return (response.statusCode, body);
  } finally {
    client.close(force: true);
  }
}

/// Talks to the providers' token endpoints.
class OAuthClient {
  /// Creates the client. [post] and [clock] are replaced in tests.
  OAuthClient({FormPost? post, DateTime Function()? clock})
    : _post = post ?? ioFormPost,
      _clock = clock ?? DateTime.now;

  final FormPost _post;
  final DateTime Function() _clock;

  /// Exchanges the authorization [code] for tokens (the last step of
  /// sign-in).
  Future<OAuthTokens> exchangeCode(
    OAuthConfig config, {
    required String code,
    required String codeVerifier,
    required Uri redirectUri,
  }) => _request(
    config,
    config.codeExchangeForm(
      code: code,
      codeVerifier: codeVerifier,
      redirectUri: redirectUri,
    ),
  );

  /// A new access token from [refreshToken].
  ///
  /// The answer may carry a new refresh token too (Microsoft rotates them):
  /// the caller must save it in place of the old one.
  Future<OAuthTokens> refresh(OAuthConfig config, String refreshToken) =>
      _request(config, config.refreshForm(refreshToken));

  Future<OAuthTokens> _request(
    OAuthConfig config,
    Map<String, String> form,
  ) async {
    final now = _clock();
    final (status, body) = await _post(config.tokenEndpoint, form);
    Map<String, Object?> json;
    try {
      json = jsonDecode(body) as Map<String, Object?>;
    } on FormatException {
      throw OAuthException('${config.label} ha risposto in modo inatteso.');
    }
    if (status != 200) {
      // invalid_grant: the refresh token was revoked, expired or the
      // password changed. Only signing in again fixes it.
      if (json['error'] == 'invalid_grant') {
        throw OAuthException(
          'L\'accesso a ${config.label} è scaduto o è stato revocato: '
          'rimuovi l\'account e aggiungilo di nuovo.',
        );
      }
      throw OAuthException(
        json['error_description'] as String? ??
            '${config.label}: errore ${json['error'] ?? status}.',
      );
    }
    return OAuthTokens.fromResponse(json, now);
  }
}

/// The result of signing in: who it is and the tokens.
typedef OAuthSignInResult = ({OAuthIdentity identity, OAuthTokens tokens});

/// Signs in with a provider in the browser.
abstract interface class OAuthSignIn {
  /// Opens the provider's page and waits for the user to finish.
  Future<OAuthSignInResult> signIn(OAuthConfig config);
}

/// Sign-in for desktop apps (RFC 8252, "loopback redirect").
///
/// The app opens a tiny HTTP server on the loopback address with a random
/// port and gives the provider `http://<loopback>:<port>/` as the return
/// address ([OAuthConfig.loopbackHost]: `127.0.0.1` or `localhost`).
/// The system browser signs in (with its saved passwords and 2FA, which the
/// app never sees) and then sends the code back to that server. Nothing
/// outside this computer can reach a 127.0.0.1 address.
class LoopbackOAuthSignIn implements OAuthSignIn {
  /// Creates the sign-in. [openBrowser] opens a URL in the system browser.
  LoopbackOAuthSignIn({
    required this.openBrowser,
    OAuthClient? client,
    this.timeout = const Duration(minutes: 5),
  }) : client = client ?? OAuthClient();

  /// Opens the sign-in page.
  final Future<void> Function(Uri url) openBrowser;

  /// Exchanges the code.
  final OAuthClient client;

  /// How long to wait for the user.
  final Duration timeout;

  @override
  Future<OAuthSignInResult> signIn(OAuthConfig config) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    // "localhost" may resolve to ::1 first: listen there too, same port.
    HttpServer? server6;
    if (config.loopbackHost == 'localhost') {
      try {
        server6 = await HttpServer.bind(
          InternetAddress.loopbackIPv6,
          server.port,
          v6Only: true,
        );
      } on SocketException {
        server6 = null;
      }
    }
    final requests = StreamController<HttpRequest>();
    final subs = [
      for (final s in [server, ?server6])
        s.listen(requests.add, onError: requests.addError),
    ];
    try {
      final redirect = Uri.parse(
        'http://${config.loopbackHost}:${server.port}/',
      );
      final verifier = createCodeVerifier();
      // state: ties the answer to this attempt, so another page can't
      // inject a code of its own.
      final state = createCodeVerifier().substring(0, 32);
      // Listen before opening the browser, so a fast answer isn't missed.
      // The result is caught right away (an error is a value here), so a
      // failure while the browser is still opening isn't left unhandled.
      final answer = _waitForCode(requests.stream, state, config)
          .timeout(
            timeout,
            onTimeout: () => throw const OAuthException(
              'Tempo scaduto: riprova ad accedere.',
            ),
          )
          .then<Object>((code) => code, onError: (Object e) => e);
      await openBrowser(
        config.authorizationUrl(
          redirectUri: redirect,
          state: state,
          codeChallenge: codeChallengeFor(verifier),
        ),
      );
      final code = await answer;
      if (code is! String) throw code;
      final tokens = await client.exchangeCode(
        config,
        code: code,
        codeVerifier: verifier,
        redirectUri: redirect,
      );
      if (tokens.refreshToken == null) {
        throw OAuthException(
          '${config.label} non ha dato un token per restare collegati.',
        );
      }
      final identity = identityFromIdToken(tokens.idToken);
      if (identity == null) {
        throw OAuthException(
          '${config.label} non ha detto qual è il tuo indirizzo.',
        );
      }
      return (identity: identity, tokens: tokens);
    } finally {
      for (final sub in subs) {
        await sub.cancel();
      }
      await requests.close();
      await server.close(force: true);
      await server6?.close(force: true);
    }
  }

  Future<String> _waitForCode(
    Stream<HttpRequest> server,
    String state,
    OAuthConfig config,
  ) async {
    await for (final request in server) {
      final params = request.uri.queryParameters;
      // Browsers also ask for /favicon.ico: ignore anything else.
      if (request.uri.path != '/' ||
          (!params.containsKey('code') && !params.containsKey('error'))) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        continue;
      }
      final ok = params['state'] == state && params['code'] != null;
      await _answer(request, ok);
      if (params['state'] != state) {
        throw const OAuthException('Risposta non valida: riprova.');
      }
      final error = params['error'];
      if (error != null) {
        throw OAuthException(
          error == 'access_denied'
              ? 'Accesso annullato.'
              : '${config.label}: ${params['error_description'] ?? error}',
        );
      }
      return params['code']!;
    }
    throw const OAuthException('Accesso interrotto.');
  }

  Future<void> _answer(HttpRequest request, bool ok) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write(
        '<!doctype html><meta charset="utf-8"><title>Kaamos Mail</title>'
        '<body style="font-family:system-ui,sans-serif;padding:48px">'
        '<h1>${ok ? 'Fatto' : 'Accesso non riuscito'}</h1>'
        '<p>Puoi chiudere questa finestra e tornare a Kaamos Mail.</p>',
      );
    await request.response.close();
  }
}
