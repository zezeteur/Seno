import 'package:flutter/material.dart';

/// Couleurs personnalisées de l'application Seno
class AppColors {
  AppColors._();

  // Couleur principale : Jaune clair
  static const Color primary = Color(0xFFFDFE96);
  
  // Couleur secondaire : Bleu
  static const Color secondary = Color(0xFF4D72F7);

  // Variantes de la couleur principale
  static const Color primaryLight = Color(0xFFFEFFC4);
  static const Color primaryDark = Color(0xFFF9FA6E);

  // Variantes de la couleur secondaire
  static const Color secondaryLight = Color(0xFF7A95F9);
  static const Color secondaryDark = Color(0xFF2D5AE5);

  // Couleurs de texte pour contraste
  static const Color textOnPrimary = Color(0xFF1A1A1A);
  static const Color textOnSecondary = Color(0xFFFFFFFF);
  
  // Couleur pour les sous-textes (gris clair)
  static const Color textSecondary = Color(0xFF9E9E9E);

  // Couleurs neutres (mode clair)
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF5F5F5);
  static const Color error = Color(0xFFB00020);
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);

  // Couleurs pour le mode sombre
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF1E1E1E);
  static const Color darkSurfaceVariant = Color(0xFF2C2C2C);
  static const Color darkTextOnPrimary = Color(0xFF1A1A1A);
  static const Color darkTextOnSecondary = Color(0xFFFFFFFF);
  static const Color darkTextOnSurface = Color(0xFFE0E0E0);
  
  // Couleurs primaires adaptées pour le mode sombre
  static const Color darkPrimary = Color(0xFFF9FA6E);
  static const Color darkPrimaryContainer = Color(0xFF6B6D1F);
  
  // Couleurs secondaires adaptées pour le mode sombre
  static const Color darkSecondary = Color(0xFF7A95F9);
  static const Color darkSecondaryContainer = Color(0xFF1E3A8A);
}

