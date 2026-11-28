import 'package:flutter_test/flutter_test.dart';
import 'package:kaamos_mail/src/core/oauth.dart';
import 'package:kaamos_mail/src/data/oauth_client.dart';

import '../support/app_harness.dart';

void main() {
  testBothLayouts('without a keychain the app explains and can retry', (
    tester,
    layout,
  ) async {
    final app = AppHarness(keychain: false);
    await app.pump(tester, layout: layout);
    expect(find.text('Serve il portachiavi di sistema'), findsOneWidget);

    app.secrets.available = true;
    await tapText(tester, 'Riprova');
    expect(find.text('Aggiungi un account'), findsOneWidget);
  });

  testBothLayouts('first start opens the add-account screen', (
    tester,
    layout,
  ) async {
    final app = AppHarness();
    await app.pump(tester, layout: layout);
    expect(find.text('Aggiungi un account'), findsOneWidget);
    expect(find.text('Annulla'), findsNothing, reason: 'nowhere to go back');
    expect(
      framedAround(find.text('Aggiungi un account')),
      findsNothing,
      reason: 'on the page itself, not in a card',
    );
    expect(
      find.text('Accedi con Google'),
      findsNothing,
      reason: 'no sign-in on this platform',
    );
  });

  testBothLayouts('sign-in buttons say when a build has no client ID', (
    tester,
    layout,
  ) async {
    final app = AppHarness();
    await app.pump(tester, layout: layout, oauth: _NoSignIn());
    expect(find.text('Accedi con Google'), findsOneWidget);
    expect(find.text('Accedi con Microsoft'), findsOneWidget);
    // Tests run without --dart-define, so neither provider is configured.
    expect(find.textContaining('non configurato'), findsOneWidget);
  });
}

class _NoSignIn implements OAuthSignIn {
  @override
  OAuthTarget get target => OAuthTarget.desktop;

  @override
  Future<OAuthSignInResult> signIn(OAuthConfig config) =>
      throw const OAuthException('not in tests');
}
