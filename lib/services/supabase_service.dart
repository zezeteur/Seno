import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../models/reseau.dart';
import '../models/compte.dart';
import '../utils/toast_service.dart';
import '../widgets/app_lock_gate.dart';

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

  // ============================================
  // AUTHENTIFICATION PAR TÉLÉPHONE (OTP 4 chiffres)
  // ============================================

  /// Envoie le code SMS à 4 chiffres.
  /// Compte existant avec code d'accès : aucun SMS sans [ticket] —
  /// renvoie alors `requiresAccessCode` pour passer d'abord par le code d'accès.
  static Future<SendOtpResult> sendOtp(String phone, {String? ticket}) async {
    final data = await _invokeAuth('send-otp', {
      'phone': phone,
      if (ticket != null) 'ticket': ticket,
    });
    return SendOtpResult(
      requiresAccessCode: data['requires_access_code'] == true,
      debugCode: data['debug_code'] as String?,
    );
  }

  /// Vérifie le code d'accès ; si correct, le serveur envoie l'OTP par SMS.
  /// Renvoie le ticket à joindre à [verifyOtp].
  static Future<String> verifyAccessCode(String phone, String code) async {
    final data =
        await _invokeAuth('verify-access-code', {'phone': phone, 'code': code});
    return data['ticket'] as String;
  }

  /// Vérifie le code SMS, ouvre la session et indique si c'est une inscription
  static Future<bool> verifyOtp(String phone, String code,
      {String? ticket}) async {
    final data = await _invokeAuth('verify-otp', {
      'phone': phone,
      'code': code,
      if (ticket != null) 'ticket': ticket,
    });
    await client!.auth.setSession(data['refresh_token'] as String);
    return data['is_new_user'] as bool? ?? false;
  }

  /// Crée le code d'accès de l'utilisateur connecté
  static Future<void> setAccessCode(String code) async {
    await _invokeAuth('set-access-code', {'code': code});
    AppLockGate.hasAccessCode.value = true;
  }

  /// Déverrouille l'app avec le code d'accès (utilisateur déjà connecté)
  static Future<void> unlockApp(String code) async {
    await _invokeAuth('unlock-app', {'code': code});
  }

  /// Blocage du code d'accès de l'utilisateur connecté
  static Future<AccessLockStatus> getAccessLockStatus() async {
    final rows = await client!.rpc('access_lock_status') as List;
    if (rows.isEmpty) return const AccessLockStatus();
    final row = Map<String, dynamic>.from(rows.first as Map);
    final until = row['locked_until'] as String?;
    return AccessLockStatus(
      lockedUntil: until == null ? null : DateTime.parse(until).toLocal(),
      permanentlyLocked: row['permanently_locked'] == true,
    );
  }

  /// Code d'accès oublié, étape 1 : date de naissance → envoi d'un OTP.
  /// Renvoie le jeton de réinitialisation et le numéro qui reçoit le SMS.
  static Future<({String token, String phone})> startAccessCodeReset(
      DateTime birthDate) async {
    final d = birthDate;
    final res = await _invokeAuth('reset-access-code', {
      'action': 'start',
      'birth_date': '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
    });
    return (token: res['token'] as String, phone: res['phone'] as String);
  }

  static Future<void> resendAccessCodeResetOtp(String token) async {
    await _invokeAuth(
        'reset-access-code', {'action': 'resend', 'token': token});
  }

  static Future<void> verifyAccessCodeResetOtp(String token, String otp) async {
    await _invokeAuth('reset-access-code',
        {'action': 'verify_otp', 'token': token, 'otp': otp});
  }

  static Future<void> setNewAccessCode(String token, String code) async {
    await _invokeAuth('reset-access-code',
        {'action': 'set_code', 'token': token, 'code': code});
  }

  /// Pseudo et photo de l'utilisateur connecté (écran de verrouillage)
  static Future<({String? pseudo, String? avatarUrl})> getLockProfile() async {
    final supabase = client;
    final userId = supabase?.auth.currentUser?.id;
    if (supabase == null || userId == null) {
      return (pseudo: null, avatarUrl: null);
    }
    final row = await supabase
        .from('profiles')
        .select('pseudo, avatar_url')
        .eq('id', userId)
        .maybeSingle();
    return (
      pseudo: row?['pseudo'] as String?,
      avatarUrl: row?['avatar_url'] as String?,
    );
  }

  /// Coordonnées du support (table support_contacts)
  static Future<SupportContacts> getSupportContacts() async {
    final supabase = client;
    if (supabase == null) throw const AuthOtpException('service_unavailable');
    final row = await supabase
        .from('support_contacts')
        .select('whatsapp, phone, email')
        .eq('id', 1)
        .maybeSingle();
    String? clean(Object? v) =>
        v is String && v.trim().isNotEmpty ? v.trim() : null;
    return SupportContacts(
      whatsapp: clean(row?['whatsapp']),
      phone: clean(row?['phone']),
      email: clean(row?['email']),
    );
  }

  /// L'utilisateur connecté a-t-il déjà un code d'accès ?
  static Future<bool> hasAccessCode() async {
    final result = await client!.rpc('has_access_code');
    return result == true;
  }

  static Future<Map<String, dynamic>> _invokeAuth(
      String function, Map<String, dynamic> body) async {
    final supabase = client;
    if (supabase == null) throw const AuthOtpException('service_unavailable');
    try {
      final res = await supabase.functions.invoke(function, body: body);
      return Map<String, dynamic>.from(res.data as Map);
    } on FunctionException catch (e) {
      final details = e.details;
      final code = details is Map ? details['error'] as String? : null;
      throw AuthOtpException(
        code ?? 'server_error',
        remaining: details is Map ? details['remaining'] as int? : null,
        retryIn: details is Map ? details['retry_in'] as int? : null,
      );
    }
  }

  /// Le profil de l'utilisateur connecté existe-t-il ?
  static Future<bool> hasProfile() async {
    final supabase = client;
    final userId = supabase?.auth.currentUser?.id;
    if (supabase == null || userId == null) return false;
    final row = await supabase
        .from('profiles')
        .select('id')
        .eq('id', userId)
        .maybeSingle();
    return row != null;
  }

  /// Crée le profil à l'inscription
  static Future<void> createProfile({
    required String nom,
    required String prenoms,
    required String pseudo,
    required DateTime dateNaissance,
  }) async {
    final supabase = client!;
    final user = supabase.auth.currentUser!;
    await supabase.from('profiles').insert({
      'id': user.id,
      'phone': user.phone != null && user.phone!.isNotEmpty
          ? (user.phone!.startsWith('+') ? user.phone : '+${user.phone}')
          : '',
      'nom': nom,
      'prenoms': prenoms,
      'pseudo': pseudo,
      'date_naissance': dateNaissance.toIso8601String().substring(0, 10),
    });
  }

  /// Vérifie qu'aucun profil n'utilise déjà ce pseudo
  static Future<bool> isPseudoAvailable(String pseudo) async {
    final result =
        await client!.rpc('is_pseudo_available', params: {'p_pseudo': pseudo});
    return result == true;
  }

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

  /// Récupérer la liste des comptes de l'utilisateur connecté
  static Future<List<Compte>> getComptes() async {
    try {
      final client = SupabaseService.client;
      if (client == null) {
        throw Exception('Supabase client non initialisé');
      }

      final session = client.auth.currentSession;
      if (session == null) {
        throw Exception('Utilisateur non connecté');
      }

      // Construction de l'URL pour récupérer les comptes
      final url = '${AppConfig.supabaseUrl}/rest/v1/comptes';

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'apikey': AppConfig.supabaseAnonKey,
          'Content-Type': 'application/json',
          'Prefer': 'return=representation',
        },
      );

      if (response.statusCode != 200) {
        throw Exception(
            'Erreur lors de la récupération des comptes: ${response.statusCode} - ${response.body}');
      }

      final comptesList = json.decode(response.body) as List<dynamic>;

      return comptesList
          .map((json) => Compte.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Erreur lors de la récupération des comptes: $e');
    }
  }

  /// Récupérer le compte par défaut de l'utilisateur connecté
  static Future<Compte?> getDefaultCompte() async {
    try {
      final client = SupabaseService.client;
      if (client == null) {
        throw Exception('Supabase client non initialisé');
      }

      final session = client.auth.currentSession;
      if (session == null) {
        throw Exception('Utilisateur non connecté');
      }

      // Construction de l'URL de l'Edge Function
      final url = '${AppConfig.supabaseUrl}/functions/v1/get-default-compte';

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 404) {
        // Aucun compte par défaut trouvé
        return null;
      }

      if (response.statusCode != 200) {
        throw Exception(
            'Erreur lors de la récupération du compte par défaut: ${response.statusCode} - ${response.body}');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final compteData = data['compte'] as Map<String, dynamic>?;

      if (compteData == null) {
        return null;
      }

      return Compte.fromJson(compteData);
    } catch (e) {
      throw Exception(
          'Erreur lors de la récupération du compte par défaut: $e');
    }
  }

  /// Définir un compte comme compte par défaut
  static Future<void> setDefaultCompte({
    required String compteId,
    BuildContext? context,
  }) async {
    try {
      final client = SupabaseService.client;
      if (client == null) {
        throw Exception('Supabase client non initialisé');
      }

      // Obtenir la session actuelle et rafraîchir si nécessaire
      var session = client.auth.currentSession;
      if (session == null) {
        throw Exception('Utilisateur non connecté');
      }

      // Vérifier si le token est expiré et le rafraîchir si nécessaire
      if (session.isExpired) {
        final authResponse = await client.auth.refreshSession();
        session = authResponse.session;
        if (session == null) {
          throw Exception('Impossible de rafraîchir la session');
        }
      }

      // Vérifier que nous avons bien le JWT de l'utilisateur (USER_JWT, pas service_role key)
      final userJwt = session.accessToken;
      if (userJwt.isEmpty) {
        throw Exception('Token utilisateur non disponible');
      }

      // Construction de l'URL de l'Edge Function
      final url = '${AppConfig.supabaseUrl}/functions/v1/set-default-compte';

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $userJwt',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'default_compte_id': compteId,
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(
            'Erreur lors de la définition du compte par défaut: ${response.statusCode} - ${response.body}');
      }

      // La réponse contient les informations mises à jour
      final responseData = json.decode(response.body) as Map<String, dynamic>;

      // Vérifier que la réponse est valide
      if (!responseData.containsKey('status') ||
          responseData['status'] != 'ok') {
        throw Exception(
            'Format de réponse invalide ou erreur: ${response.body}');
      }

      // Extraire le compte_par_defaut depuis data.data
      final data = responseData['data'] as Map<String, dynamic>?;
      if (data == null || !data.containsKey('compte_par_defaut')) {
        throw Exception('Format de réponse invalide: ${response.body}');
      }

      // Afficher un toast de succès
      if (context != null && context.mounted) {
        ToastService.showInfo(
          context,
          'Compte défini comme compte par défaut',
        );
      }
    } catch (e) {
      // Afficher un toast d'erreur
      if (context != null && context.mounted) {
        ToastService.showError(
          context,
          'Erreur: ${e.toString()}',
        );
      }
      throw Exception('Erreur lors de la définition du compte par défaut: $e');
    }
  }

  /// Créer un nouveau compte
  static Future<Compte> createCompte({
    required String numero,
    required String idReseau,
    required bool setAsDefault,
  }) async {
    try {
      final client = SupabaseService.client;
      if (client == null) {
        throw Exception('Supabase client non initialisé');
      }

      final session = client.auth.currentSession;
      if (session == null) {
        throw Exception('Utilisateur non connecté');
      }

      // Construction de l'URL de l'Edge Function
      final url = '${AppConfig.supabaseUrl}/functions/v1/create-compte-api';

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'apikey': AppConfig.supabaseAnonKey,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'numero': numero,
          'id_reseau': idReseau,
          'set_as_default': setAsDefault,
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(
            'Erreur lors de la création du compte: ${response.statusCode} - ${response.body}');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;

      // La réponse contient {"compte": {...}}, il faut extraire le compte
      if (!data.containsKey('compte')) {
        throw Exception('Format de réponse invalide: ${response.body}');
      }

      final compteData = data['compte'] as Map<String, dynamic>;

      return Compte.fromJson(compteData);
    } catch (e) {
      throw Exception('Erreur lors de la création du compte: $e');
    }
  }

  /// Mettre à jour un compte existant
  static Future<Compte> updateCompte({
    required String compteId,
    required String numero,
    BuildContext? context,
  }) async {
    try {
      final supabase = client;
      if (supabase == null) {
        throw Exception('Supabase n\'est pas initialisé');
      }

      var session = supabase.auth.currentSession;
      if (session == null) {
        throw Exception('Utilisateur non authentifié');
      }

      // Rafraîchir la session si elle est expirée
      if (session.isExpired) {
        await supabase.auth.refreshSession();
        final newSession = supabase.auth.currentSession;
        if (newSession == null) {
          throw Exception('Impossible de rafraîchir la session');
        }
        session = newSession;
      }

      final url =
          Uri.parse('${AppConfig.supabaseUrl}/functions/v1/user-comptes');

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'apikey': AppConfig.supabaseAnonKey,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'id': compteId,
          'numero': numero,
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        if (context != null && context.mounted) {
          ToastService.showError(
            context,
            'Erreur lors de la modification du compte',
          );
        }
        throw Exception(
            'Erreur lors de la modification du compte: ${response.statusCode} - ${response.body}');
      }

      final responseData = json.decode(response.body);

      // La réponse peut être un tableau de comptes ou un objet unique
      Map<String, dynamic> compteData;

      if (responseData is List) {
        // Si c'est un tableau, trouver le compte modifié par son ID
        final compteList = responseData;
        final compteFound = compteList.firstWhere(
          (compte) => (compte as Map<String, dynamic>)['id'] == compteId,
          orElse: () => null,
        );

        if (compteFound == null) {
          throw Exception('Compte modifié non trouvé dans la réponse');
        }

        compteData = compteFound;
      } else if (responseData is Map) {
        // Si c'est un objet, vérifier s'il contient 'compte' ou utiliser directement
        final data = responseData as Map<String, dynamic>;
        if (data.containsKey('compte')) {
          compteData = data['compte'] as Map<String, dynamic>;
        } else {
          compteData = data;
        }
      } else {
        throw Exception(
            'Format de réponse inattendu: ${responseData.runtimeType}');
      }

      if (context != null && context.mounted) {
        ToastService.showInfo(
          context,
          'Compte modifié avec succès',
        );
      }

      return Compte.fromJson(compteData);
    } catch (e) {
      if (context != null && context.mounted) {
        ToastService.showError(
          context,
          'Erreur lors de la modification: ${e.toString()}',
        );
      }
      throw Exception('Erreur lors de la modification du compte: $e');
    }
  }

  /// Supprimer un compte
  static Future<void> deleteCompte({
    required String compteId,
    BuildContext? context,
  }) async {
    try {
      final supabase = client;
      if (supabase == null) {
        throw Exception('Supabase n\'est pas initialisé');
      }

      var session = supabase.auth.currentSession;
      if (session == null) {
        throw Exception('Utilisateur non authentifié');
      }

      // Rafraîchir la session si elle est expirée
      if (session.isExpired) {
        await supabase.auth.refreshSession();
        final newSession = supabase.auth.currentSession;
        if (newSession == null) {
          throw Exception('Impossible de rafraîchir la session');
        }
        session = newSession;
      }

      final url = Uri.parse(
          '${AppConfig.supabaseUrl}/functions/v1/delete-compte?compte_id=$compteId');

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200 && response.statusCode != 204) {
        if (context != null && context.mounted) {
          ToastService.showError(
            context,
            'Erreur lors de la suppression du compte',
          );
        }
        throw Exception(
            'Erreur lors de la suppression du compte: ${response.statusCode} - ${response.body}');
      }

      if (context != null && context.mounted) {
        ToastService.showInfo(
          context,
          'Compte supprimé avec succès',
        );
      }
    } catch (e) {
      if (context != null && context.mounted) {
        ToastService.showError(
          context,
          'Erreur lors de la suppression: ${e.toString()}',
        );
      }
      throw Exception('Erreur lors de la suppression du compte: $e');
    }
  }
}

/// Erreur renvoyée par les fonctions d'authentification (code d'erreur serveur)
/// Résultat de l'envoi de l'OTP
class SendOtpResult {
  /// Compte existant : saisir le code d'accès avant l'envoi du SMS
  final bool requiresAccessCode;

  /// Code en clair, uniquement en mode développement
  final String? debugCode;

  const SendOtpResult({this.requiresAccessCode = false, this.debugCode});
}

class AuthOtpException implements Exception {
  final String code;

  /// Essais restants (code d'accès incorrect)
  final int? remaining;

  /// Secondes avant de pouvoir réessayer (blocage / anti-spam)
  final int? retryIn;

  const AuthOtpException(this.code, {this.remaining, this.retryIn});

  @override
  String toString() => 'AuthOtpException($code)';
}

/// État de blocage du code d'accès
class AccessLockStatus {
  final DateTime? lockedUntil;
  final bool permanentlyLocked;

  const AccessLockStatus({this.lockedUntil, this.permanentlyLocked = false});
}

/// Coordonnées du support ; null = canal non proposé
class SupportContacts {
  final String? whatsapp;
  final String? phone;
  final String? email;

  const SupportContacts({this.whatsapp, this.phone, this.email});

  bool get isEmpty => whatsapp == null && phone == null && email == null;
}
