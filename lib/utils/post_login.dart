import 'package:flutter/material.dart';
import '../main.dart';
import '../screens/register_screen.dart';
import '../screens/wallet_screen.dart';
import '../services/supabase_service.dart';

/// Redirige un utilisateur connecté vers la bonne page :
/// inscription si le profil manque, portefeuille s'il n'a aucun compte,
/// sinon l'accueil. Vide la pile de navigation.
Future<void> navigateAfterLogin(BuildContext context) async {
  Widget destination = const HomePage();
  try {
    if (!await SupabaseService.hasProfile()) {
      destination = const RegisterScreen();
    } else {
      final comptes = await SupabaseService.getComptes();
      if (comptes.isEmpty) destination = const WalletScreen();
    }
  } catch (_) {
    // En cas d'erreur, aller à la page d'accueil
  }
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => destination),
    (_) => false,
  );
}
