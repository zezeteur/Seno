import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_strings.dart';
import '../services/supabase_service.dart';
import '../utils/toast_service.dart';
import 'app_bottom_sheet.dart';

/// Modale « Nous contacter » : WhatsApp, téléphone, e-mail (coordonnées du backend)
Future<void> showContactSupportSheet(BuildContext context) async {
  final SupportContacts contacts;
  try {
    contacts = await SupabaseService.getSupportContacts();
  } catch (_) {
    if (context.mounted) {
      ToastService.showError(context, context.tr('service_unavailable'));
    }
    return;
  }
  if (!context.mounted) return;
  if (contacts.isEmpty) {
    ToastService.showInfo(context, context.tr('contact_unavailable'));
    return;
  }

  final options = <(dynamic, String, String, Uri)>[
    if (contacts.whatsapp != null)
      (
        HugeIcons.strokeRoundedWhatsapp,
        context.tr('contact_whatsapp'),
        contacts.whatsapp!,
        // wa.me attend le numéro sans « + » ni espaces
        Uri.parse(
            'https://wa.me/${contacts.whatsapp!.replaceAll(RegExp(r'\D'), '')}'),
      ),
    if (contacts.phone != null)
      (
        HugeIcons.strokeRoundedCall,
        context.tr('contact_phone'),
        contacts.phone!,
        Uri(scheme: 'tel', path: contacts.phone!.replaceAll(' ', '')),
      ),
    if (contacts.email != null)
      (
        HugeIcons.strokeRoundedMail01,
        context.tr('contact_email'),
        contacts.email!,
        Uri(scheme: 'mailto', path: contacts.email),
      ),
  ];

  await showAppBottomSheet<void>(
    context: context,
    title: context.tr('contact_us'),
    builder: (sheetContext) {
      final colorScheme = Theme.of(sheetContext).colorScheme;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (icon, label, value, uri) in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  leading: HugeIcon(icon: icon, color: colorScheme.onSurface),
                  title: Text(label),
                  subtitle: Text(value),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    final opened = await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    ).catchError((_) => false);
                    if (!opened && context.mounted) {
                      ToastService.showError(
                          context, context.tr('contact_open_failed'));
                    }
                  },
                ),
              ),
            ),
        ],
      );
    },
  );
}
