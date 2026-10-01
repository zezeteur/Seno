import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hugeicons/hugeicons.dart';
import '../widgets/dynamic_qr.dart';
import '../services/recents_store.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import '../widgets/transaction_list.dart';
import '../widgets/user_avatar.dart';
import 'qr_code_viewer_screen.dart';
import 'send_money_screen.dart';
import 'wallet_screen.dart';
import 'statistics_screen.dart';
import 'history_screen.dart';
import 'account_screen.dart';

class HomeScreen extends StatefulWidget {
  final int initialIndex;

  const HomeScreen({super.key, this.initialIndex = 0});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final supabase = Supabase.instance.client;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _loadFirstName();
    SupabaseService.profileRevision.addListener(_loadFirstName);
    RecentsStore.load();
    // Récents : dernières copies, puis mise à jour silencieuse en fond
    RecentsStore.refresh();
    WidgetsBinding.instance.addObserver(this);
    _loadTransactions();
    SupabaseService.transactionsRevision.addListener(_loadTransactions);
    // Statuts en direct (envois et réceptions) tant que l'app est ouverte
    SupabaseService.subscribeTransactions();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      RecentsStore.refresh();
      _loadTransactions();
      SupabaseService.subscribeTransactions();
    } else if (state == AppLifecycleState.paused) {
      // Arrière-plan : la connexion Realtime n'est pas gardée ouverte
      SupabaseService.unsubscribeTransactions();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SupabaseService.profileRevision.removeListener(_loadFirstName);
    SupabaseService.transactionsRevision.removeListener(_loadTransactions);
    SupabaseService.unsubscribeTransactions();
    super.dispose();
  }

  /// Copie en cache tout de suite, puis version fraîche ; null si aucune des deux
  List<SenoTransaction>? _transactions = SupabaseService.peekTransactions();
  bool _transactionsError = false;
  int _transactionsLoadId = 0;

  Future<void> _loadTransactions() async {
    final id = ++_transactionsLoadId;
    try {
      final list =
          await SupabaseService.getTransactions(limit: _homeTransactionsCount);
      if (mounted && id == _transactionsLoadId) {
        setState(() {
          _transactions = list;
          _transactionsError = false;
        });
      }
    } catch (_) {
      // Hors ligne sans copie en cache : message d'erreur
      if (mounted && id == _transactionsLoadId) {
        setState(() => _transactionsError = true);
      }
    }
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
      foregroundImage:
          _avatarUrl != null ? CachedNetworkImageProvider(_avatarUrl!) : null,
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

          // Dernières transactions + accès à l'historique
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
              // 3 derniers destinataires (nom du répertoire si connu)
              ListenableBuilder(
                listenable: Listenable.merge([
                  RecentsStore.recents,
                  RecentsStore.phoneContacts,
                  RecentsStore.senoAccounts,
                ]),
                builder: (context, _) {
                  final recents = RecentsStore.recents.value;
                  final contacts = RecentsStore.phoneContacts.value;
                  final seno = RecentsStore.senoAccounts.value;
                  // Aucun récent : le bouton d'envoi occupe toute la largeur
                  if (recents.isEmpty) {
                    return SizedBox(
                      height: 80,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: _buildSendContact(
                          context,
                          icon: HugeIcons.strokeRoundedArrowRight01,
                          label: context.tr('send'),
                          isIcon: true,
                          fullWidth: true,
                        ),
                      ),
                    );
                  }
                  return SizedBox(
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
                              for (final r in recents.take(3)) ...[
                                const SizedBox(width: 12),
                                _buildSendContact(
                                  context,
                                  icon: HugeIcons.strokeRoundedAiUser,
                                  label: RecentsStore.contactName(
                                          r, contacts, seno) ??
                                      r.value,
                                  isIcon: false,
                                  avatarUrl: r.avatarUrl,
                                  recipient: r,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
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
    RecentRecipient? recipient,
    bool fullWidth = false,
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
              width: fullWidth ? double.infinity : null,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
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
      // Envoi direct : l'écran s'ouvre sur le montant pour ce destinataire
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SendMoneyScreen(initialRecipient: recipient),
        ),
      ),
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

  /// Nombre de transactions affichées sur l'accueil (le reste : historique)
  static const _homeTransactionsCount = 10;

  Widget _buildTransactionsSection(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final transactions = _transactions;

    Widget message(String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: onSurface.withValues(alpha: 0.5)),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (transactions == null || transactions.isEmpty) ...[
            TransactionsHeader(label: context.tr('transactions')),
            const SizedBox(height: 16),
          ],
          if (transactions == null)
            _transactionsError
                ? message(context.tr('tx_load_error'))
                : const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
          else if (transactions.isEmpty)
            message(context.tr('tx_empty'))
          else ...[
            TransactionList(
              transactions: transactions.take(_homeTransactionsCount).toList(),
            ),
            // Toutes les transactions, avec filtres (largeur du contenu)
            Center(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: onSurface,
                  side: BorderSide(color: onSurface.withValues(alpha: 0.15)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50)),
                ),
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedClock01,
                  size: 18,
                  color: onSurface,
                ),
                label: Text(
                  context.tr('history'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
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
