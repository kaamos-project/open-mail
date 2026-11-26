import 'dart:convert';
import 'dart:io';

import '../core/models.dart';
import 'secret_store.dart';

/// Salva gli account: la configurazione in un file JSON, la password nel
/// portachiavi.
///
/// Perché due posti? Il file serve per ricordare server e porte e si può
/// copiare o fare il backup senza rischi; la password invece non deve mai
/// finire su disco in chiaro.
class AccountRepository {
  /// Crea il repository. [file] è `accounts.json` nella cartella dati
  /// dell'app.
  AccountRepository({required this.file, required this.secrets});

  /// Il file JSON con gli account.
  final File file;

  /// Il portachiavi.
  final SecretStore secrets;

  static String _passwordKey(String accountId) =>
      'kaamos_mail.account.$accountId.password';

  /// Tutti gli account salvati (nell'MVP al massimo uno).
  Future<List<Account>> load() async {
    if (!file.existsSync()) return const [];
    final raw = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    final list = (raw['accounts'] as List<Object?>? ?? const [])
        .cast<Map<String, Object?>>();
    return [for (final json in list) Account.fromJson(json)];
  }

  /// Salva [account] (lo sostituisce se esiste già) e la sua [password].
  Future<void> save(Account account, String password) async {
    // Prima la password: se il portachiavi fallisce, non resta un account
    // senza credenziali.
    await secrets.write(_passwordKey(account.id), password);
    final accounts = [
      for (final a in await load())
        if (a.id != account.id) a,
      account,
    ];
    await _write(accounts);
  }

  /// La password di un account.
  Future<String?> password(String accountId) =>
      secrets.read(_passwordKey(accountId));

  /// Toglie l'account e la sua password. La cache la cancella chi chiama.
  Future<void> remove(String accountId) async {
    await secrets.delete(_passwordKey(accountId));
    await _write([
      for (final a in await load())
        if (a.id != accountId) a,
    ]);
  }

  Future<void> _write(List<Account> accounts) async {
    await file.parent.create(recursive: true);
    // Scrittura atomica: prima un file temporaneo, poi rename. Se l'app
    // si chiude a metà, il file vecchio resta integro.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'accounts': [for (final a in accounts) a.toJson()],
      }),
      flush: true,
    );
    await tmp.rename(file.path);
  }
}
