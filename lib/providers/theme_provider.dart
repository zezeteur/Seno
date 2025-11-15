import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Gestionnaire de thème pour basculer entre mode clair et sombre
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;

  /// Mode de thème actuel
  ThemeMode get themeMode => _themeMode;

  /// Vérifie si le mode sombre est activé
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  /// Obtenir le thème actuel
  ThemeData get currentTheme {
    return _themeMode == ThemeMode.dark
        ? AppTheme.darkTheme
        : AppTheme.lightTheme;
  }

  /// Basculer entre mode clair et sombre
  void toggleTheme() {
    _themeMode = _themeMode == ThemeMode.light
        ? ThemeMode.dark
        : ThemeMode.light;
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

