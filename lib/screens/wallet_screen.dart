import 'package:flutter/material.dart';
import '../models/reseau.dart';
import '../services/supabase_service.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with SingleTickerProviderStateMixin {
  int _defaultAccountIndex = 0;
  List<Reseau> _reseaux = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isExpanded = false;
  late AnimationController _animationController;
  late Animation<double> _animation;
  late ScrollController _scrollController;
  bool _isAtBottom = false;

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
    _scrollController = ScrollController();
    _scrollController.addListener(_checkScrollPosition);
    _loadReseaux();
  }

  void _checkScrollPosition() {
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;
      final isAtBottom = (maxScroll - currentScroll) < 50; // 50px de tolérance

      if (isAtBottom != _isAtBottom) {
        setState(() {
          _isAtBottom = isAtBottom;
        });
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scrollController.dispose();
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
  }) {
    final bool isDefault = index == _defaultAccountIndex;
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
                      onTap: () {
                        setState(() {
                          _defaultAccountIndex = index;
                        });
                      },
                      child: Icon(
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
                          'RESEAU',
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
        );
      },
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
              controller: _scrollController,
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Text(
                          'Portefeuille',
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
                    const Padding(
                      padding: EdgeInsets.all(40.0),
                      child: CircularProgressIndicator(),
                    )
                  else if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        children: [
                          Text(
                            'Erreur: $_errorMessage',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loadReseaux,
                            child: const Text('Réessayer'),
                          ),
                        ],
                      ),
                    )
                  else if (_reseaux.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20.0),
                      child: Text('Aucun réseau disponible'),
                    )
                  else
                    Column(
                      children: [
                        // Comptes mobile money empilés
                        NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            // Permettre le scroll normal
                            return false;
                          },
                          child: GestureDetector(
                            onVerticalDragUpdate: (details) {
                              // Détecter le sens du glissement
                              // Empiler seulement si on est en bas ET qu'on glisse vers le haut
                              if (details.delta.dy < -5 &&
                                  _isExpanded &&
                                  _isAtBottom) {
                                // Glissement vers le haut - empiler (seulement si en bas)
                                setState(() {
                                  _isExpanded = false;
                                  _animationController.reverse();
                                });
                              } else if (details.delta.dy > 5 && !_isExpanded) {
                                // Glissement vers le bas - étendre
                                setState(() {
                                  _isExpanded = true;
                                  _animationController.forward();
                                });
                              }
                            },
                            onVerticalDragEnd: (details) {
                              // Ajuster selon la vélocité du glissement
                              // Empiler seulement si on est en bas ET qu'on glisse vers le haut
                              if (details.velocity.pixelsPerSecond.dy < -500 &&
                                  _isExpanded &&
                                  _isAtBottom) {
                                setState(() {
                                  _isExpanded = false;
                                  _animationController.reverse();
                                });
                              } else if (details.velocity.pixelsPerSecond.dy >
                                      500 &&
                                  !_isExpanded) {
                                setState(() {
                                  _isExpanded = true;
                                  _animationController.forward();
                                });
                              }
                            },
                            child: AnimatedBuilder(
                              animation: _animation,
                              builder: (context, child) {
                                final stackedHeight =
                                    200.0 + (_reseaux.length - 1) * 20.0;
                                final expandedHeight =
                                    _reseaux.length * (200.0 + 16.0) - 16.0;
                                final animatedHeight = stackedHeight +
                                    (expandedHeight - stackedHeight) *
                                        _animation.value;

                                return Container(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 20),
                                  height: animatedHeight,
                                  child: Stack(
                                    children: List.generate(
                                      _reseaux.length,
                                      (index) => _buildMobileMoneyAccount(
                                        reseau: _reseaux[index],
                                        phoneNumber:
                                            '+225 07 12 34 56 78', // TODO: Récupérer depuis l'API des comptes
                                        index: index,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Bouton pour ajouter un nouveau compte
                        Container(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
                          child: ElevatedButton(
                            onPressed: () {
                              // TODO: Implémenter l'ajout d'un nouveau compte mobile money
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Fonctionnalité d\'ajout de compte à venir'),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                              foregroundColor:
                                  Theme.of(context).colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              elevation: 0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add,
                                  size: 24,
                                  color:
                                      Theme.of(context).colorScheme.onPrimary,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Ajouter un compte',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        Theme.of(context).colorScheme.onPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
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
}
