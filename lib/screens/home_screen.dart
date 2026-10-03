import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hugeicons/hugeicons.dart';
import '../widgets/dynamic_qr.dart';
import '../services/payment_return_service.dart';
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
    // Lien de retour de paiement reçu au démarrage : ouvert par-dessus l'accueil
    WidgetsBinding.instance
        .addPostFrameCallback((_) => PaymentReturnService.homeReady());
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
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // Navbar flottante : le contenu passe derrière
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeContent(),
          WalletScreen(key: WalletScreen.globalKey),
          const StatisticsScreen(),
          const AccountScreen(),
        ],
      ),
      // Fond en dégradé (transparent en haut) : pas de cassure avec la page
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0),
              Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.7),
            ],
          ),
        ),
        // Zone sûre en bas (barre système), avec un minimum sans encoche
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 12),
          child: _buildBottomNavigationBar(context),
        ),
      ),
    );
  }

  Widget _buildHomeContent() {
    // Navbar flottante : barre système + bouton (56) + marges (8 + 32)
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom + 96;

    return Column(
      children: [
        // Carte de solde jaune : fixe en haut
        _buildBalanceCard(context),
        // Dernières transactions + accès à l'historique : seules à défiler
        Expanded(
          child: CustomScrollView(
            slivers: [
              ..._buildTransactionsSlivers(context),
              // Fin de page : rien n'est caché derrière la navbar
              SliverToBoxAdapter(child: SizedBox(height: bottomPadding + 40)),
            ],
          ),
        ),
      ],
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
                    const SizedBox(height: 14),
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
                  return _buildMerchantActions(
                      context, recents, contacts, seno);
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ],
      ),
    );
  }

  /// Envoyer et Encaisser côte à côte (pour tous), récents en dessous
  Widget _buildMerchantActions(
    BuildContext context,
    List<RecentRecipient> recents,
    List<PhoneContact> contacts,
    Map<String, ({String pseudo, String? avatarUrl})> seno,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Expanded(
                child: _buildPillButton(
                  label: context.tr('send'),
                  icon: HugeIcons.strokeRoundedArrowUpRight01,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SendMoneyScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPillButton(
                  label: context.tr('collect'),
                  icon: HugeIcons.strokeRoundedArrowDownLeft01,
                  color: Colors.white,
                  foregroundColor: Colors.black,
                  // QR de réception : le client le scanne pour payer
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const QRCodeViewerScreen()),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (recents.isNotEmpty) ...[
          const SizedBox(height: 16),
          SizedBox(
            height: 80,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: [
                for (final (i, r) in recents.take(4).indexed) ...[
                  if (i > 0) const SizedBox(width: 12),
                  _buildSendContact(
                    context,
                    icon: HugeIcons.strokeRoundedAiUser,
                    label:
                        RecentsStore.contactName(r, contacts, seno) ?? r.value,
                    isIcon: false,
                    avatarUrl: r.avatarUrl,
                    recipient: r,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Pilule (noire par défaut, texte + icône) sur toute la largeur disponible
  Widget _buildPillButton({
    required String label,
    required dynamic icon,
    required VoidCallback onTap,
    Color color = Colors.black,
    Color foregroundColor = Colors.white,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            HugeIcon(icon: icon, size: 18, color: foregroundColor),
          ],
        ),
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

  /// Transactions en slivers : la date du groupe reste fixe en haut
  List<Widget> _buildTransactionsSlivers(BuildContext context) {
    final transactions = _transactions;
    if (transactions == null || transactions.isEmpty) {
      return [SliverToBoxAdapter(child: _buildTransactionsSection(context))];
    }
    return [
      TransactionSliverList(
        transactions: transactions.take(_homeTransactionsCount).toList(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
      ),
      SliverToBoxAdapter(child: _buildHistoryButton(context)),
    ];
  }

  /// Toutes les transactions, avec filtres (largeur du contenu)
  Widget _buildHistoryButton(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const HistoryScreen()),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: onSurface,
            side: BorderSide(color: onSurface.withValues(alpha: 0.15)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
          ),
          icon: HugeIcon(
            icon: HugeIcons.strokeRoundedClock01,
            size: 18,
            color: onSurface,
          ),
          label: Text(
            context.tr('history'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  /// Chargement, erreur ou liste vide
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
            message(context.tr('tx_empty')),
        ],
      ),
    );
  }

  Widget _buildBottomNavigationBar(BuildContext context) {
    final items = [
      (icon: HugeIcons.strokeRoundedHome01, label: context.tr('nav_home')),
      (icon: HugeIcons.strokeRoundedWallet01, label: context.tr('nav_wallet')),
      (icon: HugeIcons.strokeRoundedChart01, label: context.tr('nav_stats')),
      (icon: HugeIcons.strokeRoundedAiUser, label: context.tr('nav_account')),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            _NavItem(
              icon: items[i].icon,
              label: items[i].label,
              isSelected: _currentIndex == i,
              onTap: () {
                // Retour sur le portefeuille : cartes empilées par défaut
                if (i == 1 && _currentIndex != 1) {
                  WalletScreen.globalKey.currentState?.collapseCards();
                }
                setState(() => _currentIndex = i);
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Onglet actif : pilule pleine (icône + libellé) ;
/// inactif : cercle clair bordé (icône seule).
/// Transitions animées : largeur, couleurs, libellé et appui.
class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final dynamic icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  static const _duration = Duration(milliseconds: 350);
  static const _curve = Curves.easeOutCubic;

  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final surface = Theme.of(context).scaffoldBackgroundColor;
    final selected = widget.isSelected;

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: _duration,
          curve: _curve,
          height: 56,
          padding: EdgeInsets.symmetric(horizontal: selected ? 22 : 16),
          decoration: BoxDecoration(
            color: selected ? onSurface : surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: onSurface, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: selected ? 0.15 : 0),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          // Couleur de l'icône / du texte en fondu
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: selected ? surface : onSurface),
            duration: _duration,
            curve: _curve,
            builder: (context, fg, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: selected ? 1.08 : 1,
                  duration: _duration,
                  curve: Curves.easeOutBack,
                  child: HugeIcon(icon: widget.icon, size: 22, color: fg),
                ),
                // Libellé : la largeur s'ouvre/se ferme en douceur
                ClipRect(
                  child: AnimatedSize(
                    duration: _duration,
                    curve: _curve,
                    alignment: Alignment.centerLeft,
                    child: AnimatedOpacity(
                      opacity: selected ? 1 : 0,
                      duration: _duration,
                      curve: _curve,
                      child: selected
                          ? Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                widget.label,
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  color: fg,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
