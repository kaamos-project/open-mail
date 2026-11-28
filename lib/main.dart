import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'src/app.dart';
import 'src/data/account_repository.dart';
import 'src/data/imap_mail_service.dart';
import 'src/data/mail_cache.dart';
import 'src/data/secret_store.dart';
import 'src/data/settings_store.dart';
import 'src/state/settings_controller.dart';
import 'src/ui/platform.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The app's data folder (e.g. %APPDATA% on Windows, Application Support on
  // macOS/iOS): it holds only the account list (without passwords) and the mail
  // cache.
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  final sep = Platform.pathSeparator;

  final secrets = SystemSecretStore();
  final accounts = AccountRepository(
    file: File('${dir.path}${sep}accounts.json'),
    secrets: secrets,
  );
  final cache = MailCache.open('${dir.path}${sep}mail.db');
  final settings = SettingsController(
    FileSettingsStore(File('${dir.path}${sep}settings.json')),
  );

  runApp(
    KaamosMailApp(
      accounts: accounts,
      secrets: secrets,
      cache: cache,
      services: ImapMailServiceFactory(
        onRefreshTokenChanged: accounts.updatePassword,
        oauthTarget: platformOAuthTarget,
      ),
      files: const PlatformFileActions(),
      htmlBody: platformHtmlBody,
      settings: settings,
      oauth: platformOAuthSignIn(),
    ),
  );
}
