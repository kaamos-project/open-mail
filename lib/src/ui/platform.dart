import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:kaamos_project_ui/kaamos_project_ui.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';
import '../core/oauth.dart';
import '../core/text_utils.dart';
import '../data/oauth_client.dart';
import 'environment.dart';

/// The WebView exists only on these platforms (`flutter_inappwebview` doesn't
/// support Linux: see the decision in the MVP document).
bool get webViewSupported =>
    !kIsWeb &&
    (Platform.isWindows ||
        Platform.isMacOS ||
        Platform.isIOS ||
        Platform.isAndroid);

/// The HTML body builder for the real app.
Widget platformHtmlBody(
  BuildContext context,
  String document,
  ValueChanged<Uri> onOpenLink,
) {
  if (!webViewSupported) return UnsupportedHtmlBody(document: document);
  return SafeHtmlWebView(document: document, onOpenLink: onOpenLink);
}

/// Google and Microsoft sign-in for this platform.
///
/// - Desktop: loopback redirect, which needs a local server (allowed on
///   macOS by the `network.server` entitlement).
/// - iOS: `ASWebAuthenticationSession`, in `ios/Runner/AppDelegate.swift`.
/// - Android: a Custom Tab, in `MainActivity.kt`.
OAuthSignIn? platformOAuthSignIn() {
  if (kIsWeb) return null;
  if (Platform.isIOS || Platform.isAndroid) {
    return AppSessionOAuthSignIn(
      present: _presentAuthSession,
      target: platformOAuthTarget,
    );
  }
  if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    return null;
  }
  return LoopbackOAuthSignIn(
    openBrowser: (url) async {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw const OAuthException('Non riesco ad aprire il browser.');
      }
    },
  );
}

/// The OAuth2 client of this build, matching [platformOAuthSignIn].
OAuthTarget get platformOAuthTarget => kIsWeb
    ? OAuthTarget.desktop
    : Platform.isIOS
    ? OAuthTarget.ios
    : Platform.isAndroid
    ? OAuthTarget.android
    : OAuthTarget.desktop;

const _oauthChannel = MethodChannel('dev.kaamos_project.mail/oauth');

Future<Uri> _presentAuthSession(Uri url, String callbackScheme) async {
  try {
    final result = await _oauthChannel.invokeMethod<String>('authenticate', {
      'url': url.toString(),
      'callbackScheme': callbackScheme,
    });
    if (result == null) throw const OAuthException('Accesso annullato.');
    return Uri.parse(result);
  } on PlatformException catch (e) {
    throw OAuthException(
      e.code == 'CANCELED'
          ? 'Accesso annullato.'
          : 'Accesso non riuscito: ${e.message ?? e.code}',
    );
  }
}

/// A locked-down WebView for showing HTML mail.
///
/// The three protections agreed with Alessio:
/// 1. JavaScript off ([InAppWebViewSettings.javaScriptEnabled]);
/// 2. HTML already cleaned by `HtmlSanitizer`;
/// 3. no network: the CSP in the page blocks remote resources, plus
///    `blockNetworkLoads` on Android, and on every platform each navigation is
///    cancelled and the link opened in the system browser.
class SafeHtmlWebView extends StatelessWidget {
  /// Creates the WebView.
  const SafeHtmlWebView({
    super.key,
    required this.document,
    required this.onOpenLink,
  });

  /// Already cleaned page.
  final String document;

  /// Called when the user taps a link.
  final ValueChanged<Uri> onOpenLink;

  @override
  Widget build(BuildContext context) {
    // Keyed on the document: if it changes (e.g. "Load images") the WebView is
    // recreated instead of reusing the one with the old page.
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
        // The initial page load (about:blank / data:) goes through.
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

/// In place of the WebView where there is none (Linux, until phase 2): the text
/// extracted from the HTML, with a line explaining why the layout is missing.
class UnsupportedHtmlBody extends StatelessWidget {
  /// Creates the placeholder for [document] (already cleaned).
  const UnsupportedHtmlBody({super.key, required this.document});

  /// The cleaned page.
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

/// [FileActions] backed by the system plugins.
class PlatformFileActions implements FileActions {
  /// Creates the actions.
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

/// MIME type from the extension, for outgoing attachments.
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
