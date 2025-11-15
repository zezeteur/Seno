/// Configuration de l'application Seno (Production)
/// 
/// Ce fichier contient toutes les clés et configurations de l'application.
/// Toutes les valeurs doivent être fournies via des variables d'environnement.
class AppConfig {
  AppConfig._();

  // ============================================
  // SUPABASE CONFIGURATION
  // ============================================
  
  /// URL de votre projet Supabase
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Clé anonyme (anon key) de Supabase
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Clé secrète de service (service role key) de Supabase
  /// ⚠️ Ne jamais exposer cette clé côté client !
  static const String supabaseServiceRoleKey = String.fromEnvironment('SUPABASE_SERVICE_ROLE_KEY');

  // ============================================
  // API CONFIGURATION
  // ============================================
  
  /// URL de base de l'API (si vous avez une API personnalisée)
  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Clé API (si nécessaire)
  static const String apiKey = String.fromEnvironment('API_KEY');

  // ============================================
  // PAYMENT CONFIGURATION
  // ============================================
  
  /// Clé publique de paiement (Stripe, PayPal, etc.)
  static const String paymentPublicKey = String.fromEnvironment('PAYMENT_PUBLIC_KEY');

  /// Clé secrète de paiement (à utiliser uniquement côté serveur)
  static const String paymentSecretKey = String.fromEnvironment('PAYMENT_SECRET_KEY');

  // ============================================
  // APP CONFIGURATION
  // ============================================
  
  /// Nom de l'application
  static const String appName = 'Seno';

  /// Version de l'application
  static const String appVersion = '1.0.0';

  /// Environnement (production uniquement)
  static const String environment = String.fromEnvironment('ENVIRONMENT', defaultValue: 'production');

  /// Mode debug (désactivé en production)
  static const bool isDebugMode = false;

  // ============================================
  // FEATURE FLAGS
  // ============================================
  
  /// Activer/désactiver certaines fonctionnalités
  static const bool enableAnalytics = bool.fromEnvironment('ENABLE_ANALYTICS', defaultValue: true);

  static const bool enableCrashReporting = bool.fromEnvironment('ENABLE_CRASH_REPORTING', defaultValue: true);

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

