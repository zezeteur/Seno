import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/toast_service.dart';
import '../l10n/app_strings.dart';
import '../widgets/app_bottom_sheet.dart';
import '../widgets/contact_support_sheet.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../theme/app_colors.dart';

class HelpSupportScreen extends StatefulWidget {
  /// N'affiche que l'option « Nous contacter » (ex. depuis l'écran de verrouillage)
  final bool contactOnly;

  /// Si fourni, ajoute l'option « Déconnexion » sous « Nous contacter »
  final Future<void> Function()? onSignOut;

  const HelpSupportScreen({
    super.key,
    this.contactOnly = false,
    this.onSignOut,
  });

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  /// Version installée (numéro de build inclus), lue au démarrage de l'écran
  String? _version;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() => _version = '${info.version} (${info.buildNumber})');
      }
    });
  }

  Future<void> _confirmSignOut() async {
    final confirm = await showConfirmSheet(
      context: context,
      title: context.tr('logout'),
      message: context.tr('logout_confirm'),
      confirmLabel: context.tr('logout'),
      destructive: true,
    );
    if (!confirm || !mounted) return;
    Navigator.of(context).pop();
    await widget.onSignOut!();
  }

  /// Copie « Seno v1.0.0 (1) » (utile pour le support)
  Future<void> _copyVersion() async {
    final version = _version;
    if (version == null) return;
    await Clipboard.setData(ClipboardData(text: 'Seno v$version'));
    HapticFeedback.lightImpact();
    if (mounted) ToastService.showInfo(context, context.tr('version_copied'));
  }

  Widget _buildMenuItem({
    required dynamic icon,
    required String title,
    required String? subtitle,
    required VoidCallback? onTap,
    Color? iconColor,
    bool showChevron = true,
  }) {
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: (iconColor ?? AppColors.secondary).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: HugeIcon(
              icon: icon,
              size: 20,
              color: iconColor ?? AppColors.secondary,
            ),
          ),
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
              )
            : null,
        trailing: showChevron
            ? Icon(
                Icons.chevron_right,
                color: AppColors.textSecondary,
              )
            : null,
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.viewPadding.top;
    final bottomPadding = mediaQuery.viewPadding.bottom;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          // SafeArea en haut
          SizedBox(height: topPadding),
          // Contenu scrollable
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Header avec bouton retour
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.arrow_back,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          context.tr('help_support'),
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                                fontSize: 28,
                              ),
                        ),
                      ],
                    ),
                  ),
                  // Contact
                  Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      children: [
                        _buildMenuItem(
                          icon: HugeIcons.strokeRoundedMessage01,
                          title: context.tr('contact_us'),
                          subtitle: context.tr('contact_us_sub'),
                          onTap: () => showContactSupportSheet(context),
                        ),
                      ],
                    ),
                  ),
                  // Déconnexion (séparée du contact)
                  if (widget.onSignOut != null)
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: _buildMenuItem(
                        icon: HugeIcons.strokeRoundedLogout01,
                        title: context.tr('logout'),
                        subtitle: null,
                        onTap: _confirmSignOut,
                      ),
                    ),
                  // Informations
                  if (!widget.contactOnly)
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        children: [
                          _buildMenuItem(
                            icon: HugeIcons.strokeRoundedFile01,
                            title: context.tr('terms'),
                            subtitle: null,
                            onTap: () {
                              // Fonctionnalité à venir
                            },
                          ),
                          Divider(
                              height: 1,
                              color: AppColors.textSecondary.withOpacity(0.2)),
                          _buildMenuItem(
                            icon: HugeIcons.strokeRoundedLock,
                            title: context.tr('privacy'),
                            subtitle: null,
                            onTap: () {
                              // Fonctionnalité à venir
                            },
                          ),
                          Divider(
                              height: 1,
                              color: AppColors.textSecondary.withOpacity(0.2)),
                          _buildMenuItem(
                            icon: HugeIcons.strokeRoundedHelpCircle,
                            title: context.tr('about'),
                            subtitle: _version != null ? 'Version $_version' : null,
                            showChevron: false,
                            onTap: _copyVersion,
                          ),
                        ],
                      ),
                    ),
                  // SafeArea en bas
                  SizedBox(height: bottomPadding),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
