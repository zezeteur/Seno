import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gestionnaire de langue (français / anglais), mémorisé entre les sessions
class LocaleProvider extends ChangeNotifier {
  static const String _prefsKey = 'app_locale';
  static const List<Locale> supportedLocales = [Locale('fr'), Locale('en')];

  /// null = langue du système
  Locale? _locale;

  Locale? get locale => _locale;

  LocaleProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefsKey);
    if (code != null) {
      _locale = Locale(code);
      notifyListeners();
    }
  }

  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, locale.languageCode);
    }
  }

  /// Français si la langue du système n'est pas prise en charge
  static Locale resolve(Locale? deviceLocale, Iterable<Locale> supported) {
    for (final l in supported) {
      if (l.languageCode == deviceLocale?.languageCode) return l;
    }
    return const Locale('fr');
  }
}
