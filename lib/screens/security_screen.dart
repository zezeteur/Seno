import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import 'package:hugeicons/hugeicons.dart';
import '../theme/app_colors.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  bool _biometricEnabled = false;

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
                          context.tr('security'),
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
                  // Authentification
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
                          icon: HugeIcons.strokeRoundedAiScan,
                          title: context.tr('biometric'),
                          subtitle: context.tr('biometric_sub'),
                          trailing: Switch(
                            value: _biometricEnabled,
                            onChanged: (value) {
                              setState(() {
                                _biometricEnabled = value;
                              });
                            },
                            activeColor: AppColors.secondary,
                          ),
                          onTap: null,
                        ),
                      ],
                    ),
                  ),
                  // Mot de passe
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
                          icon: HugeIcons.strokeRoundedLock,
                          title: context.tr('change_password'),
                          subtitle: null,
                          trailing: Icon(
                            Icons.chevron_right,
                            color: AppColors.textSecondary,
                          ),
                          onTap: () {
                            // Fonctionnalité à venir
                          },
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
