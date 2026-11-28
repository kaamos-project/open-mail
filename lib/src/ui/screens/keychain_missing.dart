import 'package:flutter/widgets.dart';
import 'package:kaamos_project_ui/kaamos_project_ui.dart';


/// Shown when the system keychain doesn't work (usually Linux without GNOME
/// Keyring or KWallet). The app doesn't start: storing passwords in plain text
/// is not an option.
class KeychainMissingScreen extends StatelessWidget {
  /// Creates the screen.
  const KeychainMissingScreen({super.key, required this.onRetry});

  /// Retries after the user has installed a keychain.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: KaamosCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KaamosIcon(KaamosIcons.lock, size: 28, color: theme.ink),
                const SizedBox(height: 16),
                Semantics(
                  header: true,
                  child: Text(
                    'Serve il portachiavi di sistema',
                    style: KaamosTypography.headingMd.copyWith(
                      color: theme.ink,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Kaamos Mail salva le password solo nel portachiavi del '
                  'sistema operativo, mai in un file. Su questo computer il '
                  'portachiavi non risponde.',
                  style: KaamosTypography.bodySm.copyWith(color: theme.body),
                ),
                const SizedBox(height: 8),
                Text(
                  'Su Linux installa e avvia GNOME Keyring o KWallet '
                  '(servizio Secret Service), poi premi Riprova.',
                  style: KaamosTypography.bodySm.copyWith(color: theme.mute),
                ),
                const SizedBox(height: 20),
                KaamosButton(onPressed: onRetry, child: const Text('Riprova')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
