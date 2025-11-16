import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'providers/theme_provider.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'config/app_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Verrouiller l'orientation en mode portrait uniquement
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialiser Supabase
  if (AppConfig.isSupabaseConfigured()) {
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
      );
    } catch (e) {
      debugPrint('Erreur lors de l\'initialisation de Supabase: $e');
    }
  }

  // Initialiser Google Sign In avec les client IDs
  final GoogleSignIn googleSignIn = GoogleSignIn.instance;
  if (AppConfig.googleWebClientId.isNotEmpty &&
      AppConfig.googleIosClientId.isNotEmpty) {
    await googleSignIn.initialize(
      clientId: AppConfig.googleIosClientId,
      serverClientId: AppConfig.googleWebClientId,
    );
  } else {
    // Initialisation sans client IDs (pour le développement)
    await googleSignIn.initialize();
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'Seno',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const SplashScreen(),
            // Gérer les deep links OAuth
            onGenerateRoute: (settings) {
              if (settings.name == '/login-callback') {
                // Gérer le callback OAuth
                return MaterialPageRoute(
                  builder: (_) => const LoginScreen(),
                );
              }
              return null;
            },
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
                child: child!,
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
