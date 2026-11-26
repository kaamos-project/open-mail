import 'package:flutter/widgets.dart';
import 'package:kaamos_project_ui/kaamos_project_ui.dart';

import '../widgets/mail_icons.dart';

/// Mostrata quando il portachiavi di sistema non funziona (di solito Linux
/// senza GNOME Keyring o KWallet). L'app non parte: salvare le password in
/// chiaro non è un'opzione.
class KeychainMissingScreen extends StatelessWidget {
  /// Crea la schermata.
  const KeychainMissingScreen({super.key, required this.onRetry});

  /// Riprova dopo che l'utente ha installato il portachiavi.
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
                MailIconView(MailIcon.lock, size: 28, color: theme.ink),
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
