import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../main.dart';
import '../utils/toast_service.dart';
import '../services/supabase_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

  Future<void> _handleGoogleSignIn() async {
    // Vérifier d'abord si Supabase est configuré
    if (!SupabaseService.isConfigured) {
      ToastService.showError(
        context,
        'Erreur de configuration. Veuillez réessayer plus tard.',
      );
      return;
    }

    // Vérifier si Supabase est initialisé
    if (!SupabaseService.isInitialized) {
      ToastService.showError(
        context,
        'Service non disponible. Veuillez réessayer plus tard.',
      );
      return;
    }

    final supabase = SupabaseService.client;
    if (supabase == null) {
      ToastService.showError(
          context, 'Service non disponible. Veuillez réessayer.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Scopes nécessaires pour l'authentification
      const scopes = ['email', 'profile'];

      final GoogleSignIn googleSignIn = GoogleSignIn.instance;

      ToastService.showInfo(context, 'Connexion à Google...');

      // Tentative d'authentification légère (sans popup si déjà connecté)
      GoogleSignInAccount? googleUser =
          await googleSignIn.attemptLightweightAuthentication();

      // Si l'authentification légère échoue, utiliser authenticate() qui affichera le popup
      googleUser ??= await googleSignIn.authenticate();

      ToastService.showInfo(context, 'Vérification de votre compte...');

      // Obtenir l'autorisation pour les scopes (email, profile)
      final authorization =
          await googleUser.authorizationClient.authorizationForScopes(scopes) ??
              await googleUser.authorizationClient.authorizeScopes(scopes);

      // Obtenir l'ID Token
      final idToken = googleUser.authentication.idToken;

      if (idToken == null) {
        ToastService.showError(
            context, 'Échec de l\'authentification. Veuillez réessayer.');
        throw Exception('No ID Token found.');
      }

      ToastService.showInfo(context, 'Finalisation de la connexion...');

      final response = await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: authorization.accessToken,
      );

      if (response.user != null && mounted) {
        ToastService.showSuccess(context, 'Bienvenue ! Connexion réussie.');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const HomePage(),
          ),
        );
      } else {
        ToastService.showError(
            context, 'Échec de la connexion. Veuillez réessayer.');
        throw Exception('Connexion échouée');
      }
    } catch (e) {
      if (mounted) {
        // Messages d'erreur plus conviviaux selon le type d'erreur
        String errorMessage = 'Erreur de connexion. Veuillez réessayer.';

        if (e.toString().contains('PlatformException')) {
          if (e.toString().contains('URL schemes')) {
            errorMessage = 'Configuration manquante. Contactez le support.';
          } else if (e.toString().contains('sign_in_canceled') ||
              e.toString().contains('canceled')) {
            errorMessage = 'Connexion annulée.';
          } else if (e.toString().contains('network')) {
            errorMessage = 'Problème de connexion. Vérifiez votre réseau.';
          }
        } else if (e.toString().contains('ID Token')) {
          errorMessage = 'Échec de l\'authentification. Réessayez.';
        } else if (e.toString().contains('Invalid API key') ||
            e.toString().contains('401')) {
          errorMessage =
              'Clé API invalide. Vérifiez la configuration Supabase.';
        } else if (e.toString().contains('Supabase') ||
            e.toString().contains('supabase') ||
            e.toString().contains('AuthApiException')) {
          if (e.toString().contains('Invalid API key')) {
            errorMessage = 'Clé API invalide. Vérifiez la configuration.';
          } else {
            errorMessage = 'Service temporairement indisponible. Réessayez.';
          }
        }

        ToastService.showError(context, errorMessage);
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            // Pattern en haut à droite
            Positioned(
              top: 0,
              right: 0,
              child: Image.asset(
                'assets/images/pattern.png',
                width: 120,
                height: 120,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const SizedBox.shrink();
                },
              ),
            ),
            // Contenu principal
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Titre
                    Text(
                      'Connexion',
                      style:
                          Theme.of(context).textTheme.headlineLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Connectez-vous à votre compte',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 100),
                    // Bouton Continuer avec Google
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _handleGoogleSignIn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50),
                        ),
                      ),
                      icon: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Image.asset(
                              'assets/images/google-logo.png',
                              height: 24,
                              width: 24,
                              color: Colors.white,
                              errorBuilder: (context, error, stackTrace) {
                                // Si l'image Google n'existe pas, utiliser une icône
                                return HugeIcon(
                                  icon: HugeIcons.strokeRoundedGoogle,
                                  size: 24,
                                  color: Colors.white,
                                );
                              },
                            ),
                      label: const Text(
                        'Continuer avec Google',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
