import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import '../core/settings.dart';

/// Where the settings are saved.
abstract interface class SettingsStore {
  /// Reads the settings; the defaults if there are none yet.
  Future<AppSettings> load();

  /// Saves [settings].
  Future<void> save(AppSettings settings);
}

/// `settings.json` in the app's data folder, next to `accounts.json`.
///
/// A plain file rather than `shared_preferences`: no extra plugin, the same
/// format and folder on every system, and you can open it to see what is
/// saved. There are no secrets in it.
class FileSettingsStore implements SettingsStore {
  /// Creates the store for [file].
  FileSettingsStore(this.file);

  /// The JSON file.
  final File file;

  @override
  Future<AppSettings> load() async {
    if (!file.existsSync()) return const AppSettings();
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is Map<String, Object?>) return AppSettings.fromJson(json);
    } on FormatException catch (e, st) {
      // A damaged file must not stop the app: start from the defaults, and
      // the next change overwrites it.
      developer.log(
        'settings.json is not valid JSON',
        name: 'kaamos_mail',
        error: e,
        stackTrace: st,
      );
    }
    return const AppSettings();
  }

  @override
  Future<void> save(AppSettings settings) async {
    await file.parent.create(recursive: true);
    // Atomic write, as for accounts.json: a temporary file, then rename.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
      flush: true,
    );
    await tmp.rename(file.path);
  }
}

/// Settings kept in memory: for tests.
class MemorySettingsStore implements SettingsStore {
  /// Creates the store with [initial] already saved.
  MemorySettingsStore([this.saved = const AppSettings()]);

  /// What was saved last.
  AppSettings saved;

  @override
  Future<AppSettings> load() async => saved;

  @override
  Future<void> save(AppSettings settings) async => saved = settings;
}
