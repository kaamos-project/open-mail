import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaamos_mail/src/core/models.dart';
import 'package:kaamos_mail/src/core/oauth.dart';
import 'package:kaamos_mail/src/data/imap_mail_service.dart';
import 'package:kaamos_mail/src/data/oauth_client.dart';

import 'support/fakes.dart';

/// A JWT with [claims] as payload (unsigned: only the payload is read).
String fakeIdToken(Map<String, Object?> claims) {
  String part(Object o) => base64Url.encode(utf8.encode(jsonEncode(o)));
  return '${part({'alg': 'none'})}.${part(claims)}.sig';
}

const gmailAccount = Account(
  id: 'g1',
  displayName: 'Alessio',
  email: 'alessio@gmail.com',
  username: 'alessio@gmail.com',
  imap: ServerConfig(
    host: 'imap.gmail.com',
    port: 993,
    security: ConnectionSecurity.tls,
  ),
  smtp: ServerConfig(
    host: 'smtp.gmail.com',
    port: 465,
    security: ConnectionSecurity.tls,
  ),
  oauth: OAuthProvider.google,
);

void main() {
  final google = oauthConfig(OAuthProvider.google);
  final microsoft = oauthConfig(OAuthProvider.microsoft);

  group('PKCE', () {
    test('S256 challenge is base64url(sha256) without padding', () {
      // Expected value computed separately with Python's hashlib.
      expect(
        codeChallengeFor('dBjftJeZ4CVP-mJ92K1fUWYvKqpHOQOgiaugWPdPYnE'),
        'oUlyT-TJUL80A595nEzilIMXn8cjIKIdAXRKl0j8oZM',
      );
    });

    test('verifier is 64 unreserved characters and random', () {
      final a = createCodeVerifier();
      expect(a, hasLength(64));
      expect(RegExp(r'^[A-Za-z0-9\-_]+$').hasMatch(a), isTrue);
      expect(createCodeVerifier(), isNot(a));
    });
  });

  test('authorization URL carries PKCE, state and provider extras', () {
    final url = google.authorizationUrl(
      redirectUri: 'http://127.0.0.1:5000/',
      state: 'st',
      codeChallenge: 'ch',
    );
    final q = url.queryParameters;
    expect(url.host, 'accounts.google.com');
    expect(q['response_type'], 'code');
    expect(q['code_challenge'], 'ch');
    expect(q['code_challenge_method'], 'S256');
    expect(q['state'], 'st');
    expect(q['redirect_uri'], 'http://127.0.0.1:5000/');
    expect(q['scope'], contains('https://mail.google.com/'));
    expect(q['access_type'], 'offline');
    expect(q.containsKey('login_hint'), isFalse);
  });

  test('Microsoft asks for IMAP, SMTP and offline access, no secret', () {
    expect(
      microsoft.scopes,
      containsAll([
        'https://outlook.office.com/IMAP.AccessAsUser.All',
        'https://outlook.office.com/SMTP.Send',
        'offline_access',
      ]),
    );
    expect(microsoft.refreshForm('r').containsKey('client_secret'), isFalse);
    expect(microsoft.smtp.security, ConnectionSecurity.startTls);
  });

  group('tokens', () {
    final now = DateTime.utc(2026, 11, 26, 12);

    test('parses a token response', () {
      final t = OAuthTokens.fromResponse({
        'access_token': 'a',
        'expires_in': 3599,
        'refresh_token': 'r',
      }, now);
      expect(t.accessToken, 'a');
      expect(t.refreshToken, 'r');
      expect(t.expiresAt, now.add(const Duration(seconds: 3599)));
      expect(t.isValid(now), isTrue);
      expect(t.isValid(now.add(const Duration(minutes: 58))), isFalse);
    });

    test('a response without access_token is an error', () {
      expect(
        () => OAuthTokens.fromResponse({'error': 'bad'}, now),
        throwsA(isA<OAuthException>()),
      );
    });
  });

  group('id_token', () {
    test('reads email and name', () {
      final id = identityFromIdToken(
        fakeIdToken({'email': 'a@gmail.com', 'name': 'Alessio'}),
      );
      expect(id?.email, 'a@gmail.com');
      expect(id?.name, 'Alessio');
    });

    test('Microsoft: falls back to preferred_username', () {
      final id = identityFromIdToken(
        fakeIdToken({'preferred_username': 'a@outlook.com'}),
      );
      expect(id?.email, 'a@outlook.com');
    });

    test('garbage = null', () {
      expect(identityFromIdToken('abc'), isNull);
      expect(identityFromIdToken(null), isNull);
      expect(identityFromIdToken(fakeIdToken({'sub': '1'})), isNull);
    });
  });

  group('OAuthClient', () {
    test('refresh sends the refresh form', () async {
      Map<String, String>? sent;
      final client = OAuthClient(
        post: (url, form) async {
          sent = form;
          return (200, jsonEncode({'access_token': 'a', 'expires_in': 60}));
        },
      );
      final t = await client.refresh(google, 'r1');
      expect(t.accessToken, 'a');
      expect(sent?['grant_type'], 'refresh_token');
      expect(sent?['refresh_token'], 'r1');
    });

    test('invalid_grant tells you to sign in again', () async {
      final client = OAuthClient(
        post: (_, _) async => (400, jsonEncode({'error': 'invalid_grant'})),
      );
      await expectLater(
        client.refresh(microsoft, 'r'),
        throwsA(
          isA<OAuthException>().having(
            (e) => e.message,
            'message',
            contains('aggiungilo di nuovo'),
          ),
        ),
      );
    });

    test('a non-JSON answer is a readable error', () async {
      final client = OAuthClient(post: (_, _) async => (502, '<html>'));
      await expectLater(
        client.refresh(google, 'r'),
        throwsA(isA<OAuthException>()),
      );
    });
  });

  group('credentials for IMAP and SMTP', () {
    test('a password account uses the password as is', () async {
      final f = ImapMailServiceFactory();
      expect(await f.credentialFor(testAccount, 'pwd')(), 'pwd');
    });

    test('OAuth: one refresh, token reused, rotation saved', () async {
      var calls = 0;
      final saved = <String>[];
      final f = ImapMailServiceFactory(
        oauth: OAuthClient(
          post: (_, form) async {
            calls++;
            return (
              200,
              jsonEncode({
                'access_token': 'access$calls',
                'expires_in': 3600,
                'refresh_token': 'r2',
              }),
            );
          },
        ),
        onRefreshTokenChanged: (id, token) async => saved.add('$id:$token'),
      );
      final credential = f.credentialFor(gmailAccount, 'r1');
      final both = await Future.wait([credential(), credential()]);
      expect(both, ['access1', 'access1']);
      expect(await credential(), 'access1');
      expect(calls, 1);
      expect(saved, ['g1:r2']);
    });
  });

  group('loopback sign-in', () {
    LoopbackOAuthSignIn signInThatAnswers(
      Map<String, String> Function(Map<String, String> auth) answer,
    ) => LoopbackOAuthSignIn(
      client: OAuthClient(
        post: (_, form) async => (
          200,
          jsonEncode({
            'access_token': 'a',
            'refresh_token': 'r-${form['code']}',
            'id_token': fakeIdToken({'email': 'a@gmail.com'}),
          }),
        ),
      ),
      // Plays the browser: goes straight back to the redirect URI.
      openBrowser: (url) async {
        final q = url.queryParameters;
        final back = Uri.parse(
          q['redirect_uri']!,
        ).replace(queryParameters: answer(q));
        final http = HttpClient();
        final request = await http.getUrl(back);
        await (await request.close()).drain<void>();
        http.close();
      },
    );

    test('gets the code and exchanges it', () async {
      final sign = signInThatAnswers(
        (q) => {'code': 'c1', 'state': q['state']!},
      );
      final result = await sign.signIn(google);
      expect(result.identity.email, 'a@gmail.com');
      expect(result.tokens.refreshToken, 'r-c1');
    });

    test('Microsoft comes back on localhost', () async {
      final sign = signInThatAnswers(
        (q) => {'code': 'c2', 'state': q['state']!},
      );
      final result = await sign.signIn(microsoft);
      expect(result.tokens.refreshToken, 'r-c2');
    });

    test('a wrong state is refused', () async {
      final sign = signInThatAnswers((_) => {'code': 'c1', 'state': 'evil'});
      await expectLater(sign.signIn(google), throwsA(isA<OAuthException>()));
    });

    test('cancelling in the browser says so', () async {
      final sign = signInThatAnswers(
        (q) => {'error': 'access_denied', 'state': q['state']!},
      );
      await expectLater(
        sign.signIn(google),
        throwsA(
          isA<OAuthException>().having(
            (e) => e.message,
            'message',
            'Accesso annullato.',
          ),
        ),
      );
    });
  });

  group('iOS sign-in sheet', () {
    final msIos = oauthConfig(OAuthProvider.microsoft, target: OAuthTarget.ios);

    AppSessionOAuthSignIn sheet(
      Map<String, String> Function(Map<String, String> auth) answer,
    ) => AppSessionOAuthSignIn(
      client: OAuthClient(
        post: (_, form) async {
          expect(form['redirect_uri'], 'msauth.$iosBundleId://auth');
          return (
            200,
            jsonEncode({
              'access_token': 'a',
              'refresh_token': 'r-${form['code']}',
              'id_token': fakeIdToken({'preferred_username': 'a@outlook.com'}),
            }),
          );
        },
      ),
      present: (url, scheme) async {
        expect(scheme, 'msauth.$iosBundleId');
        return Uri.parse(
          'msauth.$iosBundleId://auth',
        ).replace(queryParameters: answer(url.queryParameters));
      },
    );

    test('catches the redirect and exchanges the code', () async {
      final result = await sheet(
        (q) => {'code': 'c3', 'state': q['state']!},
      ).signIn(msIos);
      expect(result.identity.email, 'a@outlook.com');
      expect(result.tokens.refreshToken, 'r-c3');
    });

    test('a wrong state is refused', () async {
      await expectLater(
        sheet((_) => {'code': 'c3', 'state': 'evil'}).signIn(msIos),
        throwsA(isA<OAuthException>()),
      );
    });

    test('Google iOS: reversed client ID, no secret', () {
      expect(
        googleIosRedirect('123-abc.apps.googleusercontent.com'),
        'com.googleusercontent.apps.123-abc:/oauth2redirect',
      );
      expect(googleIosRedirect('not-a-google-id'), isNull);
      final g = oauthConfig(OAuthProvider.google, target: OAuthTarget.ios);
      expect(g.clientSecret, isEmpty);
    });
  });

  test('an OAuth account survives the accounts file', () {
    final back = Account.fromJson(gmailAccount.toJson());
    expect(back.oauth, OAuthProvider.google);
    expect(Account.fromJson(testAccount.toJson()).oauth, isNull);
  });
}
