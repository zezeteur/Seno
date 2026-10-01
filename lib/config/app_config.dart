/// Ce fichier contient toutes les clés et configurations de l'application.
/// Toutes les valeurs sont définies directement dans ce fichier.
class AppConfig {
  AppConfig._();

  // ============================================
  // SUPABASE CONFIGURATION
  // ============================================

  // Valeurs lues dans .env à la compilation :
  //   flutter run --dart-define-from-file=.env
  // Sans ce flag, les valeurs par défaut ci-dessous sont utilisées.

  /// URL de votre projet Supabase (ou votre nom de domaine)
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://jbgnipiavizocgabelcn.supabase.co',
  );

  /// Clé anonyme (anon key) de Supabase
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpiZ25pcGlhdml6b2NnYWJlbGNuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA0NDE2NzcsImV4cCI6MjEwNjAxNzY3N30.TPZn92OFCwztIWwAOzXnJ5hGn32CcLGRCsseEg2X0Qw',
  );

  /// Clé secrète de service (service role key) de Supabase
  /// ⚠️ Ne jamais exposer cette clé côté client !
  static const String supabaseServiceRoleKey = '';

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
