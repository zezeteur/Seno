import 'services/supabase_service.dart';
import 'services/cache_store.dart';
import 'services/push_service.dart';
import 'services/payment_return_service.dart';
import 'services/secure_session_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'providers/theme_provider.dart';
import 'providers/locale_provider.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'config/app_config.dart';
import 'widgets/app_lock_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Verrouiller l'orientation en mode portrait uniquement
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Cache local chiffré (données affichées hors ligne)
  await CacheStore.init();

  // Initialiser Supabase
  if (AppConfig.isSupabaseConfigured()) {
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
        // Session chiffrée (Keychain / Keystore), même clé que le stockage par défaut
        authOptions: FlutterAuthClientOptions(
          localStorage: SecureSessionStorage(
            persistSessionKey:
                'sb-${Uri.parse(AppConfig.supabaseUrl).host.split('.').first}-auth-token',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Erreur lors de l\'initialisation de Supabase: $e');
    }
  }

  // Notifications push (token FCM enregistré à la connexion)
  if (SupabaseService.isInitialized) await PushService.init();

  // Retour de la page de paiement : rouvre l'envoi concerné
  PaymentReturnService.init(MyApp.navigatorKey);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static final navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: Consumer2<ThemeProvider, LocaleProvider>(
        builder: (context, themeProvider, localeProvider, _) {
          return MaterialApp(
            title: 'Seno',
            navigatorKey: navigatorKey,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            locale: localeProvider.locale,
            supportedLocales: LocaleProvider.supportedLocales,
            localeResolutionCallback: LocaleProvider.resolve,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const SplashScreen(),
            builder: (context, child) {
              // Préserver viewPadding pour permettre SafeArea de fonctionner
              // mais mettre padding à zéro pour enlever le SafeArea par défaut
              final originalMediaQuery = MediaQuery.of(context);
              return MediaQuery(
                data: originalMediaQuery.copyWith(
                  padding: EdgeInsets.zero,
                  // Garder viewPadding pour que SafeArea fonctionne quand nécessaire
                  viewPadding: originalMediaQuery.viewPadding,
                ),
                // Verrouillage par code d'accès au-dessus de toutes les pages
                child: AppLockGate(navigatorKey: navigatorKey, child: child!),
              );
            },
          );
        },
      ),
    );
  }
}

// Alias pour la compatibilité avec login_screen.dart
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const HomeScreen();
  }
}
