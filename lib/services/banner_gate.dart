import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../screens/banner_details_screen.dart';
import 'supabase_service.dart';

/// Bannière « accès bloqué » du back-office : page plein écran sans fermeture,
/// affichée avant l'accueil et dès qu'un blocage est publié.
class BannerGate {
  BannerGate._();

  /// Id de la bannière bloquante affichée (une seule page à la fois)
  static String? _shownId;

  /// Ciblage par version : toutes, une version précise, ou les versions inférieures
  static bool matchesVersion(Map<String, dynamic> b, String current) {
    final cible = b['version_cible'] as String?;
    if (cible == null) return true;
    List<int> parse(String v) {
      final parts = v.split('+').first.split('.').map(int.tryParse).toList();
      return [for (var i = 0; i < 3; i++) i < parts.length ? parts[i] ?? 0 : 0];
    }

    final a = parse(current), c = parse(cible);
    var cmp = 0;
    for (var i = 0; i < 3 && cmp == 0; i++) {
      cmp = a[i].compareTo(c[i]);
    }
    return b['version_mode'] == 'inferieure' ? cmp < 0 : cmp == 0;
  }

  /// Bannière bloquante en ligne pour cet utilisateur et cette version (null sinon ou hors ligne)
  static Future<Map<String, dynamic>?> fetchBlocking() async {
    final client = SupabaseService.client;
    if (client?.auth.currentUser == null) return null;
    try {
      final rows = await client!
          .from('app_banners')
          .select(
              'id, titre, sous_titre, image_url, niveau, lien, page_app, bouton_texte, bloquer_acces, version_cible, version_mode')
          .eq('bloquer_acces', true)
          .order('created_at', ascending: false)
          .limit(10);
      final version = (await PackageInfo.fromPlatform()).version;
      return List<Map<String, dynamic>>.from(rows)
          .where((b) => matchesVersion(b, version))
          .firstOrNull;
    } catch (_) {
      return null;
    }
  }

  /// Affiche la page bloquante si besoin et attend sa fermeture (fin du blocage)
  static Future<void> showIfBlocked(NavigatorState navigator) async {
    if (_shownId != null) return;
    final b = await fetchBlocking();
    if (b == null || _shownId != null) return;
    _shownId = b['id'] as String;
    try {
      await navigator.push(BannerDetailsScreen.route(b));
    } finally {
      _shownId = null;
    }
  }
}
