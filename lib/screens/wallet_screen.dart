import 'dart:async';

import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shimmer/shimmer.dart';
import '../models/reseau.dart';
import '../models/compte.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import '../utils/auth_errors.dart';
import '../utils/pair_digits_formatter.dart';
import '../utils/toast_service.dart';
import 'home_screen.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  static final GlobalKey<_WalletScreenState> globalKey =
      GlobalKey<_WalletScreenState>();

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with SingleTickerProviderStateMixin {
  String? _defaultCompteId; // ID du compte par défaut depuis l'API
  String?
      _loadingDefaultCompteId; // ID du compte en cours de chargement pour définir comme défaut
  List<Reseau> _reseaux = [];
  List<Compte> _comptes = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isExpanded = false;

  // Contrôleurs pour le formulaire d'ajout
  final TextEditingController _numeroController = TextEditingController();
  final TextEditingController _confirmationController = TextEditingController();
  // Contrôleurs pour le formulaire de modification
  final TextEditingController _editNumeroController = TextEditingController();

  // Ajout de compte : vérification du numéro par SMS
  String? _compteOtpToken;
  bool _compteOtpSending = false;
  int _compteOtpSeconds = 0;
  Timer? _compteOtpTimer;
  final TextEditingController _editConfirmationController =
      TextEditingController();
  Reseau? _selectedReseau;
  int _addAccountStep = 0; // 0 = choix réseau, 1 = saisie numéro
  bool _isAddingAccount = false; // Indicateur de chargement pour l'ajout
  bool _isUpdatingAccount =
      false; // Indicateur de chargement pour la modification
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOutCubic,
    );
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  /// Cartes empilées (état par défaut) ; appelé aussi au retour sur l'onglet
  void collapseCards() {
    if (!_isExpanded && _animationController.value == 0) return;
    setState(() => _isExpanded = false);
    _animationController.value = 0;
  }

  // Méthode publique pour recharger les comptes depuis l'extérieur
  Future<void> reloadComptes() async {
    collapseCards();
    await _loadComptes();
    await _loadDefaultCompte();
  }

  Future<void> _loadData() async {
    await _loadReseaux();
    await _loadComptes();
    await _loadDefaultCompte();
  }

  Future<void> _loadComptes() async {
    try {
      final comptes = await SupabaseService.getComptes();
      if (mounted) {
        setState(() {
          _comptes = comptes;
          // Nouvelle liste : on repart des cartes empilées
          _isExpanded = false;
        });
        _animationController.value = 0;
      }
    } catch (e) {
      // Erreur silencieuse pour les comptes, on continue avec les réseaux
    }
  }

  Future<void> _loadDefaultCompte() async {
    try {
      final defaultCompte = await SupabaseService.getDefaultCompte();
      if (mounted) {
        setState(() {
          _defaultCompteId = defaultCompte?.id;
        });
      }
    } catch (e) {
      // Erreur silencieuse, on continue sans compte par défaut
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _numeroController.dispose();
    _confirmationController.dispose();
    _editNumeroController.dispose();
    _compteOtpTimer?.cancel();
    _editConfirmationController.dispose();
    super.dispose();
  }

  Future<void> _loadReseaux() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final reseaux = await SupabaseService.getReseaux();
      setState(() {
        _reseaux = reseaux;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Widget _buildCardShimmer({required int index}) {
    const double cardHeight = 200.0;
    const double stackOffset = 20.0;
    final double top = index * stackOffset;

    return Positioned(
      top: top,
      left: 20,
      right: 20,
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Container(
          height: cardHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: Colors.white,
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 50,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 150,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 60,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 100,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Mapping des couleurs pour chaque réseau
  List<Color> _getReseauColors(String nom) {
    final nomLower = nom.toLowerCase();
    if (nomLower.contains('orange')) {
      return [Colors.black, Colors.grey.shade900];
    } else if (nomLower.contains('mtn')) {
      return [const Color(0xFFFFCD00), const Color(0xFFE6B800)];
    } else if (nomLower.contains('moov')) {
      return [const Color(0xFF0067B3), const Color(0xFF005299)];
    } else if (nomLower.contains('wave')) {
      return [const Color(0xFF1CC8FE), const Color(0xFF17B0E0)];
    }
    // Couleur par défaut
    return [Colors.grey.shade700, Colors.grey.shade900];
  }

  Widget _buildMobileMoneyAccount({
    required Reseau reseau,
    required String phoneNumber,
    required int index,
    required String compteId,
  }) {
    // Vérifier si ce compte est le compte par défaut en comparant les IDs
    final bool isDefault =
        _defaultCompteId != null && compteId == _defaultCompteId;
    const double cardHeight = 200.0;
    const double stackOffset = 20.0;
    const double cardSpacing = 16.0;
    final colors = _getReseauColors(reseau.nom);

    // Calcul des positions pour l'empilement
    final double stackedTop = index * stackOffset;
    final double expandedTop = index * (cardHeight + cardSpacing);

    // Animation de la position avec interpolation
    final double animatedTop =
        stackedTop + (expandedTop - stackedTop) * _animation.value;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Positioned(
          top: animatedTop,
          left: 20,
          right: 20,
          child: GestureDetector(
            onLongPress: () {
              HapticFeedback.mediumImpact();
              _showCardModal(context, reseau, phoneNumber, index, compteId);
            },
            child: Hero(
              tag: 'card_$index',
              child: Material(
                color: Colors.transparent,
                child: Container(
                  height: cardHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: colors,
                    ),
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              reseau.logo,
                              width: 50,
                              height: 30,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 50,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Center(
                                    child: Text(
                                      reseau.abreviation,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          GestureDetector(
                            onTap: isDefault ||
                                    compteId == _loadingDefaultCompteId
                                ? null
                                : () async {
                                    if (mounted) {
                                      setState(() {
                                        _loadingDefaultCompteId = compteId;
                                      });
                                    }
                                    try {
                                      await SupabaseService.setDefaultCompte(
                                        compteId: compteId,
                                        context: context,
                                      );
                                      // Recharger le compte par défaut depuis l'API
                                      await _loadDefaultCompte();
                                    } catch (e) {
                                      // L'erreur est déjà gérée dans setDefaultCompte avec un toast
                                    } finally {
                                      if (mounted) {
                                        setState(() {
                                          _loadingDefaultCompteId = null;
                                        });
                                      }
                                    }
                                  },
                            child: compteId == _loadingDefaultCompteId
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : Icon(
                                    isDefault
                                        ? Icons.star_rounded
                                        : Icons.star_border_rounded,
                                    size: 32,
                                    color: Colors.white,
                                  ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            phoneNumber,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.tr('network_upper'),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 10,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                reseau.nom,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAddAccountCard({required int index, bool isCentered = false}) {
    const double cardHeight = 200.0;

    Widget cardContent = GestureDetector(
      onTap: () {
        _showAddAccountModal(context);
      },
      child: Container(
        height: cardHeight,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.secondary.withOpacity(0.3),
            width: 2,
          ),
          color: Theme.of(context).colorScheme.surface,
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.secondary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.add_rounded,
                size: 32,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('add_account'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('add_account_sub'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.6),
                  ),
            ),
          ],
        ),
      ),
    );

    if (isCentered) {
      return cardContent;
    }

    // Pour l'empilement avec animation
    const double stackOffset = 20.0;
    const double cardSpacing = 16.0;
    final double stackedTop = index * stackOffset;
    final double expandedTop = index * (cardHeight + cardSpacing);
    final double animatedTop =
        stackedTop + (expandedTop - stackedTop) * _animation.value;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Positioned(
          top: animatedTop,
          left: 20,
          right: 20,
          child: cardContent,
        );
      },
    );
  }

  Widget _buildCardContent({
    required Reseau reseau,
    required String phoneNumber,
    required int index,
    required bool isDefault,
  }) {
    const double cardHeight = 200.0;
    final colors = _getReseauColors(reseau.nom);

    return Container(
      height: cardHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  reseau.logo,
                  width: 50,
                  height: 30,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 50,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          reseau.abreviation,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Icon(
                isDefault ? Icons.star_rounded : Icons.star_border_rounded,
                size: 32,
                color: Colors.white,
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                phoneNumber,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('network_upper'),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 10,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    reseau.nom,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showCardModal(
    BuildContext context,
    Reseau reseau,
    String phoneNumber,
    int index,
    String? compteId,
  ) {
    // Vérifier si ce compte est le compte par défaut en comparant les IDs
    final isDefault = compteId != null &&
        _defaultCompteId != null &&
        compteId == _defaultCompteId;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setModalState) => Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Carte avec Hero animation
                Hero(
                  tag: 'card_$index',
                  child: Material(
                    color: Colors.transparent,
                    child: _buildCardContent(
                      reseau: reseau,
                      phoneNumber: phoneNumber,
                      index: index,
                      isDefault: isDefault,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Options
                ListTile(
                  leading:
                      compteId != null && compteId == _loadingDefaultCompteId
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.grey,
                                ),
                              ),
                            )
                          : HugeIcon(
                              icon: HugeIcons.strokeRoundedStar,
                              size: 24,
                              color: isDefault ? Colors.amber : Colors.grey,
                            ),
                  title: Text(
                    isDefault
                        ? context.tr('default_account')
                        : context.tr('set_default'),
                  ),
                  enabled: !isDefault && compteId != _loadingDefaultCompteId,
                  onTap: isDefault || compteId == _loadingDefaultCompteId
                      ? null
                      : () async {
                          if (compteId == null) return;

                          if (mounted) {
                            setState(() {
                              _loadingDefaultCompteId = compteId;
                            });
                            setModalState(() {});
                          }
                          try {
                            await SupabaseService.setDefaultCompte(
                              compteId: compteId,
                              context: context,
                            );
                            // Recharger le compte par défaut depuis l'API
                            await _loadDefaultCompte();
                            if (mounted) {
                              Navigator.pop(context);
                            }
                          } catch (e) {
                            // L'erreur est déjà gérée dans setDefaultCompte avec un toast
                            // Ne pas fermer la modale en cas d'erreur pour que l'utilisateur puisse réessayer
                          } finally {
                            if (mounted) {
                              setState(() {
                                _loadingDefaultCompteId = null;
                              });
                              setModalState(() {});
                            }
                          }
                        },
                ),
                ListTile(
                  leading: Icon(
                    Icons.edit_rounded,
                    size: 24,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  title: Text(context.tr('edit')),
                  onTap: () {
                    Navigator.pop(context);
                    if (compteId != null) {
                      _showEditAccountModal(
                          context, compteId, reseau, phoneNumber);
                    }
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.delete_rounded,
                    size: 24,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    context.tr('delete'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    if (compteId != null) {
                      _showDeleteConfirmationModal(
                          context, compteId, reseau, phoneNumber);
                    }
                  },
                ),
                const SizedBox(height: 40),
                SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
              ],
            ),
          ),
        ),
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
                  // Header
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Text(
                          context.tr('nav_wallet'),
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
                  // Contenu
                  if (_isLoading)
                    SizedBox(
                      height: 400,
                      child: Stack(
                        children: List.generate(
                          3,
                          (index) => _buildCardShimmer(index: index),
                        ),
                      ),
                    )
                  else if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        children: [
                          Text(
                            context.tr('error_x', {'error': '$_errorMessage'}),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loadReseaux,
                            child: Text(context.tr('retry')),
                          ),
                        ],
                      ),
                    )
                  else if (_reseaux.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Text(context.tr('no_network')),
                    )
                  else
                    _comptes.isEmpty
                        ? Center(
                            child: _buildAddAccountCard(
                                index: 0, isCentered: true),
                          )
                        : Column(
                            children: [
                              // Comptes mobile money empilés
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _isExpanded = !_isExpanded;
                                    if (_isExpanded) {
                                      _animationController.forward();
                                    } else {
                                      _animationController.reverse();
                                    }
                                  });
                                },
                                child: AnimatedBuilder(
                                  animation: _animation,
                                  builder: (context, child) {
                                    final itemCount = _comptes.length;
                                    final stackedHeight =
                                        200.0 + (itemCount - 1) * 20.0;
                                    final expandedHeight =
                                        itemCount * (200.0 + 16.0) - 16.0;
                                    final animatedHeight = stackedHeight +
                                        (expandedHeight - stackedHeight) *
                                            _animation.value;

                                    return Container(
                                      margin: const EdgeInsets.symmetric(
                                          horizontal: 20),
                                      height: animatedHeight,
                                      child: Stack(
                                        children: () {
                                          // Compte par défaut en premier (en haut quand déplié)
                                          final ordered = [
                                            ..._comptes.where((c) =>
                                                c.id == _defaultCompteId),
                                            ..._comptes.where((c) =>
                                                c.id != _defaultCompteId),
                                          ];
                                          final cards = List.generate(
                                            ordered.length,
                                            (index) {
                                              final compte = ordered[index];
                                              final reseau =
                                                  _reseaux.firstWhere(
                                                (r) => r.id == compte.idReseau,
                                                orElse: () => _reseaux.first,
                                              );
                                              return _buildMobileMoneyAccount(
                                                reseau: reseau,
                                                phoneNumber: compte.numero,
                                                index: index,
                                                compteId: compte.id,
                                              );
                                            },
                                          );
                                          // Peinte en dernier = au-dessus de la pile :
                                          // la carte par défaut recouvre les autres
                                          return cards.reversed.toList();
                                        }(),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              // Bouton pour ajouter un nouveau compte (masqué si aucun compte ou tous les réseaux sont ajoutés)
                              Builder(
                                builder: (context) {
                                  // Vérifier si tous les réseaux sont ajoutés
                                  final reseauxIdsDejaAjoutes =
                                      _comptes.map((c) => c.idReseau).toSet();
                                  final reseauxDisponibles = _reseaux
                                      .where((r) =>
                                          !reseauxIdsDejaAjoutes.contains(r.id))
                                      .toList();

                                  if (_comptes.isNotEmpty &&
                                      reseauxDisponibles.isNotEmpty) {
                                    return Column(
                                      children: [
                                        const SizedBox(height: 24),
                                        Container(
                                          margin: const EdgeInsets.symmetric(
                                              horizontal: 20, vertical: 8),
                                          child: ElevatedButton(
                                            onPressed: () {
                                              _showAddAccountModal(context);
                                            },
                                            style: ElevatedButton.styleFrom(
                                              overlayColor: Colors.transparent,
                                              backgroundColor: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                              foregroundColor: Theme.of(context)
                                                  .colorScheme
                                                  .onPrimary,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 16),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(24),
                                              ),
                                              elevation: 0,
                                              enableFeedback: false,
                                            ).copyWith(
                                              elevation:
                                                  MaterialStateProperty.all(0),
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.add,
                                                  size: 24,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onPrimary,
                                                ),
                                                const SizedBox(width: 12),
                                                Text(
                                                  context.tr('add_account'),
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onPrimary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                            ],
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

  void _showAddAccountModal(BuildContext context) {
    _selectedReseau = null;
    _numeroController.clear();
    _addAccountStep = 0;
    final isFirstAccount = _comptes.isEmpty;

    // Ajouter un listener pour mettre à jour l'état dynamiquement
    _numeroController.addListener(() {
      // La validation se fera via setState dans le StatefulBuilder
    });

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setModalState) {
            // Filtrer les réseaux déjà ajoutés (recalculé à chaque build pour être à jour)
            final reseauxIdsDejaAjoutes =
                _comptes.map((c) => c.idReseau).toSet();
            final reseauxDisponibles = _reseaux
                .where((r) => !reseauxIdsDejaAjoutes.contains(r.id))
                .toList();

            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Bouton retour (si étape 2)
                  if (_addAccountStep == 1)
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () {
                        setModalState(() {
                          _addAccountStep = 0;
                        });
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  const SizedBox(height: 8),
                  // Titre
                  Text(
                    _addAccountStep == 0
                        ? context.tr('choose_network')
                        : context.tr('enter_number'),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 24),
                  // Contenu selon l'étape
                  if (_addAccountStep == 0) ...[
                    // Étape 1 : Sélection du réseau
                    if (reseauxDisponibles.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                size: 64,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                context.tr('all_networks_added'),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      color: Colors.grey.shade600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: reseauxDisponibles.map((reseau) {
                              final isSelected =
                                  _selectedReseau?.id == reseau.id;
                              return GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    _selectedReseau = reseau;
                                  });
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppColors.secondary
                                          : Colors.grey.shade300,
                                      width: isSelected ? 2 : 1,
                                    ),
                                    color: isSelected
                                        ? AppColors.secondary.withOpacity(0.1)
                                        : Colors.transparent,
                                  ),
                                  child: Row(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: Image.network(
                                          reseau.logo,
                                          width: 40,
                                          height: 24,
                                          fit: BoxFit.contain,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                            return Container(
                                              width: 40,
                                              height: 24,
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade200,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  reseau.abreviation,
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          reseau.nom,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyLarge,
                                        ),
                                      ),
                                      if (isSelected)
                                        Icon(
                                          Icons.check_circle,
                                          color: AppColors.secondary,
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    if (reseauxDisponibles.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      // Bouton suivant
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _selectedReseau == null
                              ? null
                              : () {
                                  setModalState(() {
                                    _addAccountStep = 1;
                                  });
                                },
                          style: ElevatedButton.styleFrom(
                            overlayColor: Colors.transparent,
                            backgroundColor: AppColors.secondary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            context.tr('next'),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ] else ...[
                    // Étape 2 : Saisie du numéro
                    // Afficher le réseau sélectionné
                    if (_selectedReseau != null)
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              _selectedReseau!.logo,
                              width: 48,
                              height: 32,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 48,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Text(
                                      _selectedReseau!.abreviation,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.tr('selected_network'),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Colors.grey.shade600,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _selectedReseau!.nom,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    const SizedBox(height: 24),
                    // Champ numéro de téléphone
                    Text(
                      context.tr('phone_number'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _numeroController,
                      keyboardType: TextInputType.phone,
                      autofocus: true,
                      // « 07 01 02 03 04 » : 10 chiffres groupés 2 par 2
                      inputFormatters: [PairDigitsFormatter(maxDigits: 10)],
                      style: _numeroStyle,
                      onChanged: (value) {
                        setModalState(() {});
                      },
                      decoration: InputDecoration(
                        hintText: context.tr('enter_your_number'),
                        filled: false,
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(
                            color: Colors.grey.shade300,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(
                            color: AppColors.secondary,
                            width: 2,
                          ),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(
                            color: Colors.red,
                            width: 2,
                          ),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(
                            color: Colors.red,
                            width: 2,
                          ),
                        ),
                        prefixText: '+225 ',
                        prefixStyle: _numeroStyle,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 18,
                        ),
                        errorText: _getValidationError(),
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Bouton de validation
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _numeroController.text.isEmpty ||
                                _getValidationError() != null
                            ? null
                            : () {
                                // Afficher la modale de confirmation
                                _showConfirmationModal(
                                  context,
                                  setModalState,
                                  _selectedReseau!,
                                  _numeroDigits,
                                  isFirstAccount,
                                );
                              },
                        style: ElevatedButton.styleFrom(
                          overlayColor: Colors.transparent,
                          backgroundColor: AppColors.secondary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          context.tr('add'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 60),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Numéro saisi sans les espaces d'affichage
  String get _numeroDigits => _numeroController.text.replaceAll(' ', '');

  static const _numeroStyle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );

  String? _getValidationError() {
    if (_selectedReseau == null || _numeroController.text.isEmpty) {
      return null;
    }

    final numero = _numeroDigits;

    // Vérifier la longueur minimale
    if (numero.length < 10) {
      return context.tr('number_10_digits');
    }

    if (numero.length < 2) {
      return null; // Pas encore assez de caractères pour valider le préfixe
    }

    final reseauName = _selectedReseau!.nom.toLowerCase();
    final prefix = numero.substring(0, 2);

    if (reseauName.contains('moov')) {
      if (prefix != '01') {
        return context.tr('moov_prefix');
      }
    } else if (reseauName.contains('orange')) {
      if (prefix != '07') {
        return context.tr('orange_prefix');
      }
    } else if (reseauName.contains('mtn')) {
      if (prefix != '05') {
        return context.tr('mtn_prefix');
      }
    } else if (reseauName.contains('wave')) {
      if (prefix != '01' && prefix != '07' && prefix != '05') {
        return context.tr('wave_prefix');
      }
    }

    return null;
  }

  void _showConfirmationModal(
    BuildContext context,
    StateSetter setModalState,
    Reseau reseau,
    String numero,
    bool isFirstAccount,
  ) {
    _confirmationController.clear();
    _isAddingAccount = false;
    _compteOtpToken = null;
    var otpRequested = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            // SMS envoyé une seule fois, à l'ouverture de la modale
            if (!otpRequested) {
              otpRequested = true;
              WidgetsBinding.instance.addPostFrameCallback((_) =>
                  _sendCompteOtp(context, setDialogState, reseau, numero));
            }
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Titre
                  Text(
                    context.tr('confirm_number'),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 24),
                  // Réseau
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          reseau.logo,
                          width: 40,
                          height: 24,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 40,
                              height: 24,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  reseau.abreviation,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        reseau.nom,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildCompteOtpSection(
                    context,
                    setDialogState,
                    reseau,
                    numero,
                    _confirmationController,
                  ),
                  if (isFirstAccount) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.star_rounded,
                            color: AppColors.secondary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              context.tr('will_be_default'),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppColors.secondary,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  // Boutons
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            _confirmationController.clear();
                            Navigator.pop(context);
                          },
                          style: TextButton.styleFrom(
                            overlayColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                          ),
                          child: Text(
                            context.tr('cancel'),
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: (_compteOtpToken != null &&
                                  _confirmationController.text.length == 4 &&
                                  !_isAddingAccount)
                              ? () async {
                                  setDialogState(() {
                                    _isAddingAccount = true;
                                  });

                                  try {
                                    // Créer le compte
                                    await SupabaseService.createCompte(
                                      verificationToken: _compteOtpToken!,
                                      otp: _confirmationController.text,
                                      setAsDefault: isFirstAccount,
                                    );
                                    _compteOtpTimer?.cancel();

                                    if (mounted && context.mounted) {
                                      // Si c'était le premier compte, rediriger vers HomeScreen pour afficher la navbar
                                      if (isFirstAccount) {
                                        // Fermer les modales d'abord
                                        Navigator.pop(
                                            context); // Fermer la modale de confirmation
                                        Navigator.pop(
                                            context); // Fermer la modale d'ajout

                                        // Attendre un peu pour que les modales se ferment complètement
                                        await Future.delayed(
                                            const Duration(milliseconds: 200));

                                        if (mounted && context.mounted) {
                                          Navigator.of(context)
                                              .pushAndRemoveUntil(
                                            MaterialPageRoute(
                                              builder: (_) => const HomeScreen(
                                                  initialIndex: 1),
                                            ),
                                            (route) => false,
                                          );
                                          return; // Sortir pour éviter de continuer
                                        }
                                      }

                                      // Fermer les modales d'abord
                                      Navigator.pop(
                                          context); // Fermer la modale de confirmation
                                      Navigator.pop(
                                          context); // Fermer la modale d'ajout

                                      // Attendre que les modales soient complètement fermées
                                      await Future.delayed(
                                          const Duration(milliseconds: 200));

                                      // Attendre un peu pour que la base de données se mette à jour
                                      await Future.delayed(
                                          const Duration(milliseconds: 500));

                                      // Recharger les comptes
                                      if (mounted) {
                                        await _loadComptes();

                                        // Forcer un rebuild immédiat
                                        if (mounted) {
                                          setState(() {});
                                        }

                                        // Utiliser addPostFrameCallback pour s'assurer que le setState est appelé après le frame
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                          if (mounted) {
                                            setState(() {});
                                          }
                                        });

                                        // Afficher le message de succès
                                        if (mounted && context.mounted) {
                                          ToastService.showInfo(
                                            context,
                                            context.tr('account_added'),
                                          );
                                        }
                                      }
                                    }
                                  } catch (e) {
                                    if (mounted && context.mounted) {
                                      setDialogState(() {
                                        _isAddingAccount = false;
                                        _confirmationController.clear();
                                      });
                                      if (context.mounted) {
                                        ToastService.showError(
                                          context,
                                          authErrorMessage(context, e),
                                        );
                                      }
                                    }
                                  }
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            overlayColor: Colors.transparent,
                            backgroundColor: AppColors.secondary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            elevation: 0,
                          ),
                          child: _isAddingAccount
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : Text(
                                  context.tr('confirm'),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            );
          },
        ),
      ),
    ).whenComplete(() => _compteOtpTimer?.cancel());
  }

  /// Code SMS envoyé au numéro (ajout ou modification) + bouton de renvoi
  Widget _buildCompteOtpSection(
    BuildContext context,
    StateSetter setDialogState,
    Reseau reseau,
    String numero,
    TextEditingController controller, {
    String? compteId,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('compte_otp_title'),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('compte_otp_subtitle',
              {'phone': PairDigitsFormatter.group(numero)}),
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          maxLength: 4,
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: 16,
          ),
          onChanged: (_) => setDialogState(() {}),
          decoration: InputDecoration(
            hintText: '••••',
            filled: false,
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(color: AppColors.secondary, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        Center(
          child: TextButton(
            onPressed: _compteOtpSeconds > 0 || _compteOtpSending
                ? null
                : () => _sendCompteOtp(context, setDialogState, reseau, numero,
                    compteId: compteId),
            child: Text(
              _compteOtpSending
                  ? '…'
                  : _compteOtpSeconds > 0
                      ? context
                          .tr('resend_in', {'seconds': '$_compteOtpSeconds'})
                      : context.tr('resend_code'),
            ),
          ),
        ),
      ],
    );
  }

  /// Envoie (ou renvoie) le code SMS au numéro à ajouter ou modifier
  Future<void> _sendCompteOtp(
    BuildContext context,
    StateSetter setDialogState,
    Reseau reseau,
    String numero, {
    String? compteId,
  }) async {
    setDialogState(() => _compteOtpSending = true);
    try {
      if (_compteOtpToken == null) {
        _compteOtpToken = await SupabaseService.sendCompteOtp(
          numero: numero,
          idReseau: reseau.id,
          compteId: compteId,
        );
      } else {
        await SupabaseService.resendCompteOtp(_compteOtpToken!);
      }
      _compteOtpTimer?.cancel();
      _compteOtpSeconds = 30;
      _compteOtpTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!context.mounted) return t.cancel();
        setDialogState(() => _compteOtpSeconds--);
        if (_compteOtpSeconds <= 0) t.cancel();
      });
    } catch (e) {
      if (!context.mounted) return;
      ToastService.showError(context, authErrorMessage(context, e));
      // Numéro déjà ajouté : inutile de rester sur la confirmation
      if (e is AuthOtpException && e.code == 'compte_exists') {
        Navigator.pop(context);
        return;
      }
    }
    if (context.mounted) setDialogState(() => _compteOtpSending = false);
  }

  void _showEditAccountModal(
    BuildContext context,
    String compteId,
    Reseau reseau,
    String currentPhoneNumber,
  ) {
    _editNumeroController.text = PairDigitsFormatter.group(currentPhoneNumber);
    _editConfirmationController.clear();
    _isUpdatingAccount = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setModalState) => Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              left: 24,
              right: 24,
              top: 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Titre
                Text(
                  context.tr('edit_account'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 24),
                // Réseau (affiché mais non modifiable)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.grey.shade300,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          reseau.logo,
                          width: 48,
                          height: 32,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 48,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  reseau.abreviation,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('network'),
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey.shade600,
                                    ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            reseau.nom,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Champ numéro de téléphone
                Text(
                  context.tr('phone_number'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _editNumeroController,
                  keyboardType: TextInputType.phone,
                  autofocus: true,
                  // « 07 01 02 03 04 » : 10 chiffres groupés 2 par 2
                  inputFormatters: [PairDigitsFormatter(maxDigits: 10)],
                  style: _numeroStyle,
                  onChanged: (value) {
                    setModalState(() {});
                  },
                  decoration: InputDecoration(
                    hintText: context.tr('enter_your_number'),
                    filled: false,
                    counterText: '',
                    prefixText: '+225 ',
                    prefixStyle: _numeroStyle,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(
                        color: Colors.grey.shade300,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(
                        color: AppColors.secondary,
                        width: 2,
                      ),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(
                        color: Colors.red,
                        width: 2,
                      ),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(
                        color: Colors.red,
                        width: 2,
                      ),
                    ),
                    errorText: _getEditValidationError(reseau),
                  ),
                ),
                const SizedBox(height: 32),
                // Bouton Modifier
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _getEditValidationError(reseau) == null &&
                            _editNumeroDigits.length == 10 &&
                            _editNumeroDigits != currentPhoneNumber
                        ? () {
                            _showEditConfirmationModal(
                              context,
                              setModalState,
                              compteId,
                              reseau,
                              _editNumeroDigits,
                            );
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      overlayColor: Colors.transparent,
                      backgroundColor: AppColors.secondary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      context.tr('edit'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _editNumeroDigits =>
      _editNumeroController.text.replaceAll(' ', '');

  String? _getEditValidationError(Reseau reseau) {
    if (_editNumeroController.text.isEmpty) {
      return null;
    }

    final numero = _editNumeroDigits;

    // Vérifier la longueur minimale
    if (numero.length < 10) {
      return context.tr('number_10_digits');
    }

    if (numero.length < 2) {
      return null; // Pas encore assez de caractères pour valider le préfixe
    }

    final reseauName = reseau.nom.toLowerCase();
    final prefix = numero.substring(0, 2);

    if (reseauName.contains('moov')) {
      if (prefix != '01') {
        return context.tr('moov_prefix');
      }
    } else if (reseauName.contains('orange')) {
      if (prefix != '07') {
        return context.tr('orange_prefix');
      }
    } else if (reseauName.contains('mtn')) {
      if (prefix != '05') {
        return context.tr('mtn_prefix');
      }
    } else if (reseauName.contains('wave')) {
      if (prefix != '01' && prefix != '07' && prefix != '05') {
        return context.tr('wave_prefix');
      }
    }

    return null;
  }

  void _showEditConfirmationModal(
    BuildContext context,
    StateSetter setModalState,
    String compteId,
    Reseau reseau,
    String numero,
  ) {
    _editConfirmationController.clear();
    _isUpdatingAccount = false;
    _compteOtpToken = null;
    var otpRequested = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            // SMS envoyé une seule fois au nouveau numéro, à l'ouverture
            if (!otpRequested) {
              otpRequested = true;
              WidgetsBinding.instance.addPostFrameCallback((_) =>
                  _sendCompteOtp(context, setDialogState, reseau, numero,
                      compteId: compteId));
            }
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 60,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Titre
                  Text(
                    context.tr('confirm_number'),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 24),
                  // Réseau
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.grey.shade300,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            reseau.logo,
                            width: 48,
                            height: 32,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 48,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    reseau.abreviation,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            reseau.nom,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildCompteOtpSection(
                    context,
                    setDialogState,
                    reseau,
                    numero,
                    _editConfirmationController,
                    compteId: compteId,
                  ),
                  const SizedBox(height: 32),
                  // Boutons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isUpdatingAccount
                              ? null
                              : () {
                                  Navigator.pop(context);
                                },
                          style: OutlinedButton.styleFrom(
                            overlayColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            side: BorderSide(
                              color: Colors.grey.shade300,
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            context.tr('cancel'),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _compteOtpToken != null &&
                                  _editConfirmationController.text.length ==
                                      4 &&
                                  !_isUpdatingAccount
                              ? () async {
                                  setDialogState(() {
                                    _isUpdatingAccount = true;
                                  });

                                  try {
                                    await SupabaseService.updateCompte(
                                      verificationToken: _compteOtpToken!,
                                      otp: _editConfirmationController.text,
                                      context: context,
                                    );
                                    _compteOtpTimer?.cancel();

                                    // Fermer les modales
                                    Navigator.pop(
                                        context); // Fermer la modale de confirmation
                                    Navigator.pop(
                                        context); // Fermer la modale de modification

                                    // Attendre que les modales soient complètement fermées
                                    await Future.delayed(
                                        const Duration(milliseconds: 200));

                                    // Recharger les comptes
                                    if (mounted) {
                                      await _loadComptes();
                                      await _loadDefaultCompte();

                                      // Forcer un rebuild
                                      if (mounted) {
                                        setState(() {});
                                      }

                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                        if (mounted) {
                                          setState(() {});
                                        }
                                      });
                                    }
                                  } catch (e) {
                                    if (mounted && context.mounted) {
                                      setDialogState(() {
                                        _isUpdatingAccount = false;
                                        _editConfirmationController.clear();
                                      });
                                    }
                                  }
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            overlayColor: Colors.transparent,
                            backgroundColor: AppColors.secondary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            elevation: 0,
                          ),
                          child: _isUpdatingAccount
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : Text(
                                  context.tr('confirm'),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            );
          },
        ),
      ),
    ).whenComplete(() => _compteOtpTimer?.cancel());
  }

  void _showDeleteConfirmationModal(
    BuildContext context,
    String compteId,
    Reseau reseau,
    String phoneNumber,
  ) {
    bool _isDeletingAccount = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setDialogState) => Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 60,
              left: 24,
              right: 24,
              top: 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Titre
                Text(
                  context.tr('confirm_delete'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                Text(
                  context.tr('delete_account_confirm'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                ),
                const SizedBox(height: 24),
                // Informations du compte
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.grey.shade300,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          reseau.logo,
                          width: 48,
                          height: 32,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 48,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  reseau.abreviation,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              reseau.nom,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              phoneNumber,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Colors.grey.shade600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // Boutons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isDeletingAccount
                            ? null
                            : () {
                                Navigator.pop(context);
                              },
                        style: OutlinedButton.styleFrom(
                          overlayColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          side: BorderSide(
                            color: Colors.grey.shade300,
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          context.tr('cancel'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isDeletingAccount
                            ? null
                            : () async {
                                setDialogState(() {
                                  _isDeletingAccount = true;
                                });

                                try {
                                  // Vérifier si le compte supprimé est le compte par défaut
                                  final isDefaultAccount =
                                      _defaultCompteId != null &&
                                          compteId == _defaultCompteId;

                                  await SupabaseService.deleteCompte(
                                    compteId: compteId,
                                    context: context,
                                  );

                                  // Fermer la modale de confirmation
                                  if (mounted && context.mounted) {
                                    Navigator.pop(context);
                                  }

                                  // Attendre que la modale soit complètement fermée
                                  await Future.delayed(
                                      const Duration(milliseconds: 200));

                                  // Recharger les comptes
                                  if (mounted) {
                                    await _loadComptes();

                                    // Si le compte supprimé était le compte par défaut
                                    // et qu'il reste d'autres comptes, assigner le premier comme défaut
                                    if (isDefaultAccount &&
                                        _comptes.isNotEmpty) {
                                      final nouveauCompteParDefaut =
                                          _comptes.first;
                                      try {
                                        await SupabaseService.setDefaultCompte(
                                          compteId: nouveauCompteParDefaut.id,
                                          context: context,
                                        );
                                      } catch (e) {
                                        // L'erreur est déjà gérée dans setDefaultCompte avec un toast
                                      }
                                    }

                                    // Recharger le compte par défaut
                                    await _loadDefaultCompte();

                                    // Forcer un rebuild
                                    if (mounted) {
                                      setState(() {});
                                    }

                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      if (mounted) {
                                        setState(() {});
                                      }
                                    });
                                  }
                                } catch (e) {
                                  if (mounted && context.mounted) {
                                    setDialogState(() {
                                      _isDeletingAccount = false;
                                    });
                                    // L'erreur est déjà gérée dans deleteCompte avec un toast
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          overlayColor: Colors.transparent,
                          backgroundColor: Theme.of(context).colorScheme.error,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 0,
                        ),
                        child: _isDeletingAccount
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Text(
                                context.tr('delete'),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
