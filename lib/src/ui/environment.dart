import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../core/mail_service.dart';
import '../core/models.dart';
import '../data/account_repository.dart';
import '../data/mail_cache.dart';
import '../data/secret_store.dart';

/// Draws the (already cleaned) HTML body of a message.
///
/// In the real app it is a WebView; in tests and where there is no WebView
/// (Linux, phase 2) a substitute is used.
typedef HtmlBodyBuilder =
    Widget Function(
      BuildContext context,
      String sanitizedDocument,
      ValueChanged<Uri> onOpenLink,
    );

/// File actions that depend on the operating system.
abstract interface class FileActions {
  /// Lets the user pick files to attach. Empty list if they cancel.
  Future<List<OutgoingAttachment>> pickAttachments();

  /// Saves an attachment to a temporary folder and opens it with the system
  /// app.
  Future<void> openAttachment(String fileName, Uint8List bytes);

  /// Opens a link in the system browser.
  Future<void> openLink(Uri uri);
}

/// All of the app's services, made available to widgets.
///
/// An `InheritedWidget` instead of globals: tests build an environment with a
/// fake server and an in-memory cache, without touching the screens' code.
class MailEnvironment extends InheritedWidget {
  /// Creates the environment.
  const MailEnvironment({
    super.key,
    required this.accounts,
    required this.secrets,
    required this.cache,
    required this.services,
    required this.files,
    required this.htmlBody,
    required super.child,
  });

  /// Saved accounts.
  final AccountRepository accounts;

  /// Keychain.
  final SecretStore secrets;

  /// SQLite cache.
  final MailCache cache;

  /// Creates the server connections.
  final MailServiceFactory services;

  /// Files and links.
  final FileActions files;

  /// Draws HTML mail.
  final HtmlBodyBuilder htmlBody;

  /// The nearest environment.
  static MailEnvironment of(BuildContext context) {
    final env = context.dependOnInheritedWidgetOfExactType<MailEnvironment>();
    assert(env != null, 'Nessun MailEnvironment sopra questo widget');
    return env!;
  }

  @override
  bool updateShouldNotify(MailEnvironment old) =>
      accounts != old.accounts ||
      cache != old.cache ||
      services != old.services ||
      htmlBody != old.htmlBody;
}
