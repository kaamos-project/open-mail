import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaamos_mail/src/data/account_repository.dart';
import 'package:kaamos_mail/src/data/secret_store.dart';

import 'support/fakes.dart';

void main() {
  late Directory dir;
  late MemorySecretStore secrets;
  late AccountRepository repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kaamos_mail_test');
    secrets = MemorySecretStore();
    repo = AccountRepository(
      file: File('${dir.path}/accounts.json'),
      secrets: secrets,
    );
  });

  tearDown(() => dir.delete(recursive: true));

  test('no file means no accounts', () async {
    expect(await repo.load(), isEmpty);
  });

  test(
    'saves the account in the file and the password only in the keychain',
    () async {
      await repo.save(testAccount, 'segreta-123');
      final json = await File('${dir.path}/accounts.json').readAsString();
      expect(json, contains('alessio@esempio.org'));
      expect(json, isNot(contains('segreta-123')));
      expect(await repo.password(testAccount.id), 'segreta-123');

      final loaded = await repo.load();
      expect(loaded.single.email, testAccount.email);
      expect(loaded.single.imap.host, 'imap.esempio.org');
    },
  );

  test('removing also deletes the password', () async {
    await repo.save(testAccount, 'p');
    await repo.remove(testAccount.id);
    expect(await repo.load(), isEmpty);
    expect(await repo.password(testAccount.id), isNull);
  });
}
