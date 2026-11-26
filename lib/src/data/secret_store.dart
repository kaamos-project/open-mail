import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Dove vivono i segreti (le password degli account).
///
/// È un'interfaccia perché nei test non c'è un portachiavi vero: si usa
/// [MemorySecretStore].
abstract interface class SecretStore {
  /// `true` se il portachiavi di sistema funziona. Su Linux senza
  /// GNOME Keyring o KWallet risponde `false`, e l'app non parte (scelta di
  /// Alessio: meglio non avviarsi che salvare password in chiaro).
  Future<bool> isAvailable();

  /// Legge un segreto, `null` se non c'è.
  Future<String?> read(String key);

  /// Salva o sostituisce un segreto.
  Future<void> write(String key, String value);

  /// Cancella un segreto.
  Future<void> delete(String key);
}

/// Il portachiavi di sistema tramite `flutter_secure_storage`:
/// Gestione credenziali su Windows, Keychain su macOS e iOS, Keystore su
/// Android, Secret Service su Linux.
class SystemSecretStore implements SecretStore {
  /// Crea il collegamento al portachiavi.
  SystemSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _probeKey = 'kaamos_mail.probe';

  @override
  Future<bool> isAvailable() async {
    // Non c'è un'API "esiste il portachiavi?": l'unico test affidabile è
    // provare a scrivere, rileggere e cancellare un valore.
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

/// Segreti in memoria, solo per i test.
class MemorySecretStore implements SecretStore {
  /// Crea un portachiavi finto. Con [available] falso simula Linux senza
  /// Secret Service.
  MemorySecretStore({this.available = true});

  /// Risposta di [isAvailable].
  bool available;

  /// I valori salvati, visibili ai test.
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
