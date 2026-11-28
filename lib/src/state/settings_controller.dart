import 'package:flutter/foundation.dart';

import '../core/settings.dart';
import '../data/settings_store.dart';

/// The app's settings, for the screens to read and listen to.
class SettingsController extends ChangeNotifier {
  /// Creates the controller on [store]; call [load] before using it.
  SettingsController(this.store);

  /// Where they are saved.
  final SettingsStore store;

  AppSettings _value = const AppSettings();

  /// The current settings.
  AppSettings get value => _value;

  /// Reads the saved settings.
  Future<void> load() async {
    _value = await store.load();
    notifyListeners();
  }

  /// Applies [settings] at once, then saves them.
  Future<void> update(AppSettings settings) async {
    if (settings == _value) return;
    _value = settings;
    notifyListeners();
    await store.save(settings);
  }
}
