import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../theme/app_colors.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _pushNotificationsEnabled = true;
  bool _emailNotificationsEnabled = false;
  bool _transactionNotificationsEnabled = true;
  bool _promotionNotificationsEnabled = false;
  bool _securityNotificationsEnabled = true;

  Widget _buildMenuItem({
    required dynamic icon,
    required String title,
    required String? subtitle,
    required Widget trailing,
    required VoidCallback? onTap,
    Color? iconColor,
  }) {
    return ListTile(
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
                          'Notifications',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                                fontSize: 28,
                              ),
                        ),
                      ],
                    ),
                  ),
                  // Notifications générales
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      children: [
                        _buildMenuItem(
                          icon: HugeIcons.strokeRoundedNotification01,
                          title: 'Notifications push',
                          subtitle: 'Recevoir des notifications sur votre appareil',
                          trailing: Switch(
                            value: _pushNotificationsEnabled,
                            onChanged: (value) {
                              setState(() {
                                _pushNotificationsEnabled = value;
                              });
                            },
                            activeColor: AppColors.secondary,
                          ),
                          onTap: null,
                        ),
                        Divider(height: 1, color: AppColors.textSecondary.withOpacity(0.2)),
                        _buildMenuItem(
                          icon: HugeIcons.strokeRoundedMail01,
                          title: 'Notifications email',
                          subtitle: 'Recevoir des notifications par email',
                          trailing: Switch(
                            value: _emailNotificationsEnabled,
                            onChanged: (value) {
                              setState(() {
                                _emailNotificationsEnabled = value;
                              });
                            },
                            activeColor: AppColors.secondary,
                          ),
                          onTap: null,
                        ),
                      ],
                    ),
                  ),
                  // Types de notifications
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      children: [
                        _buildMenuItem(
                          icon: HugeIcons.strokeRoundedCoinsSwap,
                          title: 'Transactions',
                          subtitle: 'Notifications pour vos transactions',
                          trailing: Switch(
                            value: _transactionNotificationsEnabled,
                            onChanged: (value) {
                              setState(() {
                                _transactionNotificationsEnabled = value;
                              });
                            },
                            activeColor: AppColors.secondary,
                          ),
                          onTap: null,
                        ),
                        Divider(height: 1, color: AppColors.textSecondary.withOpacity(0.2)),
                        _buildMenuItem(
                          icon: HugeIcons.strokeRoundedShoppingBag01,
                          title: 'Promotions',
                          subtitle: 'Offres et promotions spéciales',
                          trailing: Switch(
                            value: _promotionNotificationsEnabled,
                            onChanged: (value) {
                              setState(() {
                                _promotionNotificationsEnabled = value;
                              });
                            },
                            activeColor: AppColors.secondary,
                          ),
                          onTap: null,
                        ),
                        Divider(height: 1, color: AppColors.textSecondary.withOpacity(0.2)),
                        _buildMenuItem(
                          icon: HugeIcons.strokeRoundedLock,
                          title: 'Sécurité',
                          subtitle: 'Alertes de sécurité importantes',
                          trailing: Switch(
                            value: _securityNotificationsEnabled,
                            onChanged: (value) {
                              setState(() {
                                _securityNotificationsEnabled = value;
                              });
                            },
                            activeColor: AppColors.secondary,
                          ),
                          onTap: null,
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

