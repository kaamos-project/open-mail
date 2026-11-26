import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'src/app.dart';
import 'src/data/account_repository.dart';
import 'src/data/imap_mail_service.dart';
import 'src/data/mail_cache.dart';
import 'src/data/secret_store.dart';
import 'src/ui/platform.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // La cartella dati dell'app (es. %APPDATA% su Windows, Application
  // Support su macOS/iOS): qui stanno solo la lista degli account (senza
  // password) e la cache delle mail.
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  final sep = Platform.pathSeparator;

  final secrets = SystemSecretStore();
  final accounts = AccountRepository(
    file: File('${dir.path}${sep}accounts.json'),
    secrets: secrets,
  );
  final cache = MailCache.open('${dir.path}${sep}mail.db');

  runApp(
    KaamosMailApp(
      accounts: accounts,
      secrets: secrets,
      cache: cache,
      services: const ImapMailServiceFactory(),
      files: const PlatformFileActions(),
      htmlBody: platformHtmlBody,
    ),
  );
}
