/// Ce fichier contient toutes les clés et configurations de l'application.
/// Toutes les valeurs sont définies directement dans ce fichier.
class AppConfig {
  AppConfig._();

  // ============================================
  // SUPABASE CONFIGURATION
  // ============================================

  /// URL de votre projet Supabase
  static const String supabaseUrl = 'https://klgtxkmjagrydvxjulnn.supabase.co';

  /// Clé anonyme (anon key) de Supabase
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtsZ3R4a21qYWdyeWR2eGp1bG5uIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjMxNDM4MzYsImV4cCI6MjA3ODcxOTgzNn0.U1P0I9NJDwkEBnhYbEFtcKUkZ5FbFFaTmV0k_IIp0ec';

  /// Clé secrète de service (service role key) de Supabase
  /// ⚠️ Ne jamais exposer cette clé côté client !
  static const String supabaseServiceRoleKey = '';

  // ============================================
  // GOOGLE OAUTH CONFIGURATION
  // ============================================

  /// Web Client ID pour Google OAuth (obtenu depuis Google Cloud Console)
  /// Remplacez par votre Web Client ID depuis Google Cloud Console
  static const String googleWebClientId =
      '19573161667-nncavbtsbefc2mtlrjgdqgfdldi7a7eg.apps.googleusercontent.com';

  /// iOS Client ID pour Google OAuth (obtenu depuis Google Cloud Console)
  /// Remplacez par votre iOS Client ID depuis Google Cloud Console
  static const String googleIosClientId =
      '19573161667-ujpk9oji3dc40gra5buspf8v5q33ihuf.apps.googleusercontent.com';

  // ============================================
  // API CONFIGURATION
  // ============================================

  /// URL de base de l'API (si vous avez une API personnalisée)
  static const String apiBaseUrl = '';

  /// Clé API (si nécessaire)
  static const String apiKey = '';

  // ============================================
  // PAYMENT CONFIGURATION
  // ============================================

  /// Clé publique de paiement (Stripe, PayPal, etc.)
  static const String paymentPublicKey = '';

  /// Clé secrète de paiement (à utiliser uniquement côté serveur)
  static const String paymentSecretKey = '';

  // ============================================
  // APP CONFIGURATION
  // ============================================

  /// Nom de l'application
  static const String appName = 'Seno';

  /// Version de l'application
  static const String appVersion = '1.0.0';

  /// Environnement (production uniquement)
  static const String environment = 'production';

  /// Mode debug (désactivé en production)
  static const bool isDebugMode = false;

  // ============================================
  // FEATURE FLAGS
  // ============================================

  /// Activer/désactiver certaines fonctionnalités
  static const bool enableAnalytics = true;

  static const bool enableCrashReporting = true;

  // ============================================
  // VALIDATION METHODS
  // ============================================

  /// Vérifie si la configuration Supabase est valide
  static bool isSupabaseConfigured() {
    return supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
  }

  /// Vérifie si l'application est en mode production
  static bool isProduction() {
    return environment == 'production';
  }
}
