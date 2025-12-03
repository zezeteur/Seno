import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../theme/app_colors.dart';
import 'qr_code_viewer_screen.dart';
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
  }

  String _getUserName() {
    final user = supabase.auth.currentUser;
    if (user != null) {
      // Essayer d'obtenir le nom depuis user_metadata
      final fullName = user.userMetadata?['full_name'] as String?;
      if (fullName != null && fullName.isNotEmpty) {
        return fullName;
      }

      // Essayer d'obtenir le nom depuis user_metadata avec 'name'
      final name = user.userMetadata?['name'] as String?;
      if (name != null && name.isNotEmpty) {
        return name;
      }

      // Utiliser l'email comme fallback
      if (user.email != null && user.email!.isNotEmpty) {
        // Extraire le nom de l'email (partie avant @)
        final emailParts = user.email!.split('@');
        return emailParts[0];
      }
    }
    return 'Utilisateur';
  }

  String _getQRCodeData() {
    final user = supabase.auth.currentUser;
    if (user != null && user.id.isNotEmpty) {
      // Générer un QR code avec l'ID de l'utilisateur
      return user.id;
    }
    return 'seno://user/default';
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
                              Text(
                                'Hello',
                                style: Theme.of(context)
                                    .textTheme
                                    .displayLarge
                                    ?.copyWith(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _getUserName(),
                                style: Theme.of(context)
                                    .textTheme
                                    .displayLarge
                                    ?.copyWith(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => QRCodeViewerScreen(
                                  qrData: _getQRCodeData(),
                                ),
                              ),
                            );
                          },
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            padding: const EdgeInsets.all(2),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: QrImageView(
                                data: _getQRCodeData(),
                                version: QrVersions.auto,
                                size: 116,
                                backgroundColor: Colors.white,
                                eyeStyle: const QrEyeStyle(
                                  eyeShape: QrEyeShape.circle,
                                  color: Colors.black,
                                ),
                                dataModuleStyle: const QrDataModuleStyle(
                                  dataModuleShape: QrDataModuleShape.circle,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Send money section
                    Text(
                      'Envoyer de l\'argent',
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
                            label: 'Envoyer',
                            isIcon: true,
                          ),
                          const SizedBox(width: 12),
                          _buildSendContact(
                            context,
                            icon: HugeIcons.strokeRoundedAiUser,
                            label: 'Devon',
                            isIcon: false,
                            color: Colors.blue,
                          ),
                          const SizedBox(width: 12),
                          _buildSendContact(
                            context,
                            icon: HugeIcons.strokeRoundedAiUser,
                            label: 'Sara',
                            isIcon: false,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 12),
                          _buildSendContact(
                            context,
                            icon: HugeIcons.strokeRoundedAiUser,
                            label: 'John',
                            isIcon: false,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 12),
                          _buildSendContact(
                            context,
                            icon: HugeIcons.strokeRoundedAiUser,
                            label: 'Ale',
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
  }) {
    return GestureDetector(
      onTap: () {
        // Fonctionnalité à venir
      },
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isIcon ? Colors.black : color ?? AppColors.secondary,
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
          const SizedBox(height: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.black.withOpacity(0.6),
                  fontSize: 12,
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
                    'Aujourd\'hui',
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
            category: 'Logement',
            amount: '- 200',
            isNegative: true,
          ),
          const SizedBox(height: 12),

          // Bouton Add card
          _buildAddCardButton(context),
          const SizedBox(height: 12),

          // Transaction McDonald's
          _buildTransactionItem(
            context,
            icon: HugeIcons.strokeRoundedRestaurant01,
            iconColor: Colors.green.shade700,
            title: 'McDonald\'s',
            category: 'Restaurant',
            amount: '- 1,123.10',
            isNegative: true,
          ),
          const SizedBox(height: 12),

          // Transaction Transfer
          _buildTransactionItem(
            context,
            icon: HugeIcons.strokeRoundedCoinsSwap,
            iconColor: Theme.of(context).colorScheme.onSurface,
            title: 'Transfert',
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
            category: 'Transport',
            amount: '- 2,500',
            isNegative: true,
          ),
          const SizedBox(height: 12),

          // Transaction Salaire
          _buildTransactionItem(
            context,
            icon: HugeIcons.strokeRoundedCoinsSwap,
            iconColor: Colors.green,
            title: 'Salaire',
            category: 'Revenu',
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
            category: 'Abonnement',
            amount: '- 5,000',
            isNegative: true,
          ),
          const SizedBox(height: 12),

          // Transaction Pharmacie
          _buildTransactionItem(
            context,
            icon: HugeIcons.strokeRoundedShoppingBag01,
            iconColor: Colors.blue,
            title: 'Pharmacie',
            category: 'Santé',
            amount: '- 8,750',
            isNegative: true,
          ),
          const SizedBox(height: 12),

          // Transaction Supermarché
          _buildTransactionItem(
            context,
            icon: HugeIcons.strokeRoundedShoppingCart01,
            iconColor: Colors.orange,
            title: 'Supermarché',
            category: 'Courses',
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
            category: 'Abonnement',
            amount: '- 2,500',
            isNegative: true,
          ),
          const SizedBox(height: 12),

          // Transaction Essence
          _buildTransactionItem(
            context,
            icon: HugeIcons.strokeRoundedCar01,
            iconColor: Colors.amber.shade700,
            title: 'Station-service',
            category: 'Transport',
            amount: '- 15,000',
            isNegative: true,
          ),
          const SizedBox(height: 12),

          // Transaction Virement reçu
          _buildTransactionItem(
            context,
            icon: HugeIcons.strokeRoundedCoinsSwap,
            iconColor: Colors.green,
            title: 'Virement reçu',
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
            category: 'Café',
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
            category: 'Achat en ligne',
            amount: '- 45,000',
            isNegative: true,
          ),
          const SizedBox(height: 12),

          // Transaction Banque
          _buildTransactionItem(
            context,
            icon: HugeIcons.strokeRoundedWallet01,
            iconColor: Colors.blue.shade700,
            title: 'Frais bancaires',
            category: 'Banque',
            amount: '- 1,000',
            isNegative: true,
          ),
          const SizedBox(height: 12),

          // Transaction Cinéma
          _buildTransactionItem(
            context,
            icon: HugeIcons.strokeRoundedPlay,
            iconColor: Colors.purple,
            title: 'Cinéma',
            category: 'Divertissement',
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

  Widget _buildAddCardButton(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Transform.scale(
              scale: 0.95,
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedCreditCard,
                size: 20,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ajouter votre carte ou compte',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ajouter des cartes et comptes illimités',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 12,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
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
              label: 'Accueil',
            ),
            BottomNavigationBarItem(
              icon: _buildNavIcon(
                icon: HugeIcons.strokeRoundedWallet01,
                isSelected: _currentIndex == 1,
              ),
              label: 'Portefeuille',
            ),
            BottomNavigationBarItem(
              icon: _buildNavIcon(
                icon: HugeIcons.strokeRoundedChart01,
                isSelected: _currentIndex == 2,
              ),
              label: 'Statistiques',
            ),
            BottomNavigationBarItem(
              icon: _buildNavIcon(
                icon: HugeIcons.strokeRoundedAiUser,
                isSelected: _currentIndex == 3,
              ),
              label: 'Compte',
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
