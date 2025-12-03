import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../models/reseau.dart';

/// Service global pour gérer l'instance Supabase
class SupabaseService {
  SupabaseService._();

  /// Obtenir le client Supabase
  static SupabaseClient? get client {
    try {
      return Supabase.instance.client;
    } catch (e) {
      return null;
    }
  }

  /// Vérifier si Supabase est initialisé
  static bool get isInitialized {
    try {
      Supabase.instance.client;
      return true;
    } catch (e) {
      // Supabase n'est pas initialisé (exception levée si non initialisé)
      return false;
    }
  }

  /// Vérifier si Supabase est configuré
  static bool get isConfigured => AppConfig.isSupabaseConfigured();

  /// Récupérer la liste des réseaux
  static Future<List<Reseau>> getReseaux() async {
    try {
      // Construction de l'URL complète de l'Edge Function
      final url = '${AppConfig.supabaseUrl}/functions/v1/list-reseaux';

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${AppConfig.supabaseAnonKey}',
          'apikey': AppConfig.supabaseAnonKey,
        },
      );

      if (response.statusCode != 200) {
        throw Exception(
            'Erreur lors de la récupération des réseaux: ${response.statusCode} - ${response.body}');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final reseauxList = data['reseaux'] as List<dynamic>;

      return reseauxList
          .map((json) => Reseau.fromJson(json as Map<String, dynamic>))
          .where((reseau) =>
              reseau.statut) // Filtrer uniquement les réseaux actifs
          .toList();
    } catch (e) {
      throw Exception('Erreur lors de la récupération des réseaux: $e');
    }
  }
}
