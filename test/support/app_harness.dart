import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaamos_mail/src/app.dart';
import 'package:kaamos_mail/src/core/models.dart';
import 'package:kaamos_mail/src/data/mail_cache.dart';
import 'package:kaamos_mail/src/data/oauth_client.dart';
import 'package:kaamos_mail/src/data/secret_store.dart';

import 'fakes.dart';

/// The two layouts every UI feature is checked in (see docs/features.md).
enum Layout {
  /// A phone in portrait.
  phone(Size(390, 844)),

  /// A laptop window, above `desktopBreakpoint`.
  desktop(Size(1280, 800));

  const Layout(this.size);

  /// The window size.
  final Size size;
}

/// Runs [body] once per [Layout], as two separate tests.
void testBothLayouts(
  String description,
  Future<void> Function(WidgetTester tester, Layout layout) body,
) {
  for (final layout in Layout.values) {
    testWidgets('$description [${layout.name}]', (t) => body(t, layout));
  }
}

/// A bordered box around [finder]: the "card" look that reads as a pop-up.
Finder framedAround(Finder finder) => find.ancestor(
  of: finder,
  matching: find.byWidgetPredicate(
    (w) =>
        w is DecoratedBox &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).border != null,
  ),
);

/// Runs [body] in one [Layout] only, for what exists in one of them (the
/// phone's drawer, the desktop compose window).
void testLayout(
  Layout layout,
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets('$description [${layout.name}]', body);
}

/// The whole app on fakes: an in-memory server, cache, keychain and files.
class AppHarness {
  /// Creates the harness. The Inbox starts with messages 1..[inbox];
  /// [keychain] false is a Linux without Secret Service.
  AppHarness({int inbox = 5, bool keychain = true})
    : server = FakeMailService()..seed('INBOX', inbox),
      cache = MailCache.inMemory(),
      secrets = MemorySecretStore(available: keychain),
      files = FakeFileActions() {
    accounts = MemoryAccountRepository(secrets);
  }

  /// The fake IMAP/SMTP server, shared by every account.
  final FakeMailService server;

  /// The cache.
  final MailCache cache;

  /// The keychain.
  final MemorySecretStore secrets;

  /// Attachments and links.
  final FakeFileActions files;

  /// Saved accounts.
  late final MemoryAccountRepository accounts;

  /// Saves [account] before the app starts.
  Future<void> addAccount([Account account = testAccount]) =>
      accounts.save(account, 'p');

  /// Starts the app in [layout] and waits for the first sync.
  Future<void> pump(
    WidgetTester tester, {
    Layout layout = Layout.desktop,
    OAuthSignIn? oauth,
  }) async {
    tester.view
      ..physicalSize = layout.size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(cache.close);
    await tester.pumpWidget(
      KaamosMailApp(
        accounts: accounts,
        secrets: secrets,
        cache: cache,
        services: FakeMailServiceFactory(server),
        files: files,
        htmlBody: (context, doc, onLink) => const Text('HTML'),
        oauth: oauth,
      ),
    );
    await tester.pumpAndSettle();
  }
}

/// Taps the first widget with the semantics [label] and settles.
Future<void> tapLabel(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel(label).first);
  await tester.pumpAndSettle();
}

/// Taps the first widget showing [text] and settles.
Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).first);
  await tester.pumpAndSettle();
}
