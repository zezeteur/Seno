import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';

/// Modale standard de l'app : sort du bas, coins arrondis, poignée
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  String? title,
  String? message,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          24,
          12,
          24,
          MediaQuery.of(sheetContext).viewPadding.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Poignée
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (title != null)
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ],
            if (title != null || message != null) const SizedBox(height: 24),
            builder(sheetContext),
          ],
        ),
      );
    },
  );
}

/// Modale de confirmation : renvoie true si l'utilisateur confirme
Future<bool> showConfirmSheet({
  required BuildContext context,
  required String title,
  String? message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showAppBottomSheet<bool>(
    context: context,
    title: title,
    message: message,
    builder: (sheetContext) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: destructive ? AppColors.error : AppColors.primary,
            foregroundColor:
                destructive ? Colors.white : AppColors.textOnPrimary,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: () => Navigator.of(sheetContext).pop(true),
          child: Text(confirmLabel),
        ),
        const SizedBox(height: 8),
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
          onPressed: () => Navigator.of(sheetContext).pop(false),
          child: Text(context.tr('cancel')),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Modale de choix unique (liste d'options avec coche)
Future<void> showChoiceSheet<T>({
  required BuildContext context,
  required String title,
  required List<(T, String)> options,
  required T selected,
  required ValueChanged<T> onSelected,
}) {
  return showAppBottomSheet<void>(
    context: context,
    title: title,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (value, label) in options)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(label),
            trailing: value == selected
                ? Icon(Icons.check,
                    color: Theme.of(sheetContext).colorScheme.onSurface)
                : null,
            onTap: () {
              onSelected(value);
              Navigator.of(sheetContext).pop();
            },
          ),
      ],
    ),
  );
}
