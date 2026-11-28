import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaamos_mail/src/core/settings.dart';
import 'package:kaamos_mail/src/data/settings_store.dart';

void main() {
  test('JSON round trip', () {
    const s = AppSettings(
      remoteImages: RemoteImages.always,
      layout: MailLayout.list,
      compose: ComposeMode.page,
    );
    expect(AppSettings.fromJson(s.toJson()), s);
  });

  test('unknown or missing values fall back to the defaults', () {
    final s = AppSettings.fromJson({
      'version': 9,
      'remoteImages': 'sometimes',
      'layout': 42,
    });
    expect(s, const AppSettings());
  });

  group('FileSettingsStore', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('kaamos_settings'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('no file: defaults', () async {
      final store = FileSettingsStore(File('${dir.path}/settings.json'));
      expect(await store.load(), const AppSettings());
    });

    test('saves and loads back, with no temporary file left', () async {
      final file = File('${dir.path}/settings.json');
      final store = FileSettingsStore(file);
      const s = AppSettings(layout: MailLayout.list);
      await store.save(s);
      expect(await FileSettingsStore(file).load(), s);
      expect(
        jsonDecode(file.readAsStringSync()),
        containsPair('layout', 'list'),
      );
      expect(dir.listSync().map((e) => e.path.split('/').last), [
        'settings.json',
      ]);
    });

    test('a broken file: defaults, not a crash', () async {
      final file = File('${dir.path}/settings.json')
        ..writeAsStringSync('{not json');
      expect(await FileSettingsStore(file).load(), const AppSettings());
    });
  });
}
