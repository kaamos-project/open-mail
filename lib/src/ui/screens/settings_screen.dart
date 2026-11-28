import 'package:flutter/widgets.dart';
import 'package:kaamos_project_ui/kaamos_project_ui.dart';

import '../../core/settings.dart';
import '../../state/settings_controller.dart';
import '../widgets/common.dart';
import '../widgets/mail_icons.dart';

/// The app's settings: one page, the same on the phone and on desktop,
/// centred and without a card (like the add-account page).
///
/// Every choice applies at once and is saved on the device.
class SettingsScreen extends StatelessWidget {
  /// Creates the page.
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.onBack,
  });

  /// The settings to show and change.
  final SettingsController settings;

  /// Leaves the page.
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final s = settings.value;
        void set(AppSettings next) => settings.update(next);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  MailIconButton(
                    icon: MailIcon.back,
                    label: 'Indietro',
                    size: 44,
                    onPressed: onBack,
                  ),
                  const SizedBox(width: 4),
                  Semantics(
                    header: true,
                    child: Text(
                      'Impostazioni',
                      style: KaamosTypography.headingSm.copyWith(
                        color: theme.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Hairline(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 32,
                      children: [
                        _Choice<RemoteImages>(
                          title: 'Immagini remote',
                          description: switch (s.remoteImages) {
                            RemoteImages.ask =>
                              'Le blocco e ti chiedo se caricarle: chi ti '
                                  'scrive non sa quando e da dove leggi.',
                            RemoteImages.always =>
                              'Le carico subito. Chi ti scrive (e molte '
                                  'newsletter) può sapere quando e da dove '
                                  'leggi.',
                          },
                          value: s.remoteImages,
                          options: const {
                            RemoteImages.ask: 'Chiedi ogni volta',
                            RemoteImages.always: 'Carica sempre',
                          },
                          onChanged: (v) => set(s.copyWith(remoteImages: v)),
                        ),
                        _Choice<MailLayout>(
                          title: 'Disposizione su desktop',
                          description: switch (s.layout) {
                            MailLayout.split =>
                              'La lista dei messaggi e il messaggio aperto '
                                  'uno accanto all’altro.',
                            MailLayout.list =>
                              'Solo la lista, come Gmail classico: il '
                                  'messaggio aperto prende tutta l’area, '
                                  '"Indietro" torna alla lista.',
                          },
                          value: s.layout,
                          options: const {
                            MailLayout.split: 'Lista e lettura affiancate',
                            MailLayout.list: 'Solo lista',
                          },
                          onChanged: (v) => set(s.copyWith(layout: v)),
                        ),
                        _Choice<ComposeMode>(
                          title: 'Scrittura su desktop',
                          description: switch (s.compose) {
                            ComposeMode.window =>
                              'Una finestra in basso a destra, come Gmail: '
                                  'puoi leggere altre mail mentre scrivi.',
                            ComposeMode.page =>
                              'Una pagina che prende l’area della posta: '
                                  '"Chiudi" torna alla lista.',
                          },
                          value: s.compose,
                          options: const {
                            ComposeMode.window: 'Finestra flottante',
                            ComposeMode.page: 'Pagina',
                          },
                          onChanged: (v) => set(s.copyWith(compose: v)),
                        ),
                        Text(
                          'Sul telefono la lista, il messaggio e la scrittura '
                          'sono sempre pagine. Le impostazioni restano su '
                          'questo dispositivo.',
                          style: KaamosTypography.captionMd.copyWith(
                            color: theme.mute,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One setting: a title, two or more options as pill tabs (a segmented
/// control: every option visible, one tap to change), and a line that
/// explains the chosen one.
class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.description,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final String description;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: KaamosTypography.bodySmStrong.copyWith(color: theme.ink),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final MapEntry(:key, value: label) in options.entries)
              KaamosPillTab(
                label: label,
                selected: key == value,
                onPressed: () => onChanged(key),
              ),
          ],
        ),
        Text(
          description,
          style: KaamosTypography.bodySm.copyWith(color: theme.mute),
        ),
      ],
    );
  }
}
