import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:kaamos_project_ui/kaamos_project_ui.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';
import '../core/text_utils.dart';
import 'environment.dart';

/// La WebView esiste solo su queste piattaforme (`flutter_inappwebview`
/// non supporta Linux: vedi la decisione nel documento dell'MVP).
bool get webViewSupported =>
    !kIsWeb &&
    (Platform.isWindows ||
        Platform.isMacOS ||
        Platform.isIOS ||
        Platform.isAndroid);

/// Il costruttore del corpo HTML per l'app vera.
Widget platformHtmlBody(
  BuildContext context,
  String document,
  ValueChanged<Uri> onOpenLink,
) {
  if (!webViewSupported) return UnsupportedHtmlBody(document: document);
  return SafeHtmlWebView(document: document, onOpenLink: onOpenLink);
}

/// Una WebView chiusa a chiave per mostrare mail HTML.
///
/// Le tre protezioni decise con Alessio:
/// 1. JavaScript spento ([InAppWebViewSettings.javaScriptEnabled]);
/// 2. HTML già ripulito da `HtmlSanitizer`;
/// 3. niente rete: la CSP nella pagina blocca le risorse remote, e in più su
///    Android `blockNetworkLoads` e su tutte le piattaforme ogni navigazione
///    viene annullata e il link aperto nel browser di sistema.
class SafeHtmlWebView extends StatelessWidget {
  /// Crea la WebView.
  const SafeHtmlWebView({
    super.key,
    required this.document,
    required this.onOpenLink,
  });

  /// Pagina già ripulita.
  final String document;

  /// Chiamato quando l'utente tocca un link.
  final ValueChanged<Uri> onOpenLink;

  @override
  Widget build(BuildContext context) {
    // La chiave sul documento: se cambia (es. "Carica immagini") si ricrea
    // la WebView invece di riusare quella con la pagina vecchia.
    return InAppWebView(
      key: ValueKey(document.hashCode),
      initialData: InAppWebViewInitialData(data: document),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: false,
        javaScriptCanOpenWindowsAutomatically: false,
        useShouldOverrideUrlLoading: true,
        incognito: true,
        cacheEnabled: false,
        thirdPartyCookiesEnabled: false,
        allowFileAccess: false,
        allowContentAccess: false,
        transparentBackground: false,
        supportZoom: true,
        isInspectable: kDebugMode,
      ),
      shouldOverrideUrlLoading: (controller, action) async {
        final url = action.request.url;
        final scheme = url?.scheme ?? '';
        // Il caricamento iniziale della pagina (about:blank / data:) passa.
        if (url == null || scheme == 'about' || scheme == 'data') {
          return NavigationActionPolicy.ALLOW;
        }
        if (scheme == 'http' || scheme == 'https' || scheme == 'mailto') {
          onOpenLink(Uri.parse(url.toString()));
        }
        return NavigationActionPolicy.CANCEL;
      },
    );
  }
}

/// Al posto della WebView dove non c'è (Linux, fino alla fase 2): il testo
/// ricavato dall'HTML, con una riga che spiega perché manca la grafica.
class UnsupportedHtmlBody extends StatelessWidget {
  /// Crea il segnaposto per [document] (già ripulito).
  const UnsupportedHtmlBody({super.key, required this.document});

  /// La pagina ripulita.
  final String document;

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Questa mail è in HTML: su questa piattaforma per ora la mostro '
            'come testo semplice.',
            style: KaamosTypography.captionMd.copyWith(color: theme.mute),
          ),
          const SizedBox(height: 12),
          Text(
            htmlToText(document).trim(),
            style: KaamosTypography.bodySm.copyWith(color: theme.body),
          ),
        ],
      ),
    );
  }
}

/// [FileActions] con i plugin di sistema.
class PlatformFileActions implements FileActions {
  /// Crea le azioni.
  const PlatformFileActions();

  @override
  Future<List<OutgoingAttachment>> pickAttachments() async {
    final files = await FilePicker.pickFiles();
    final result = <OutgoingAttachment>[];
    for (final f in files) {
      final bytes = await f.xFile.readAsBytes();
      result.add(
        OutgoingAttachment(
          fileName: f.name,
          mimeType: guessMimeType(f.name),
          bytes: bytes,
        ),
      );
    }
    return result;
  }

  @override
  Future<void> openAttachment(String fileName, Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File('${dir.path}${Platform.pathSeparator}$safeName');
    await file.writeAsBytes(bytes, flush: true);
    await OpenFilex.open(file.path);
  }

  @override
  Future<void> openLink(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Tipo MIME dall'estensione, per gli allegati in uscita.
String guessMimeType(String fileName) {
  final ext = fileName.contains('.')
      ? fileName.split('.').last.toLowerCase()
      : '';
  return switch (ext) {
    'pdf' => 'application/pdf',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'txt' => 'text/plain',
    'csv' => 'text/csv',
    'zip' => 'application/zip',
    'gpx' => 'application/gpx+xml',
    'json' => 'application/json',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'odt' => 'application/vnd.oasis.opendocument.text',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ods' => 'application/vnd.oasis.opendocument.spreadsheet',
    _ => 'application/octet-stream',
  };
}
