import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where secrets (the account passwords) live.
///
/// It is an interface because tests have no real keychain: they use
/// [MemorySecretStore].
abstract interface class SecretStore {
  /// `true` if the system keychain works. On Linux without GNOME Keyring or
  /// KWallet it answers `false` and the app doesn't start (Alessio's choice:
  /// better not to start than to store passwords in plain text).
  Future<bool> isAvailable();

  /// Reads a secret, `null` if missing.
  Future<String?> read(String key);

  /// Saves or replaces a secret.
  Future<void> write(String key, String value);

  /// Deletes a secret.
  Future<void> delete(String key);
}

/// The system keychain via `flutter_secure_storage`: DPAPI-encrypted file on
/// Windows, Keychain on macOS and iOS, Keystore on Android, Secret Service on
/// Linux.
class SystemSecretStore implements SecretStore {
  /// Creates the keychain link.
  SystemSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _probeKey = 'kaamos_mail.probe';

  @override
  Future<bool> isAvailable() async {
    // There is no "is there a keychain?" API: the only reliable test is
    // writing, reading back and deleting a value.
    try {
      await _storage.write(key: _probeKey, value: 'ok');
      final value = await _storage.read(key: _probeKey);
      await _storage.delete(key: _probeKey);
      return value == 'ok';
    } on Object {
      return false;
    }
  }

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// In-memory secrets, for tests only.
class MemorySecretStore implements SecretStore {
  /// Creates a fake keychain. With [available] false it simulates Linux without
  /// Secret Service.
  MemorySecretStore({this.available = true});

  /// Answer of [isAvailable].
  bool available;

  /// The saved values, visible to tests.
  final Map<String, String> values = {};

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
