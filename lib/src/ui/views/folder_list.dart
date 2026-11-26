import 'package:flutter/widgets.dart';
import 'package:kaamos_project_ui/kaamos_project_ui.dart';

import '../../core/models.dart';
import '../../core/text_utils.dart';
import '../../state/mailbox_controller.dart';
import '../widgets/common.dart';
import '../widgets/mail_icons.dart';

/// L'icona di una cartella in base al ruolo.
MailIcon folderIcon(FolderRole role) => switch (role) {
  FolderRole.inbox => MailIcon.inbox,
  FolderRole.sent => MailIcon.send,
  FolderRole.drafts => MailIcon.file,
  FolderRole.archive => MailIcon.archive,
  FolderRole.trash => MailIcon.trash,
  FolderRole.junk => MailIcon.junk,
  FolderRole.other => MailIcon.folder,
};

/// La colonna delle cartelle: bottone "Scrivi", cartelle, account in fondo.
///
/// Su desktop è la prima colonna; su mobile è una pagina a sé.
class FolderList extends StatelessWidget {
  /// Crea la colonna.
  const FolderList({
    super.key,
    required this.controller,
    required this.onCompose,
    required this.onSelected,
    required this.onAccount,
  });

  /// Lo stato della casella.
  final MailboxController controller;

  /// "Scrivi".
  final VoidCallback onCompose;

  /// Chiamato dopo aver scelto una cartella (su mobile chiude la pagina).
  final ValueChanged<Folder> onSelected;

  /// Apre le impostazioni dell'account.
  final VoidCallback onAccount;

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final folders = controller.folders.isEmpty
            ? [controller.current]
            : controller.folders;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: KaamosButton(
                onPressed: onCompose,
                leading: MailIconView(
                  MailIcon.edit,
                  size: 16,
                  color: theme.canvas,
                ),
                child: const Text('Scrivi'),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final folder in folders)
                    _FolderRow(
                      folder: folder,
                      selected:
                          folder.path == controller.current.path &&
                          controller.searchQuery == null,
                      onPressed: () {
                        onSelected(folder);
                        controller.selectFolder(folder);
                      },
                    ),
                ],
              ),
            ),
            const Hairline(),
            KaamosPressable(
              onPressed: onAccount,
              semanticLabel: 'Account ${controller.account.email}',
              builder: (context, states) => KaamosFocusRing(
                visible: states.contains(WidgetState.focused),
                color: theme.focusRing,
                borderRadius: KaamosRadius.md,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      MailAvatar(
                        label: controller.account.displayName,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              controller.account.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: KaamosTypography.bodySmStrong.copyWith(
                                color: theme.ink,
                              ),
                            ),
                            Text(
                              controller.account.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: KaamosTypography.captionSm.copyWith(
                                color: theme.mute,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.folder,
    required this.selected,
    required this.onPressed,
  });

  final Folder folder;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    final label = folderLabel(folder);
    return Semantics(
      selected: selected,
      child: KaamosPressable(
        onPressed: onPressed,
        semanticLabel: label,
        builder: (context, states) {
          final hovered = states.contains(WidgetState.hovered);
          return KaamosFocusRing(
            visible: states.contains(WidgetState.focused),
            color: theme.focusRing,
            borderRadius: KaamosRadius.md,
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: selected || hovered ? theme.surfaceElevated : null,
                borderRadius: const BorderRadius.all(
                  Radius.circular(KaamosRadius.md),
                ),
              ),
              child: Row(
                children: [
                  MailIconView(
                    folderIcon(folder.role),
                    size: 18,
                    color: selected ? theme.ink : theme.mute,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          (selected
                                  ? KaamosTypography.bodySmStrong
                                  : KaamosTypography.bodySm)
                              .copyWith(
                                color: selected ? theme.ink : theme.body,
                              ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
