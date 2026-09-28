import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hugeicons/hugeicons.dart';
import '../widgets/dynamic_qr.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import '../widgets/user_avatar.dart';
import 'qr_code_viewer_screen.dart';
import 'send_money_screen.dart';
import 'wallet_screen.dart';
import 'statistics_screen.dart';
import 'account_screen.dart';

class HomeScreen extends StatefulWidget {
  final int initialIndex;

  const HomeScreen({super.key, this.initialIndex = 0});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final supabase = Supabase.instance.client;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _loadFirstName();
    SupabaseService.profileRevision.addListener(_loadFirstName);
  }

  @override
  void dispose() {
    SupabaseService.profileRevision.removeListener(_loadFirstName);
    super.dispose();
  }

  String? _firstName;
  String? _pseudo;
  String? _avatarUrl;

  Future<void> _loadFirstName() async {
    try {
      final profile = await SupabaseService.getLockProfile();
      // Premier prénom seulement : « Jean Marc » → « Jean »
      final first = profile.prenoms?.trim().split(RegExp(r'\s+')).first;
      if (mounted) {
        setState(() {
          _firstName = first;
          _pseudo = profile.pseudo;
          _avatarUrl = profile.avatarUrl;
        });
      }
    } catch (_) {
      // Hors ligne : le libellé par défaut reste affiché
    }
  }

  String _getUserName() {
    final name = _firstName;
    return name != null && name.isNotEmpty ? name : context.tr('user');
  }

  /// Photo de profil, sinon initiale du prénom, sinon icône utilisateur
  Widget _buildAvatar(BuildContext context) {
    final name = _firstName;
    final initial =
        name != null && name.isNotEmpty ? name[0].toUpperCase() : null;
    return CircleAvatar(
      radius: 24,
      backgroundColor: Colors.black,
      foregroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
      child: initial != null
          ? Text(
              initial,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
            )
          : const HugeIcon(
              icon: HugeIcons.strokeRoundedUser,
              size: 22,
              color: AppColors.primary,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.viewPadding.bottom;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeContent(),
          WalletScreen(key: WalletScreen.globalKey),
          const StatisticsScreen(),
          const AccountScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: _buildBottomNavigationBar(context),
      ),
    );
  }

  Widget _buildHomeContent() {
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.viewPadding.bottom;

    return SingleChildScrollView(
      child: Column(
        children: [
          // Carte de solde jaune
          _buildBalanceCard(context),

          // Section Today avec transactions
          _buildTransactionsSection(context),
          // SafeArea en bas
          SizedBox(height: bottomPadding),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(BuildContext context) {
    final topPadding = MediaQuery.of(context).viewPadding.top;
    return Container(
      margin: EdgeInsets.fromLTRB(20, 20 + topPadding, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          // Pattern en haut à droite
          Positioned(
            top: 0,
            right: 0,
            child: Image.asset(
              'assets/images/pattern.png',
              width: 120,
              height: 120,
              fit: BoxFit.cover,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Contenu avec padding
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nom de l'utilisateur avec QR code
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildAvatar(context),
                              const SizedBox(height: 12),
                              // Une seule ligne : prénom long tronqué (« Hello Jean-Christo… »)
                              Text(
                                'Hello ${_getUserName()}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .displayLarge
                                    ?.copyWith(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                              ),
                              if (_pseudo?.isNotEmpty ?? false) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '@$_pseudo',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color:
                                            Colors.black.withValues(alpha: 0.6),
                                        fontSize: 14,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const QRCodeViewerScreen(),
                              ),
                            );
                          },
                          // Marge blanche : les repères du QR ne sont pas rognés
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            padding: const EdgeInsets.all(10),
                            child: const DynamicQrCode(size: 100),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Send money section
                    Text(
                      context.tr('send_money'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.black,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                    ),
                  ],
                ),
              ),

              // Contacts pour envoyer de l'argent - sans padding latéral pour aller jusqu'aux bords
              SizedBox(
                height: 80,
                child: ClipRect(
                  clipBehavior: Clip.hardEdge,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          _buildSendContact(
                            context,
                            icon: HugeIcons.strokeRoundedArrowRight01,
                            label: context.tr('send'),
                            isIcon: true,
                          ),
                          const SizedBox(width: 12),
                          _buildSendContact(
                            context,
                            icon: HugeIcons.strokeRoundedAiUser,
                            label: 'devon',
                            isIcon: false,
                            color: Colors.blue,
                          ),
                          const SizedBox(width: 12),
                          _buildSendContact(
                            context,
                            icon: HugeIcons.strokeRoundedAiUser,
                            label: 'sara_k',
                            isIcon: false,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 12),
                          _buildSendContact(
                            context,
                            icon: HugeIcons.strokeRoundedAiUser,
                            label: 'moussa225',
                            isIcon: false,
                            color: Colors.purple,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSendContact(
    BuildContext context, {
    required dynamic icon,
    required String label,
    required bool isIcon,
    Color? color,
    String? avatarUrl,
  }) {
    // Bouton d'envoi : pilule noire avec le texte à l'intérieur
    if (isIcon) {
      return GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SendMoneyScreen()),
        ),
        child: Column(
          children: [
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  HugeIcon(icon: icon, size: 18, color: Colors.white),
                ],
              ),
            ),
            // Même hauteur que les contacts (nom sous l'avatar) pour l'alignement
            const SizedBox(height: 24),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        // Fonctionnalité à venir
      },
      child: Column(
        children: [
          UserAvatar(
            pseudo: label,
            avatarUrl: avatarUrl,
            radius: 28,
            backgroundColor: color ?? AppColors.secondary,
            foregroundColor: Colors.white,
          ),
          const SizedBox(height: 6),
          // Largeur fixe : un pseudo trop long est tronqué (« moussa2… »)
          SizedBox(
            width: 64,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.black.withOpacity(0.6),
                    fontSize: 12,
                    height: 1.2,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Today
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Transform.scale(
                    scale: 0.95,
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedWallet01,
                      size: 16,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.tr('today'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                        ),
                  ),
                ],
              ),
              IconButton(
                icon: Transform.scale(
                  scale: 0.95,
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedAiSearch,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                onPressed: () {
                  // Fonctionnalité à venir
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Transaction Airbnb
          _buildTransactionItem(
            context,
            icon: HugeIcons.strokeRoundedHome01,
            iconColor: Colors.red,
            title: 'AirBnb',
            category: context.tr('cat_housing'),
            amount: '- 200',
            isNegative: true,
          ),
          const SizedBox(height: 12),

          // Transaction McDonald's
          _buildTransactionItem(
            context,
            icon: HugeIcons.strokeRoundedRestaurant01,
            iconColor: Colors.green.shade700,
            title: 'McDonald\'s',
            category: context.tr('cat_restaurant'),
            amount: '- 1,123.10',
            isNegative: true,
          ),
          const SizedBox(height: 12),

          // Transaction Transfer
          _buildTransactionItem(
            context,
            icon: HugeIcons.strokeRoundedCoinsSwap,
            iconColor: Theme.of(context).colorScheme.onSurface,
            title: context.tr('transfer'),
            category: '*4243',
            amount: '+ 153.54',
            isNegative: false,
          ),
          const SizedBox(height: 12),

          // Transaction Uber
          _buildTransactionItem(
            context,
            icon: HugeIcons.strokeRoundedCar01,
            iconColor: Colors.black,
            title: 'Uber',
            category: context.tr('cat_transport'),
            amount: '- 2,500',
            isNegative: true,
          ),
          const SizedBox(height: 12),

          // Transaction Salaire
          _buildTransactionItem(
            context,
            icon: HugeIcons.strokeRoundedCoinsSwap,
            iconColor: Colors.green,
            title: context.tr('salary'),
            category: context.tr('cat_income'),
            amount: '+ 150,000',
            isNegative: false,
          ),
          const SizedBox(height: 12),

          // Transaction Netflix
          _buildTransactionItem(
            context,
            icon: HugeIcons.strokeRoundedPlay,
            iconColor: Colors.red.shade700,
            title: 'Netflix',
            category: context.tr('cat_subscription'),
            amount: '- 5,000',
            isNegative: true,
          ),
          const SizedBox(height: 12),

          // Transaction Pharmacie
          _buildTransactionItem(
            context,
            icon: HugeIcons.strokeRoundedShoppingBag01,
            iconColor: Colors.blue,
            title: context.tr('pharmacy'),
            category: context.tr('cat_health'),
            amount: '- 8,750',
            isNegative: true,
          ),
          const SizedBox(height: 12),

          // Transaction Supermarché
          _buildTransactionItem(
            context,
            icon: HugeIcons.strokeRoundedShoppingCart01,
            iconColor: Colors.orange,
            title: context.tr('supermarket'),
            category: context.tr('cat_groceries'),
            amount: '- 12,300',
            isNegative: true,
          ),
          const SizedBox(height: 12),

          // Transaction Spotify
          _buildTransactionItem(
            context,
            icon: HugeIcons.strokeRoundedPlay,
            iconColor: Colors.green.shade600,
            title: 'Spotify',
            category: context.tr('cat_subscription'),
            amount: '- 2,500',
            isNegative: true,
          ),
          const SizedBox(height: 12),

          // Transaction Essence
          _buildTransactionItem(
            context,
            icon: HugeIcons.strokeRoundedCar01,
            iconColor: Colors.amber.shade700,
            title: context.tr('gas_station'),
            category: context.tr('cat_transport'),
            amount: '- 15,000',
            isNegative: true,
          ),
          const SizedBox(height: 12),

          // Transaction Virement reçu
          _buildTransactionItem(
            context,
            icon: HugeIcons.strokeRoundedCoinsSwap,
            iconColor: Colors.green,
            title: context.tr('transfer_received'),
            category: 'Marie Dupont',
            amount: '+ 25,000',
            isNegative: false,
          ),
          const SizedBox(height: 12),

          // Transaction Café
          _buildTransactionItem(
            context,
            icon: HugeIcons.strokeRoundedRestaurant01,
            iconColor: Colors.brown,
            title: 'Starbucks',
            category: context.tr('cat_cafe'),
            amount: '- 3,500',
            isNegative: true,
          ),
          const SizedBox(height: 12),

          // Transaction Amazon
          _buildTransactionItem(
            context,
            icon: HugeIcons.strokeRoundedShoppingBag01,
            iconColor: Colors.orange.shade700,
            title: 'Amazon',
            category: context.tr('cat_online'),
            amount: '- 45,000',
            isNegative: true,
          ),
          const SizedBox(height: 12),

          // Transaction Banque
          _buildTransactionItem(
            context,
            icon: HugeIcons.strokeRoundedWallet01,
            iconColor: Colors.blue.shade700,
            title: context.tr('bank_fees'),
            category: context.tr('cat_bank'),
            amount: '- 1,000',
            isNegative: true,
          ),
          const SizedBox(height: 12),

          // Transaction Cinéma
          _buildTransactionItem(
            context,
            icon: HugeIcons.strokeRoundedPlay,
            iconColor: Colors.purple,
            title: context.tr('cinema'),
            category: context.tr('cat_entertainment'),
            amount: '- 5,500',
            isNegative: true,
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionItem(
    BuildContext context, {
    required dynamic icon,
    required Color iconColor,
    required String title,
    required String category,
    required String amount,
    required bool isNegative,
  }) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: iconColor,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Transform.scale(
              scale: 0.95,
              child: HugeIcon(
                icon: icon,
                size: 20,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                category,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.5),
                      fontSize: 12,
                    ),
              ),
            ],
          ),
        ),
        Text(
          amount,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: isNegative
                    ? Theme.of(context).colorScheme.onSurface
                    : AppColors.success,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
        ),
      ],
    );
  }

  Widget _buildBottomNavigationBar(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Theme(
        data: Theme.of(context).copyWith(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            // Retour sur le portefeuille : cartes empilées par défaut
            if (index == 1 && _currentIndex != 1) {
              WalletScreen.globalKey.currentState?.collapseCards();
            }
            setState(() {
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          selectedItemColor: Theme.of(context).colorScheme.onSurface,
          unselectedItemColor:
              Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
          selectedFontSize: 14,
          unselectedFontSize: 12,
          items: [
            BottomNavigationBarItem(
              icon: _buildNavIcon(
                icon: HugeIcons.strokeRoundedHome01,
                isSelected: _currentIndex == 0,
              ),
              label: context.tr('nav_home'),
            ),
            BottomNavigationBarItem(
              icon: _buildNavIcon(
                icon: HugeIcons.strokeRoundedWallet01,
                isSelected: _currentIndex == 1,
              ),
              label: context.tr('nav_wallet'),
            ),
            BottomNavigationBarItem(
              icon: _buildNavIcon(
                icon: HugeIcons.strokeRoundedChart01,
                isSelected: _currentIndex == 2,
              ),
              label: context.tr('nav_stats'),
            ),
            BottomNavigationBarItem(
              icon: _buildNavIcon(
                icon: HugeIcons.strokeRoundedAiUser,
                isSelected: _currentIndex == 3,
              ),
              label: context.tr('nav_account'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavIcon({
    required dynamic icon,
    required bool isSelected,
  }) {
    if (isSelected) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black,
          shape: BoxShape.circle,
        ),
        child: Transform.scale(
          scale: 0.95,
          child: HugeIcon(
            icon: icon,
            size: 24,
            color: Colors.white,
          ),
        ),
      );
    } else {
      return Transform.scale(
        scale: 0.95,
        child: HugeIcon(
          icon: icon,
          size: 24,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
        ),
      );
    }
  }
}
