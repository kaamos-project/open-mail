import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../core/mail_service.dart';
import '../core/models.dart';
import '../data/account_repository.dart';
import '../data/mail_cache.dart';
import '../data/secret_store.dart';

/// Disegna il corpo HTML (già ripulito) di un messaggio.
///
/// Nell'app vera è una WebView; nei test e dove la WebView non c'è
/// (Linux, fase 2) si usa un sostituto.
typedef HtmlBodyBuilder =
    Widget Function(
      BuildContext context,
      String sanitizedDocument,
      ValueChanged<Uri> onOpenLink,
    );

/// Le azioni sui file che dipendono dal sistema operativo.
abstract interface class FileActions {
  /// Fa scegliere dei file da allegare. Lista vuota se l'utente annulla.
  Future<List<OutgoingAttachment>> pickAttachments();

  /// Salva un allegato in una cartella temporanea e lo apre con l'app di
  /// sistema.
  Future<void> openAttachment(String fileName, Uint8List bytes);

  /// Apre un link nel browser di sistema.
  Future<void> openLink(Uri uri);
}

/// Tutti i servizi dell'app, messi a disposizione dei widget.
///
/// Un `InheritedWidget` invece di variabili globali: nei test si costruisce
/// un ambiente con server finto e cache in memoria, senza toccare il codice
/// delle schermate.
class MailEnvironment extends InheritedWidget {
  /// Crea l'ambiente.
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

  /// Account salvati.
  final AccountRepository accounts;

  /// Portachiavi.
  final SecretStore secrets;

  /// Cache SQLite.
  final MailCache cache;

  /// Crea le connessioni ai server.
  final MailServiceFactory services;

  /// File e link.
  final FileActions files;

  /// Disegna le mail HTML.
  final HtmlBodyBuilder htmlBody;

  /// L'ambiente più vicino.
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
