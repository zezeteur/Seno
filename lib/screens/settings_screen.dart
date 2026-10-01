import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../widgets/app_bottom_sheet.dart';
import 'package:provider/provider.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:country_flags/country_flags.dart';
import '../theme/app_colors.dart';
import '../providers/theme_provider.dart';
import '../providers/locale_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Widget _buildMenuItem({
    required dynamic icon,
    required String title,
    required String? subtitle,
    required Widget trailing,
    required VoidCallback? onTap,
    Color? iconColor,
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
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }

  /// Icône d'une option de choix (même style que les entrées du menu)
  Widget _choiceIcon(dynamic icon) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: HugeIcon(icon: icon, size: 20, color: AppColors.secondary),
      ),
    );
  }

  /// Drapeau d'une langue (rond, à la taille des pastilles d'icônes)
  Widget _choiceFlag(String countryCode) {
    return CountryFlag.fromCountryCode(
      countryCode,
      theme: const ImageTheme(width: 40, height: 40, shape: Circle()),
    );
  }

  String _getThemeModeText(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return context.tr('theme_system');
      case ThemeMode.light:
        return context.tr('theme_light');
      case ThemeMode.dark:
        return context.tr('theme_dark');
    }
  }

  void _showLanguageDialog(LocaleProvider localeProvider) {
    final current = Localizations.localeOf(context).languageCode;
    showChoiceSheet<String>(
      context: context,
      title: context.tr('choose_language'),
      options: [
        for (final code in ['fr', 'en']) (code, context.tr('lang_$code'))
      ],
      selected: current,
      leading: {'fr': _choiceFlag('FR'), 'en': _choiceFlag('GB')},
      onSelected: (value) => localeProvider.setLocale(Locale(value)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.viewPadding.top;
    final bottomPadding = mediaQuery.viewPadding.bottom;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final localeProvider = Provider.of<LocaleProvider>(context);

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
                          context.tr('settings'),
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
                  // Paramètres
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
                          icon: HugeIcons.strokeRoundedMoon,
                          title: context.tr('theme'),
                          subtitle: _getThemeModeText(themeProvider.themeMode),
                          trailing: Icon(
                            Icons.chevron_right,
                            color: AppColors.textSecondary,
                          ),
                          onTap: () {
                            showChoiceSheet<ThemeMode>(
                              context: context,
                              title: context.tr('choose_theme'),
                              options: [
                                (ThemeMode.system, context.tr('theme_system')),
                                (ThemeMode.light, context.tr('theme_light')),
                                (ThemeMode.dark, context.tr('theme_dark')),
                              ],
                              selected: themeProvider.themeMode,
                              leading: {
                                ThemeMode.system: _choiceIcon(
                                    HugeIcons.strokeRoundedSmartPhone01),
                                ThemeMode.light:
                                    _choiceIcon(HugeIcons.strokeRoundedSun03),
                                ThemeMode.dark:
                                    _choiceIcon(HugeIcons.strokeRoundedMoon02),
                              },
                              onSelected: themeProvider.setThemeMode,
                            );
                          },
                        ),
                        Divider(
                            height: 1,
                            color: AppColors.textSecondary.withOpacity(0.2)),
                        _buildMenuItem(
                          icon: HugeIcons.strokeRoundedGlobe,
                          title: context.tr('language'),
                          subtitle: context.tr(
                              Localizations.localeOf(context).languageCode ==
                                      'en'
                                  ? 'lang_en'
                                  : 'lang_fr'),
                          trailing: Icon(
                            Icons.chevron_right,
                            color: AppColors.textSecondary,
                          ),
                          onTap: () => _showLanguageDialog(localeProvider),
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
