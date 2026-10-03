import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../widgets/app_bottom_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:lottie/lottie.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import '../utils/toast_service.dart';
import '../widgets/user_avatar.dart';
import 'settings_screen.dart';
import 'security_screen.dart';
import 'notifications_screen.dart';
import 'help_support_screen.dart';
import 'profile_screen.dart';
import 'account_limits_screen.dart';
import 'merchant_profile_screen.dart';
import 'merchant_request_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final supabase = Supabase.instance.client;
  final _lottieKey = UniqueKey();

  String? _pseudo;
  String? _nom;
  String? _prenoms;
  String? _avatarUrl;

  /// Boutique de l'utilisateur ; null s'il n'est pas marchand
  MerchantInfo? _merchant;

  @override
  void initState() {
    super.initState();
    // Boutique en cache affichée tout de suite, puis version fraîche
    _merchant = SupabaseService.peekMyMerchant();
    _loadProfile();
    _loadMerchant();
    SupabaseService.merchantRevision.addListener(_loadMerchant);
    SupabaseService.profileRevision.addListener(_loadProfile);
  }

  @override
  void dispose() {
    SupabaseService.profileRevision.removeListener(_loadProfile);
    SupabaseService.merchantRevision.removeListener(_loadMerchant);
    super.dispose();
  }

  /// Profil (table profiles, mis en cache) : photo, prénoms, pseudo
  Future<void> _loadProfile() async {
    try {
      final profile = await SupabaseService.getLockProfile();
      if (!mounted) return;
      setState(() {
        _pseudo = profile.pseudo;
        _nom = profile.nom;
        _prenoms = profile.prenoms;
        _avatarUrl = profile.avatarUrl;
      });
    } catch (_) {
      // Hors ligne sans cache : libellé par défaut
    }
  }

  String _getUserName() {
    // « Nom Prénoms », avec ce qui est renseigné
    final name = [_nom, _prenoms]
        .map((v) => v?.trim() ?? '')
        .where((v) => v.isNotEmpty)
        .join(' ');
    return name.isNotEmpty ? name : context.tr('user');
  }

  Future<void> _loadMerchant() async {
    try {
      final merchant = await SupabaseService.getMyMerchant();
      if (mounted) setState(() => _merchant = merchant);
    } catch (_) {
      // Hors ligne : la carte « Devenir un marchand » reste affichée
    }
  }

  /// Formulaire marchand, sauf si le compte marchand existe déjà
  Future<void> _handleBecomeMerchant() async {
    await _loadMerchant();
    if (!mounted) return;
    if (_merchant != null) {
      ToastService.showInfo(context, context.tr('merchant_approved'));
      return;
    }
    // Les frais de transaction sont à la charge du marchand
    final accepted = await showConfirmSheet(
      context: context,
      title: context.tr('merchant_fees_title'),
      message: context.tr('merchant_fees_message'),
      confirmLabel: context.tr('merchant_fees_accept'),
    );
    if (!accepted || !mounted) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const MerchantRequestScreen()),
    );
    if (created == true) _loadMerchant();
  }

  /// Carte de la boutique, à la place de « Devenir un marchand »
  Widget _buildMerchantCard(MerchantInfo merchant) {
    final textTheme = Theme.of(context).textTheme;
    final logoUrl = merchant.logoUrl;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Material(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MerchantProfileScreen()),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    image: logoUrl == null
                        ? null
                        : DecorationImage(
                            image: NetworkImage(logoUrl), fit: BoxFit.cover),
                  ),
                  child: logoUrl != null
                      ? null
                      : const Center(
                          child: HugeIcon(
                            icon: HugeIcons.strokeRoundedStore01,
                            size: 28,
                            color: AppColors.secondary,
                          ),
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        merchant.businessName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                      if (merchant.pseudo != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '@${merchant.pseudo}',
                          style: textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileSection() {
    final userName = _getUserName();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                UserAvatar(
                  pseudo: _pseudo ?? _prenoms,
                  avatarUrl: _avatarUrl,
                  radius: 32,
                ),
                const SizedBox(width: 16),
                // Nom et email
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                      ),
                      if (_pseudo?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 4),
                        Text(
                          '@$_pseudo',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required dynamic icon,
    required String title,
    required VoidCallback onTap,
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
        trailing: Icon(
          Icons.chevron_right,
          color: AppColors.textSecondary,
        ),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.viewPadding.top;
    // Navbar flottante : barre système + bouton (56) + marges (8 + 32)
    final bottomPadding = mediaQuery.viewPadding.bottom + 96;

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
                  // Section profil
                  _buildProfileSection(),
                  // Boutique si l'utilisateur est marchand, sinon « Devenir un marchand »
                  if (_merchant != null)
                    _buildMerchantCard(_merchant!)
                  else
                    Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
                          child: Material(
                            color: AppColors.secondary,
                            borderRadius: BorderRadius.circular(24),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: _handleBecomeMerchant,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 20),
                                child: Row(
                                  children: [
                                    const SizedBox(width: 80),
                                    const SizedBox(width: 0),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            context.tr('become_merchant'),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            context.tr('accept_payments'),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: Colors.white
                                                      .withOpacity(0.9),
                                                  fontSize: 12,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.arrow_forward_ios,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: -43,
                          child: IgnorePointer(
                            child: Lottie.asset(
                              'assets/jsons/OpenStore.json',
                              key: _lottieKey,
                              width: 150,
                              height: 150,
                              fit: BoxFit.contain,
                              repeat: false,
                            ),
                          ),
                        ),
                      ],
                    ),
                  // Options
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
                          icon: HugeIcons.strokeRoundedSettings01,
                          title: context.tr('settings'),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SettingsScreen(),
                              ),
                            );
                          },
                        ),
                        Divider(
                            height: 1,
                            color: AppColors.textSecondary.withOpacity(0.2)),
                        _buildMenuItem(
                          icon: HugeIcons.strokeRoundedChartBarLine,
                          title: context.tr('account_limits'),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const AccountLimitsScreen(),
                              ),
                            );
                          },
                        ),
                        Divider(
                            height: 1,
                            color: AppColors.textSecondary.withOpacity(0.2)),
                        _buildMenuItem(
                          icon: HugeIcons.strokeRoundedLock,
                          title: context.tr('security'),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SecurityScreen(),
                              ),
                            );
                          },
                        ),
                        Divider(
                            height: 1,
                            color: AppColors.textSecondary.withOpacity(0.2)),
                        _buildMenuItem(
                          icon: HugeIcons.strokeRoundedNotification01,
                          title: context.tr('notifications'),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const NotificationsScreen(),
                              ),
                            );
                          },
                        ),
                        Divider(
                            height: 1,
                            color: AppColors.textSecondary.withOpacity(0.2)),
                        _buildMenuItem(
                          icon: HugeIcons.strokeRoundedHelpCircle,
                          title: context.tr('help_support'),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const HelpSupportScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  // Fin de page : rien n'est caché derrière la navbar
                  SizedBox(height: bottomPadding + 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
