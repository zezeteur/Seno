import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Session Supabase (jetons d'accès et de rafraîchissement) dans le Keychain /
/// Keystore au lieu des SharedPreferences en clair.
/// Reprend la session déjà enregistrée par l'ancien stockage : pas de reconnexion.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({required this.persistSessionKey});

  final String persistSessionKey;

  static const _secure = FlutterSecureStorage();
  // Le Keychain iOS survit à la désinstallation : ce marqueur, effacé avec l'app,
  // évite de retrouver une ancienne session après une réinstallation.
  static const _installedFlag = 'seno_secure_session_installed';

  @override
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_installedFlag) ?? false)) {
      await _secure.delete(key: persistSessionKey);
      await prefs.setBool(_installedFlag, true);
    }
    // Migration depuis l'ancien stockage en clair
    final legacy = prefs.getString(persistSessionKey);
    if (legacy != null) {
      await _secure.write(key: persistSessionKey, value: legacy);
      await prefs.remove(persistSessionKey);
    }
  }

  @override
  Future<bool> hasAccessToken() => _secure.containsKey(key: persistSessionKey);

  @override
  Future<String?> accessToken() => _secure.read(key: persistSessionKey);

  @override
  Future<void> removePersistedSession() => _secure.delete(key: persistSessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _secure.write(key: persistSessionKey, value: persistSessionString);
}
