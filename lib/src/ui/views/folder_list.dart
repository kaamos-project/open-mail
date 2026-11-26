import 'package:flutter/widgets.dart';
import 'package:kaamos_project_ui/kaamos_project_ui.dart';

import '../../core/models.dart';
import '../../core/text_utils.dart';
import '../../state/mailbox_controller.dart';
import '../widgets/common.dart';
import '../widgets/mail_icons.dart';

/// A folder's icon based on its role.
MailIcon folderIcon(FolderRole role) => switch (role) {
  FolderRole.inbox => MailIcon.inbox,
  FolderRole.sent => MailIcon.send,
  FolderRole.drafts => MailIcon.file,
  FolderRole.archive => MailIcon.archive,
  FolderRole.trash => MailIcon.trash,
  FolderRole.junk => MailIcon.junk,
  FolderRole.other => MailIcon.folder,
};

/// The folder column: "Scrivi" (compose) button, folders, account at the
/// bottom.
///
/// On desktop it is the first column; on mobile it is a page of its own.
class FolderList extends StatelessWidget {
  /// Creates the column.
  const FolderList({
    super.key,
    required this.controller,
    required this.onCompose,
    required this.onSelected,
    required this.onAccount,
    this.onUnified,
    this.unified = false,
  });

  /// "Tutte le caselle" (all inboxes). `null` with a single account.
  final VoidCallback? onUnified;

  /// The unified Inbox is the one shown.
  final bool unified;

  /// The mailbox state.
  final MailboxController controller;

  /// "Scrivi" (compose).
  final VoidCallback onCompose;

  /// Called after choosing a folder (on mobile it closes the page).
  final ValueChanged<Folder> onSelected;

  /// Opens the account settings.
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
                  if (onUnified != null) ...[
                    _FolderRow(
                      label: 'Tutte le caselle',
                      icon: MailIcon.inbox,
                      selected: unified,
                      onPressed: onUnified!,
                    ),
                    const SizedBox(height: 8),
                  ],
                  for (final folder in folders)
                    _FolderRow(
                      label: folderLabel(folder),
                      icon: folderIcon(folder.role),
                      selected:
                          !unified &&
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
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final MailIcon icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
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
                    icon,
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
