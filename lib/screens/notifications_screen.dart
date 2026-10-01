import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shimmer/shimmer.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  Map<String, bool> _prefs = Map.of(SupabaseService.defaultNotifPrefs);
  bool _loading = true;

  bool get _pushNotificationsEnabled => _prefs['push']!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SupabaseService.getNotifPrefs();
      if (mounted) setState(() => _prefs = Map.of(prefs));
    } catch (_) {
      // Pas de réseau ni de cache : valeurs par défaut affichées
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Bascule optimiste : l'interface change tout de suite, retour arrière si échec
  Future<void> _toggle(String key, bool value) async {
    final previous = Map.of(_prefs);
    setState(() => _prefs = {..._prefs, key: value});
    try {
      await SupabaseService.updateNotifPrefs(_prefs);
    } catch (_) {
      if (!mounted) return;
      setState(() => _prefs = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('network_problem'))),
      );
    }
  }

  /// Les types sont inactifs tant que les notifications push sont coupées
  ValueChanged<bool>? _onChanged(String key) {
    if (_loading) return null;
    if (key != 'push' && !_pushNotificationsEnabled) return null;
    return (value) => _toggle(key, value);
  }

  /// Interrupteur, ou son shimmer tant que les préférences chargent
  Widget _buildSwitch(String key) {
    if (_loading) {
      return Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Container(
          width: 52,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
    }
    return Switch(
      value: _prefs[key]!,
      onChanged: _onChanged(key),
      activeColor: AppColors.secondary,
    );
  }

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
                          context.tr('notifications'),
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
                  // Notifications générales
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
                          icon: HugeIcons.strokeRoundedNotification01,
                          title: context.tr('push_notif'),
                          subtitle: context.tr('push_notif_sub'),
                          trailing: _buildSwitch('push'),
                          onTap: null,
                        ),
                      ],
                    ),
                  ),
                  // Types de notifications
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
                          icon: HugeIcons.strokeRoundedCoinsSwap,
                          title: context.tr('transactions'),
                          subtitle: context.tr('transactions_sub'),
                          trailing: _buildSwitch('transactions'),
                          onTap: null,
                        ),
                        Divider(
                            height: 1,
                            color: AppColors.textSecondary.withOpacity(0.2)),
                        _buildMenuItem(
                          icon: HugeIcons.strokeRoundedShoppingBag01,
                          title: context.tr('promotions'),
                          subtitle: context.tr('promotions_sub'),
                          trailing: _buildSwitch('promotions'),
                          onTap: null,
                        ),
                        Divider(
                            height: 1,
                            color: AppColors.textSecondary.withOpacity(0.2)),
                        _buildMenuItem(
                          icon: HugeIcons.strokeRoundedLock,
                          title: context.tr('security'),
                          subtitle: context.tr('security_alerts_sub'),
                          trailing: _buildSwitch('security'),
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
