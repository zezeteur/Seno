import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Gestionnaire de thème pour basculer entre mode clair et sombre
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  /// Mode de thème actuel
  ThemeMode get themeMode => _themeMode;

  /// Vérifie si le mode sombre est activé (en tenant compte du thème système)
  bool get isDarkMode {
    if (_themeMode == ThemeMode.system) {
      // Utiliser MediaQuery pour détecter le thème système
      // Note: Cette méthode nécessite un BuildContext, donc on utilisera
      // plutôt Brightness.of(context) dans les widgets
      return false; // Valeur par défaut, sera déterminée par le système
    }
    return _themeMode == ThemeMode.dark;
  }

  /// Obtenir le thème actuel
  ThemeData get currentTheme {
    return _themeMode == ThemeMode.dark
        ? AppTheme.darkTheme
        : AppTheme.lightTheme;
  }

  /// Basculer entre les modes : system -> light -> dark -> system
  void toggleTheme() {
    switch (_themeMode) {
      case ThemeMode.system:
        _themeMode = ThemeMode.light;
        break;
      case ThemeMode.light:
        _themeMode = ThemeMode.dark;
        break;
      case ThemeMode.dark:
        _themeMode = ThemeMode.system;
        break;
    }
    notifyListeners();
  }

  /// Définir le mode de thème
  void setThemeMode(ThemeMode mode) {
    if (_themeMode != mode) {
      _themeMode = mode;
      notifyListeners();
    }
  }

  /// Activer le mode sombre
  void enableDarkMode() {
    setThemeMode(ThemeMode.dark);
  }

  /// Activer le mode clair
  void enableLightMode() {
    setThemeMode(ThemeMode.light);
  }
}

