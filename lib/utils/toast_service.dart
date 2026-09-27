import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Service de toast réutilisable dans toute l'application
class ToastService {
  ToastService._();

  static OverlayEntry? _currentOverlay;

  /// Affiche un toast de succès
  static void showSuccess(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _showToast(
      context,
      message: message,
      backgroundColor: AppColors.success,
      icon: Icons.check_circle_outline,
      duration: duration,
    );
  }

  /// Affiche un toast d'erreur
  static void showError(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
  }) {
    _showToast(
      context,
      message: message,
      backgroundColor: AppColors.error,
      icon: Icons.error_outline,
      duration: duration,
    );
  }

  /// Affiche un toast d'information
  static void showInfo(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _showToast(
      context,
      message: message,
      backgroundColor: AppColors.secondary,
      icon: Icons.info_outline,
      duration: duration,
    );
  }

  /// Affiche un toast d'avertissement
  static void showWarning(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _showToast(
      context,
      message: message,
      backgroundColor: AppColors.warning,
      icon: Icons.warning_amber_rounded,
      duration: duration,
    );
  }

  /// Méthode privée pour afficher le toast
  static void _showToast(
    BuildContext context, {
    required String message,
    required Color backgroundColor,
    required IconData icon,
    required Duration duration,
  }) {
    // Fermer le toast précédent s'il existe
    _hideToast();

    // Obtenir le padding en haut pour la SafeArea
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.viewPadding.top;

    // Créer l'overlay entry
    _currentOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: topPadding + 8,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, -50 * (1 - value)),
                child: Opacity(
                  opacity: value,
                  child: child,
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(50),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 22,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // Afficher l'overlay
    Overlay.of(context).insert(_currentOverlay!);

    // Masquer automatiquement après la durée spécifiée
    Future.delayed(duration, () {
      _hideToast();
    });
  }

  /// Masquer le toast actuel
  static void _hideToast() {
    _currentOverlay?.remove();
    _currentOverlay = null;
  }
}
