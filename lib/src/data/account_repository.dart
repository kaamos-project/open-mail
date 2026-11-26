import 'dart:convert';
import 'dart:io';

import '../core/models.dart';
import 'secret_store.dart';

/// Saves the accounts: the configuration in a JSON file, the password in the
/// keychain.
///
/// Why two places? The file remembers servers and ports and can be copied or
/// backed up safely; the password must never end up on disk in plain text.
class AccountRepository {
  /// Creates the repository. [file] is `accounts.json` in the app's data
  /// folder.
  AccountRepository({required this.file, required this.secrets});

  /// The JSON file with the accounts.
  final File file;

  /// The keychain.
  final SecretStore secrets;

  static String _passwordKey(String accountId) =>
      'kaamos_mail.account.$accountId.password';

  /// All saved accounts.
  Future<List<Account>> load() async {
    if (!file.existsSync()) return const [];
    final raw = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    final list = (raw['accounts'] as List<Object?>? ?? const [])
        .cast<Map<String, Object?>>();
    return [for (final json in list) Account.fromJson(json)];
  }

  /// Saves [account] (replacing it if it already exists) and its [password].
  Future<void> save(Account account, String password) async {
    // Password first: if the keychain fails, no account is left without
    // credentials.
    await secrets.write(_passwordKey(account.id), password);
    final accounts = [
      for (final a in await load())
        if (a.id != account.id) a,
      account,
    ];
    await _write(accounts);
  }

  /// The password of an account (the refresh token for OAuth2 accounts).
  Future<String?> password(String accountId) =>
      secrets.read(_passwordKey(accountId));

  /// Replaces the keychain secret, e.g. a rotated refresh token.
  Future<void> updatePassword(String accountId, String secret) =>
      secrets.write(_passwordKey(accountId), secret);

  /// Removes the account and its password. The caller deletes the cache.
  Future<void> remove(String accountId) async {
    await secrets.delete(_passwordKey(accountId));
    await _write([
      for (final a in await load())
        if (a.id != accountId) a,
    ]);
  }

  Future<void> _write(List<Account> accounts) async {
    await file.parent.create(recursive: true);
    // Atomic write: a temporary file first, then rename. If the app quits
    // halfway, the old file stays intact.
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
