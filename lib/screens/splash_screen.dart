import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../theme/app_colors.dart';
import '../main.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final Random _random = Random();
  late List<IconPosition> _iconPositions;

  // Liste des icônes financières (utilisant les icônes Material standard)
  static final List<IconData> _financeIcons = [
    Icons.account_balance,
    Icons.account_balance_wallet,
    Icons.credit_card,
    Icons.payment,
    Icons.attach_money,
    Icons.monetization_on,
    Icons.savings,
    Icons.account_circle,
    Icons.wallet,
    Icons.receipt,
    Icons.point_of_sale,
    Icons.money_off,
    Icons.currency_exchange,
    Icons.trending_up,
    Icons.trending_down,
    Icons.show_chart,
    Icons.bar_chart,
    Icons.pie_chart,
    Icons.account_tree,
    Icons.business,
  ];

  @override
  void initState() {
    super.initState();
    _generateIconPositions();
    _initializeApp();
  }

  bool _hasCollision(IconPosition newPos, List<IconPosition> existingPositions) {
    // Supposons une taille d'écran minimale pour le calcul (400px)
    // Cela permet de convertir les pixels en pourcentage approximatif
    const double minScreenWidth = 400.0;
    
    // Zone d'exclusion au centre pour le logo (environ 30% de l'écran)
    const double centerX = 0.5;
    const double centerY = 0.5;
    const double logoRadius = 0.15; // 15% de l'écran
    
    // Vérifier si la nouvelle position est trop proche du centre (logo)
    final double distanceToCenter = sqrt(
      pow(newPos.left - centerX, 2) + pow(newPos.top - centerY, 2),
    );
    final double newSizePercent = newPos.size / minScreenWidth;
    if (distanceToCenter < logoRadius + newSizePercent / 2) {
      return true; // Trop proche du logo
    }
    
    // Vérifier les collisions avec les autres icônes
    for (var existingPos in existingPositions) {
      // Calculer la distance entre les centres des icônes (en pourcentage)
      final double deltaX = newPos.left - existingPos.left;
      final double deltaY = newPos.top - existingPos.top;
      final double distancePercent = sqrt(deltaX * deltaX + deltaY * deltaY);
      
      // Convertir les tailles en pourcentage de l'écran
      final double existingSizePercent = existingPos.size / minScreenWidth;
      
      // Vérifier si les icônes sont identiques
      final bool isSameIcon = newPos.icon.codePoint == existingPos.icon.codePoint;
      
      // Distance minimale requise
      // Si les icônes sont identiques, augmenter la distance minimale (8% au lieu de 2%)
      final double baseMargin = isSameIcon ? 0.08 : 0.02;
      final double minDistancePercent = 
          (newSizePercent + existingSizePercent) / 2 + baseMargin;
      
      if (distancePercent < minDistancePercent) {
        return true; // Collision détectée
      }
    }
    return false; // Pas de collision
  }

  void _generateIconPositions() {
    _iconPositions = [];
    const int numberOfIcons = 15;
    
    // Créer une grille pour distribuer uniformément les icônes
    // On divise l'écran en zones (par exemple 4x4 = 16 zones)
    const int gridCols = 4;
    const int gridRows = 4;
    
    // Créer une liste de toutes les zones disponibles (col, row)
    final List<({int col, int row})> availableZones = [];
    for (int row = 0; row < gridRows; row++) {
      for (int col = 0; col < gridCols; col++) {
        availableZones.add((col: col, row: row));
      }
    }
    
    // Mélanger les zones pour une distribution aléatoire
    availableZones.shuffle(_random);
    
    // Zone d'exclusion au centre pour le logo
    const double centerX = 0.5;
    const double centerY = 0.5;
    const double logoRadius = 0.15;
    
    int iconCount = 0;
    for (final zone in availableZones) {
      if (iconCount >= numberOfIcons) break;
      
      // Calculer la position de la zone
      final double zoneWidth = 1.0 / gridCols;
      final double zoneHeight = 1.0 / gridRows;
      
      final double zoneLeft = zone.col * zoneWidth;
      final double zoneTop = zone.row * zoneHeight;
      
      // Position aléatoire dans la zone (avec marge pour éviter les bords)
      final double margin = 0.1; // 10% de marge dans chaque zone
      final double left = zoneLeft + margin * zoneWidth + 
          _random.nextDouble() * zoneWidth * (1 - 2 * margin);
      final double top = zoneTop + margin * zoneHeight + 
          _random.nextDouble() * zoneHeight * (1 - 2 * margin);
      
      // Vérifier si la position est trop proche du centre (logo)
      final double distanceToCenter = sqrt(
        pow(left - centerX, 2) + pow(top - centerY, 2),
      );
      
      if (distanceToCenter < logoRadius) {
        continue; // Ignorer cette zone si trop proche du logo
      }
      
      // Créer l'icône dans cette zone
      final iconPosition = IconPosition(
        icon: _financeIcons[_random.nextInt(_financeIcons.length)],
        top: top,
        left: left,
        size: 20 + _random.nextDouble() * 30, // Taille entre 20 et 50
        opacity: 0.1 + _random.nextDouble() * 0.2, // Opacité entre 0.1 et 0.3
        rotation: _random.nextDouble() * 360, // Rotation aléatoire
      );
      
      // Vérifier les collisions avec les icônes déjà placées
      if (!_hasCollision(iconPosition, _iconPositions)) {
        _iconPositions.add(iconPosition);
        iconCount++;
      }
    }
    
    // Si on n'a pas assez d'icônes, en ajouter de manière aléatoire
    while (_iconPositions.length < numberOfIcons) {
      final candidate = IconPosition(
        icon: _financeIcons[_random.nextInt(_financeIcons.length)],
        top: _random.nextDouble() * 0.8,
        left: _random.nextDouble() * 0.8,
        size: 20 + _random.nextDouble() * 30,
        opacity: 0.1 + _random.nextDouble() * 0.2,
        rotation: _random.nextDouble() * 360,
      );
      
      if (!_hasCollision(candidate, _iconPositions)) {
        _iconPositions.add(candidate);
      }
    }
  }

  Future<void> _initializeApp() async {
    // Initialiser Supabase si configuré
    if (AppConfig.isSupabaseConfigured()) {
      try {
        // Supabase sera initialisé via le client directement
        // Le client peut être créé avec: SupabaseClient(url, anonKey)
        debugPrint('Supabase configuré: ${AppConfig.supabaseUrl}');
      } catch (e) {
        debugPrint('Erreur lors de l\'initialisation de Supabase: $e');
      }
    }

    // Attendre un délai minimum pour l'affichage de la splash screen
    await Future.delayed(const Duration(seconds: 2));

    // Naviguer vers la page d'accueil
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const HomePage(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Stack(
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
              errorBuilder: (context, error, stackTrace) {
                // Si l'image n'est pas trouvée, ne rien afficher
                return const SizedBox.shrink();
              },
            ),
          ),
          // Icônes financières aléatoires en arrière-plan
          ..._iconPositions.map((iconPos) {
            return Positioned(
              top: iconPos.top * screenSize.height,
              left: iconPos.left * screenSize.width,
              child: Transform.rotate(
                angle: iconPos.rotation * pi / 180,
                child: Opacity(
                  opacity: iconPos.opacity,
                  child: Icon(
                    iconPos.icon,
                    size: iconPos.size,
                    color: Colors.black,
                  ),
                ),
              ),
            );
          }),
          // Contenu centré
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo centré
                Image.asset(
                  'assets/images/seno-logo.png',
                  width: 200,
                  height: 200,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    // Si l'image n'est pas trouvée, afficher un placeholder
                    return const Icon(
                      Icons.image_not_supported,
                      size: 100,
                      color: AppColors.secondary,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Classe pour stocker les informations de position des icônes
class IconPosition {
  final IconData icon;
  final double top;
  final double left;
  final double size;
  final double opacity;
  final double rotation;

  IconPosition({
    required this.icon,
    required this.top,
    required this.left,
    required this.size,
    required this.opacity,
    required this.rotation,
  });
}

