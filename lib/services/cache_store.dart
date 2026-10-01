import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cache local chiffré des lectures réseau (réseau d'abord, copie locale en secours).
/// Stockage : boîte Hive chiffrée AES-256, clé gardée dans le Keychain / Keystore.
/// Les clés sont préfixées par l'utilisateur : un autre compte ne voit rien.
class CacheStore {
  CacheStore._();

  static const _boxName = 'seno_cache';
  static const _keyName = 'seno_cache_key';
  static const _secure = FlutterSecureStorage();

  /// true quand l'écran affiche des données du cache faute de réseau
  static final offline = ValueNotifier<bool>(false);

  /// null si le stockage chiffré est indisponible : l'app marche alors sans cache
  static Box<String>? _box;

  /// À appeler une fois au démarrage, avant runApp
  static Future<void> init() async {
    try {
      await Hive.initFlutter();
      final cipher = HiveAesCipher(await _encryptionKey());
      try {
        _box = await Hive.openBox<String>(_boxName, encryptionCipher: cipher);
      } catch (_) {
        // Boîte illisible (clé perdue, fichier corrompu) : on repart de zéro
        await Hive.deleteBoxFromDisk(_boxName);
        _box = await Hive.openBox<String>(_boxName, encryptionCipher: cipher);
      }
    } catch (e) {
      debugPrint('[CacheStore] cache chiffré indisponible : $e');
      _box = null;
    }
    await _removeLegacyCache();
  }

  static Future<List<int>> _encryptionKey() async {
    final stored = await _secure.read(key: _keyName);
    if (stored != null) return base64Url.decode(stored);
    final key = Hive.generateSecureKey();
    await _secure.write(key: _keyName, value: base64UrlEncode(key));
    return key;
  }

  /// Ancienne version : cache en clair dans shared_preferences, à supprimer
  static Future<void> _removeLegacyCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys().where((k) => k.startsWith('cache:'))) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }

  static String _key(String? userId, String name) =>
      '${userId ?? 'public'}:$name';

  /// Exécute [fetch] ; succès → copie enregistrée. Échec → dernière copie,
  /// ou l'erreur d'origine s'il n'y en a pas.
  static Future<T> cached<T>({
    required String name,
    required String? userId,
    required Future<T> Function() fetch,
    required Object? Function(T value) encode,
    required T Function(Object? json) decode,
  }) async {
    final key = _key(userId, name);
    try {
      final value = await fetch();
      offline.value = false;
      try {
        await _box?.put(key, jsonEncode(encode(value)));
      } catch (_) {
        // Écriture du cache impossible : la donnée fraîche reste utilisable
      }
      return value;
    } catch (_) {
      final raw = _box?.get(key);
      if (raw == null) rethrow;
      offline.value = true;
      return decode(jsonDecode(raw));
    }
  }

  /// Dernière copie enregistrée, sans appel réseau (null si absente)
  static T? peek<T>({
    required String name,
    required String? userId,
    required T Function(Object? json) decode,
  }) {
    final raw = _box?.get(_key(userId, name));
    if (raw == null) return null;
    try {
      return decode(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  /// Enregistre une donnée locale (hors réseau), ex. les destinataires récents
  static Future<void> put(String? userId, String name, Object? json) async {
    try {
      await _box?.put(_key(userId, name), jsonEncode(json));
    } catch (_) {
      // Écriture impossible : la donnée reste en mémoire pour cet écran
    }
  }

  /// Supprime une entrée (après une modification, pour éviter une copie périmée)
  static Future<void> remove(String? userId, String name) async {
    await _box?.delete(_key(userId, name));
  }

  /// Déconnexion : efface toutes les données mises en cache
  static Future<void> clear() async {
    await _box?.clear();
    offline.value = false;
  }
}
