import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';

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
}

