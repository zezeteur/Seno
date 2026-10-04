import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../models/reseau.dart';
import '../models/compte.dart';
import '../utils/auth_errors.dart';
import '../utils/toast_service.dart';
import '../widgets/app_lock_gate.dart';
import 'cache_store.dart';

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
  static Future<AccessLockStatus> getAccessLockStatus() =>
      CacheStore.cached<AccessLockStatus>(
        name: 'access_lock_status',
        userId: client?.auth.currentUser?.id,
        fetch: _getAccessLockStatusRemote,
        encode: (v) => {
          'locked_until': v.lockedUntil?.toIso8601String(),
          'permanently_locked': v.permanentlyLocked,
        },
        decode: (j) {
          final m = j as Map<String, dynamic>;
          final until = m['locked_until'] as String?;
          return AccessLockStatus(
            lockedUntil: until == null ? null : DateTime.parse(until),
            permanentlyLocked: m['permanently_locked'] == true,
          );
        },
      );

  static Future<AccessLockStatus> _getAccessLockStatusRemote() async {
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

  /// Vérifie seulement la date de naissance (aucun SMS, même blocage 3 essais)
  static Future<void> checkBirthDate(DateTime birthDate) async {
    final d = birthDate;
    await _invokeAuth('reset-access-code', {
      'action': 'check_birth_date',
      'birth_date': '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
    });
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

  // ============================================
  // QR CODES (fixe = carte physique, dynamique = app)
  // ============================================

  /// QR fixe de l'utilisateur (mis en cache : sert aussi de secours hors ligne)
  static Future<String> getStaticQr() => CacheStore.cached<String>(
        name: 'qr_static',
        userId: client?.auth.currentUser?.id,
        fetch: () async =>
            (await _invokeAuth('qr-code', {'action': 'static'}))['payload']
                as String,
        encode: (v) => v,
        decode: (j) => j as String,
      );

  /// QR fixe déjà en cache, instantané (affichage avant le QR dynamique)
  static String? peekStaticQr() => CacheStore.peek<String>(
        name: 'qr_static',
        userId: client?.auth.currentUser?.id,
        decode: (j) => j as String,
      );

  /// Nouveau QR fixe : l'ancien (carte perdue) devient invalide
  static Future<String> regenerateStaticQr() async {
    final payload = (await _invokeAuth(
        'qr-code', {'action': 'regenerate_static'}))['payload'] as String;
    await CacheStore.remove(client?.auth.currentUser?.id, 'qr_static');
    return payload;
  }

  /// QR fixe de la boutique (une boutique n'a pas de QR dynamique)
  static Future<String> getMerchantQr() => CacheStore.cached<String>(
        name: 'qr_merchant',
        userId: client?.auth.currentUser?.id,
        fetch: () async =>
            (await _invokeAuth('qr-code', {'action': 'merchant_static'}))[
                'payload'] as String,
        encode: (v) => v,
        decode: (j) => j as String,
      );

  /// QR de la boutique déjà en cache, instantané
  static String? peekMerchantQr() => CacheStore.peek<String>(
        name: 'qr_merchant',
        userId: client?.auth.currentUser?.id,
        decode: (j) => j as String,
      );

  /// QR dynamique : valable ~90 s, à rafraîchir avant [expiresAt]
  static Future<({String payload, DateTime expiresAt})> getDynamicQr() async {
    final res = await _invokeAuth('qr-code', {'action': 'dynamic'});
    return (
      payload: res['payload'] as String,
      expiresAt: DateTime.parse(res['expires_at'] as String).toLocal(),
    );
  }

  /// Résout un QR scanné (côté serveur uniquement)
  static Future<QrPayee> resolveQr(String payload) async {
    final res =
        await _invokeAuth('qr-code', {'action': 'resolve', 'payload': payload});
    return QrPayee.fromJson(res);
  }

  /// Incrémenté après chaque modification du profil : les écrans qui
  /// l'affichent l'écoutent pour se recharger
  static final profileRevision = ValueNotifier<int>(0);

  /// Pseudo, prénoms et photo de l'utilisateur connecté
  static Future<
          ({String? pseudo, String? nom, String? prenoms, String? avatarUrl})>
      getLockProfile() => CacheStore.cached(
            name: 'profile',
            userId: client?.auth.currentUser?.id,
            fetch: _getLockProfileRemote,
            encode: (v) => {
              'pseudo': v.pseudo,
              'nom': v.nom,
              'prenoms': v.prenoms,
              'avatar_url': v.avatarUrl,
            },
            decode: _decodeProfile,
          );

  /// Profil en cache, sans appel réseau (affichage immédiat)
  static ({String? pseudo, String? nom, String? prenoms, String? avatarUrl})?
      peekLockProfile() => CacheStore.peek(
            name: 'profile',
            userId: client?.auth.currentUser?.id,
            decode: _decodeProfile,
          );

  static ({String? pseudo, String? nom, String? prenoms, String? avatarUrl})
      _decodeProfile(Object? j) {
    final m = j as Map<String, dynamic>;
    return (
      pseudo: m['pseudo'] as String?,
      nom: m['nom'] as String?,
      prenoms: m['prenoms'] as String?,
      avatarUrl: m['avatar_url'] as String?,
    );
  }

  static Future<
          ({String? pseudo, String? nom, String? prenoms, String? avatarUrl})>
      _getLockProfileRemote() async {
    final supabase = client;
    final userId = supabase?.auth.currentUser?.id;
    if (supabase == null || userId == null) {
      return (pseudo: null, nom: null, prenoms: null, avatarUrl: null);
    }
    final row = await supabase
        .from('profiles')
        .select('pseudo, nom, prenoms, avatar_url')
        .eq('id', userId)
        .maybeSingle();
    return (
      pseudo: row?['pseudo'] as String?,
      nom: row?['nom'] as String?,
      prenoms: row?['prenoms'] as String?,
      avatarUrl: row?['avatar_url'] as String?,
    );
  }

  /// Pourcentage des frais d'envoi (table frais_transfert, mis en cache)
  static Future<double> getFeePercent() => CacheStore.cached<double>(
        name: 'frais_transfert',
        userId: null,
        fetch: () async {
          final supabase = client;
          if (supabase == null) {
            throw const AuthOtpException('service_unavailable');
          }
          final row = await supabase
              .from('frais_transfert')
              .select('pourcentage')
              .eq('id', 1)
              .maybeSingle();
          return (row?['pourcentage'] as num?)?.toDouble() ?? 0;
        },
        encode: (v) => v,
        decode: (j) => (j as num).toDouble(),
      );

  /// Plafonds d'envoi, identiques pour tous (table plafonds_transfert, mis en cache)
  static Future<AccountLimits> getAccountLimits() =>
      CacheStore.cached<AccountLimits>(
        name: 'plafonds_transfert',
        userId: null,
        fetch: () async {
          final supabase = client;
          if (supabase == null) {
            throw const AuthOtpException('service_unavailable');
          }
          final row = await supabase
              .from('plafonds_transfert')
              .select('par_transaction, journalier, mensuel')
              .eq('id', 1)
              .single();
          return AccountLimits.fromJson(row);
        },
        encode: (v) => v.toJson(),
        decode: (j) =>
            AccountLimits.fromJson(Map<String, dynamic>.from(j as Map)),
      );

  /// Montants déjà envoyés aujourd'hui et ce mois-ci (non mis en cache)
  static Future<({int daily, int monthly})> getLimitsUsage() async {
    final supabase = client;
    if (supabase == null) throw const AuthOtpException('service_unavailable');
    final rows = await supabase.rpc('get_my_plafond_usage') as List;
    final row = rows.isEmpty ? const {} : rows.first as Map;
    return (
      daily: (row['journalier'] as num?)?.toInt() ?? 0,
      monthly: (row['mensuel'] as num?)?.toInt() ?? 0,
    );
  }

  /// Coordonnées du support (table support_contacts)
  static Future<SupportContacts> getSupportContacts() =>
      CacheStore.cached<SupportContacts>(
        name: 'support_contacts',
        userId: null,
        fetch: _getSupportContactsRemote,
        encode: (v) =>
            {'whatsapp': v.whatsapp, 'phone': v.phone, 'email': v.email},
        decode: (j) {
          final m = j as Map<String, dynamic>;
          return SupportContacts(
            whatsapp: m['whatsapp'] as String?,
            phone: m['phone'] as String?,
            email: m['email'] as String?,
          );
        },
      );

  static Future<SupportContacts> _getSupportContactsRemote() async {
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
  static Future<bool> hasAccessCode() => CacheStore.cached<bool>(
        name: 'has_access_code',
        userId: client?.auth.currentUser?.id,
        fetch: _hasAccessCodeRemote,
        encode: (v) => v,
        decode: (j) => j == true,
      );

  static Future<bool> _hasAccessCodeRemote() async {
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
  static Future<bool> hasProfile() => CacheStore.cached<bool>(
        name: 'has_profile',
        userId: client?.auth.currentUser?.id,
        fetch: _hasProfileRemote,
        encode: (v) => v,
        decode: (j) => j == true,
      );

  static Future<bool> _hasProfileRemote() async {
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

  /// Compte marchand de l'utilisateur connecté, ou null (mis en cache)
  static Future<MerchantInfo?> getMyMerchant() =>
      CacheStore.cached<MerchantInfo?>(
        name: 'merchant',
        userId: client?.auth.currentUser?.id,
        fetch: () async {
          final supabase = client!;
          final row = await supabase
              .from('merchant_requests')
              .select('business_name, pseudo, category, description, city, '
                  'address, business_phone, email, logo_url, is_active, '
                  'admin_suspended, admin_suspended_reason')
              .eq('user_id', supabase.auth.currentUser!.id)
              .maybeSingle();
          return row == null ? null : MerchantInfo.fromJson(row);
        },
        encode: (v) => v?.toJson(),
        decode: _decodeMerchant,
      );

  /// Boutique en cache, sans appel réseau (affichage immédiat)
  static MerchantInfo? peekMyMerchant() => CacheStore.peek<MerchantInfo?>(
        name: 'merchant',
        userId: client?.auth.currentUser?.id,
        decode: _decodeMerchant,
      );

  static MerchantInfo? _decodeMerchant(Object? j) => j == null
      ? null
      : MerchantInfo.fromJson(Map<String, dynamic>.from(j as Map));

  /// Date à partir de laquelle le pseudo boutique peut être changé
  /// (null = maintenant) ; même délai que le pseudo utilisateur
  static Future<DateTime?> getNextShopPseudoChange() async {
    final supabase = client!;
    final row = await supabase
        .from('merchant_requests')
        .select('pseudo_changed_at')
        .eq('user_id', supabase.auth.currentUser!.id)
        .maybeSingle();
    final value = row?['pseudo_changed_at'] as String?;
    final changedAt = value == null ? null : DateTime.tryParse(value);
    if (changedAt == null) return null;
    final next = changedAt.toLocal().add(pseudoCooldown);
    return next.isAfter(DateTime.now()) ? next : null;
  }

  /// Incrémenté à chaque modification de la boutique (carte du compte)
  static final merchantRevision = ValueNotifier<int>(0);

  /// Modifie les champs de la boutique ({'business_name': …, 'pseudo': …})
  static Future<void> updateMerchant(Map<String, dynamic> fields) async {
    final supabase = client!;
    final rows = await supabase
        .from('merchant_requests')
        .update(fields)
        .eq('user_id', supabase.auth.currentUser!.id)
        .select('user_id');
    if (rows.isEmpty) throw const AuthOtpException('profile_update_denied');
    await CacheStore.remove(supabase.auth.currentUser!.id, 'merchant');
    merchantRevision.value++;
  }

  /// Supprime le logo de la boutique (fichier + URL)
  static Future<void> removeMerchantLogo() async {
    final supabase = client!;
    await updateMerchant({'logo_url': null});
    await supabase.storage
        .from('avatars')
        .remove(['${supabase.auth.currentUser!.id}/merchant_logo.jpg']);
  }

  /// Envoie le logo du commerce (bucket avatars, dossier = id utilisateur)
  /// et renvoie son URL publique
  static Future<String> uploadMerchantLogo(Uint8List bytes) async {
    final supabase = client!;
    final path = '${supabase.auth.currentUser!.id}/merchant_logo.jpg';
    final bucket = supabase.storage.from('avatars');
    await bucket.uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
    );
    return '${bucket.getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Envoie la demande pour devenir marchand
  static Future<void> submitMerchantRequest({
    required String businessName,
    required String category,
    String? description,
    required String city,
    required String address,
    required String businessPhone,
    String? email,
    String? logoUrl,
    required String pseudo,
  }) async {
    final supabase = client!;
    await supabase.from('merchant_requests').insert({
      'pseudo': pseudo,
      'logo_url': logoUrl,
      'user_id': supabase.auth.currentUser!.id,
      'business_name': businessName,
      'category': category,
      'description': description,
      'city': city,
      'address': address,
      'business_phone': businessPhone,
      'email': email,
    });
    await CacheStore.remove(supabase.auth.currentUser!.id, 'merchant');
  }

  /// Préférences de notifications par défaut (identiques à la colonne SQL)
  static const defaultNotifPrefs = {
    'push': true,
    'transactions': true,
    'promotions': false,
    'security': true,
  };

  static Map<String, bool> _decodeNotifPrefs(Object? json) => {
        ...defaultNotifPrefs,
        if (json is Map)
          for (final e in json.entries)
            if (e.value is bool) e.key as String: e.value as bool,
      };

  /// Préférences de notifications (copie locale si hors ligne)
  static Future<Map<String, bool>> getNotifPrefs() =>
      CacheStore.cached<Map<String, bool>>(
        name: 'notif_prefs',
        userId: client?.auth.currentUser?.id,
        fetch: _getNotifPrefsRemote,
        encode: (v) => v,
        decode: _decodeNotifPrefs,
      );

  static Future<Map<String, bool>> _getNotifPrefsRemote() async {
    final supabase = client!;
    final row = await supabase
        .from('profiles')
        .select('notif_prefs')
        .eq('id', supabase.auth.currentUser!.id)
        .maybeSingle();
    return _decodeNotifPrefs(row?['notif_prefs']);
  }

  /// Enregistre les préférences de notifications
  static Future<void> updateNotifPrefs(Map<String, bool> prefs) async {
    final supabase = client!;
    final userId = supabase.auth.currentUser!.id;
    final rows = await supabase
        .from('profiles')
        .update({'notif_prefs': prefs})
        .eq('id', userId)
        .select('id');
    // Aucune ligne modifiée : refusé par la RLS (pas d'erreur renvoyée)
    if (rows.isEmpty) throw const AuthOtpException('profile_update_denied');
    await CacheStore.remove(userId, 'notif_prefs');
  }

  /// Délai de changement de pseudo : 1 fois tous les 7 jours
  static const pseudoCooldown = Duration(days: 7);

  /// Date à partir de laquelle le pseudo peut être changé (null = maintenant)
  static Future<DateTime?> getNextPseudoChange() async {
    final supabase = client!;
    final row = await supabase
        .from('profiles')
        .select('pseudo_changed_at')
        .eq('id', supabase.auth.currentUser!.id)
        .maybeSingle();
    final value = row?['pseudo_changed_at'] as String?;
    final changedAt = value == null ? null : DateTime.tryParse(value);
    if (changedAt == null) return null;
    final next = changedAt.toLocal().add(pseudoCooldown);
    return next.isAfter(DateTime.now()) ? next : null;
  }

  /// Met à jour les champs renseignés du profil puis rafraîchit le cache
  /// Envoie la photo de profil (bucket avatars, dossier = id utilisateur)
  /// puis enregistre son URL publique dans le profil
  static Future<void> uploadAvatar(Uint8List bytes) async {
    final supabase = client!;
    final userId = supabase.auth.currentUser!.id;
    final path = '$userId/avatar.jpg';
    final bucket = supabase.storage.from('avatars');
    await bucket.uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
    );
    // Paramètre de version : la nouvelle photo n'est pas masquée par un cache
    final url =
        '${bucket.getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
    final rows = await supabase
        .from('profiles')
        .update({'avatar_url': url})
        .eq('id', userId)
        .select('id');
    if (rows.isEmpty) throw const AuthOtpException('profile_update_denied');
    try {
      await getLockProfile();
    } catch (_) {
      await CacheStore.remove(userId, 'profile');
    }
    profileRevision.value++;
  }

  /// Supprime la photo de profil (fichier + URL dans le profil)
  static Future<void> removeAvatar() async {
    final supabase = client!;
    final userId = supabase.auth.currentUser!.id;
    final rows = await supabase
        .from('profiles')
        .update({'avatar_url': null})
        .eq('id', userId)
        .select('id');
    if (rows.isEmpty) throw const AuthOtpException('profile_update_denied');
    try {
      await supabase.storage.from('avatars').remove(['$userId/avatar.jpg']);
    } catch (_) {
      // Fichier orphelin sans conséquence : le profil n'y fait plus référence
    }
    try {
      await getLockProfile();
    } catch (_) {
      await CacheStore.remove(userId, 'profile');
    }
    profileRevision.value++;
  }

  static Future<void> updateProfile({
    String? nom,
    String? prenoms,
    String? pseudo,
  }) async {
    final supabase = client!;
    final userId = supabase.auth.currentUser!.id;
    final rows = await supabase
        .from('profiles')
        .update({
          if (nom != null) 'nom': nom,
          if (prenoms != null) 'prenoms': prenoms,
          if (pseudo != null) 'pseudo': pseudo,
        })
        .eq('id', userId)
        .select('id');
    // Aucune ligne modifiée : refusé par la RLS (pas d'erreur renvoyée)
    if (rows.isEmpty) throw const AuthOtpException('profile_update_denied');
    try {
      // Relecture : le cache reçoit la nouvelle version (utile hors ligne)
      await getLockProfile();
    } catch (_) {
      // Relecture impossible : pas de copie périmée
      await CacheStore.remove(userId, 'profile');
    }
    profileRevision.value++;
  }

  static const _senoLookupBatch = 1000;
  static const _senoLookupCacheName = 'seno_contacts';

  static Map<String, ({String pseudo, String? avatarUrl})> _decodeSenoContacts(
          Object? json) =>
      {
        for (final e in (json as Map).cast<String, dynamic>().entries)
          e.key: (
            pseudo: (e.value as Map)['pseudo'] as String,
            avatarUrl: (e.value as Map)['avatar_url'] as String?,
          ),
      };

  /// Dernière copie des comptes Seno des contacts, sans appel réseau
  static Map<String, ({String pseudo, String? avatarUrl})> peekSenoContacts() =>
      CacheStore.peek(
        name: _senoLookupCacheName,
        userId: client?.auth.currentUser?.id,
        decode: _decodeSenoContacts,
      ) ??
      {};

  /// Numéros locaux (10 chiffres) ayant un compte Seno → pseudo et photo.
  /// Toujours relu sur le serveur (lots de 1000) ; la copie enregistrée ne
  /// sert que hors ligne.
  static Future<Map<String, ({String pseudo, String? avatarUrl})>>
      lookupSenoContacts(List<String> localNumbers) async {
    final userId = client?.auth.currentUser?.id;
    final numbers = localNumbers.toSet().toList();
    final found = <String, ({String pseudo, String? avatarUrl})>{};
    try {
      for (var i = 0; i < numbers.length; i += _senoLookupBatch) {
        final batch =
            numbers.sublist(i, (i + _senoLookupBatch).clamp(0, numbers.length));
        final rows = await client!.rpc('lookup_seno_contacts', params: {
          'p_phones': [for (final n in batch) '+225$n'],
        }) as List<dynamic>;
        for (final r in rows.cast<Map<String, dynamic>>()) {
          found[(r['phone'] as String).replaceFirst('+225', '')] = (
            pseudo: r['pseudo'] as String,
            avatarUrl: r['avatar_url'] as String?,
          );
        }
      }
    } catch (_) {
      // Hors ligne : dernière copie enregistrée, sinon l'erreur d'origine
      final saved = CacheStore.peek(
          name: _senoLookupCacheName,
          userId: userId,
          decode: _decodeSenoContacts);
      if (saved == null) rethrow;
      CacheStore.offline.value = true;
      return {
        for (final n in numbers)
          if (saved[n] case final account?) n: account,
      };
    }
    CacheStore.offline.value = false;
    // Copie de secours : fusion pour ne pas perdre les autres numéros
    final saved = CacheStore.peek(
            name: _senoLookupCacheName,
            userId: userId,
            decode: _decodeSenoContacts) ??
        {};
    for (final n in numbers) {
      saved.remove(n);
    }
    saved.addAll(found);
    await CacheStore.put(userId, _senoLookupCacheName, {
      for (final e in saved.entries)
        e.key: {'pseudo': e.value.pseudo, 'avatar_url': e.value.avatarUrl},
    });
    return found;
  }

  /// Utilisateurs Seno dont le pseudo commence par [query] (3 car. min, 10 max)
  /// Utilisateurs et boutiques actives dont le pseudo commence par [query]
  /// (boutique : logo en avatar, nom du commerce en [displayName])
  static Future<
      List<
          ({
            String pseudo,
            String? avatarUrl,
            String? displayName,
            bool isMerchant,
            String? category
          })>> searchSenoUsers(String query) async {
    final rows = await client!
        .rpc('search_seno_users', params: {'p_query': query}) as List<dynamic>;
    return [
      for (final r in rows.cast<Map<String, dynamic>>())
        (
          pseudo: r['pseudo'] as String,
          avatarUrl: r['avatar_url'] as String?,
          displayName: r['display_name'] as String?,
          isMerchant: r['is_merchant'] == true,
          category: r['category'] as String?,
        ),
    ];
  }

  /// Le destinataire (pseudo utilisateur ou boutique) est-il un marchand
  /// actif ? Ses frais sont alors retirés du montant reçu (règle de transfer)
  static Future<bool> isSenoMerchant(String pseudo) async {
    final result =
        await client!.rpc('is_seno_merchant', params: {'p_pseudo': pseudo});
    return result == true;
  }

  /// Comptes de réception d'un utilisateur Seno (numéro masqué, défaut en
  /// tête). Hors ligne : dernière copie enregistrée pour ce pseudo.
  static Future<
      List<
          ({
            String id,
            String idReseau,
            String numeroMasque,
            bool isDefault
          })>> getSenoUserComptes(String pseudo) => CacheStore.cached(
        name: 'seno_user_comptes:${pseudo.toLowerCase()}',
        userId: client?.auth.currentUser?.id,
        fetch: () async {
          final rows = await client!.rpc('get_seno_user_comptes',
              params: {'p_pseudo': pseudo}) as List<dynamic>;
          return [
            for (final r in rows.cast<Map<String, dynamic>>())
              (
                id: r['id'] as String,
                idReseau: r['id_reseau'] as String,
                numeroMasque: r['numero_masque'] as String,
                isDefault: r['is_default'] as bool,
              ),
          ];
        },
        encode: (comptes) => [
          for (final c in comptes)
            {
              'id': c.id,
              'id_reseau': c.idReseau,
              'numero_masque': c.numeroMasque,
              'is_default': c.isDefault,
            },
        ],
        decode: (json) => [
          for (final r in (json as List).cast<Map<String, dynamic>>())
            (
              id: r['id'] as String,
              idReseau: r['id_reseau'] as String,
              numeroMasque: r['numero_masque'] as String,
              isDefault: r['is_default'] as bool,
            ),
        ],
      );

  /// Vérifie qu'aucun profil n'utilise déjà ce pseudo
  static Future<bool> isPseudoAvailable(String pseudo) async {
    final result =
        await client!.rpc('is_pseudo_available', params: {'p_pseudo': pseudo});
    return result == true;
  }

  /// Récupérer la liste des réseaux
  static Future<List<Reseau>> getReseaux() => CacheStore.cached<List<Reseau>>(
        name: 'reseaux',
        userId: null,
        fetch: _getReseauxRemote,
        encode: (v) => v.map((r) => r.toJson()).toList(),
        decode: (j) => (j as List)
            .map((e) => Reseau.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  static Future<List<Reseau>> _getReseauxRemote() async {
    final rows = await client!
        .from('reseaux')
        .select('id, nom, abreviation, statut, logo')
        .eq('statut', true)
        .order('ordre');
    return rows.map(Reseau.fromJson).toList();
  }

  /// Récupérer la liste des comptes de l'utilisateur connecté
  static Future<List<Compte>> getComptes() => CacheStore.cached<List<Compte>>(
        name: 'comptes',
        userId: client?.auth.currentUser?.id,
        fetch: _getComptesRemote,
        encode: (v) => v.map((c) => c.toJson()).toList(),
        decode: _decodeComptes,
      );

  /// Dernière copie des comptes, sans attendre le réseau
  static List<Compte>? peekComptes() => CacheStore.peek(
        name: 'comptes',
        userId: client?.auth.currentUser?.id,
        decode: _decodeComptes,
      );

  static List<Compte> _decodeComptes(Object? j) => (j as List)
      .map((e) => Compte.fromJson(e as Map<String, dynamic>))
      .toList();

  static const _compteColumns =
      'id, proprietaire, numero, id_reseau, created_at, updated_at';

  static Future<List<Compte>> _getComptesRemote() async {
    // RLS : seuls les comptes de l'utilisateur connecté sont renvoyés
    final rows = await client!
        .from('comptes')
        .select(_compteColumns)
        .order('created_at');
    return rows.map(Compte.fromJson).toList();
  }

  /// Récupérer le compte par défaut de l'utilisateur connecté
  static Future<Compte?> getDefaultCompte() => CacheStore.cached<Compte?>(
        name: 'default_compte',
        userId: client?.auth.currentUser?.id,
        fetch: _getDefaultCompteRemote,
        encode: (v) => v?.toJson(),
        decode: (j) =>
            j == null ? null : Compte.fromJson(j as Map<String, dynamic>),
      );

  static Future<Compte?> _getDefaultCompteRemote() async {
    final id = await client!.rpc('get_default_compte_id') as String?;
    if (id == null) return null;
    final row = await client!
        .from('comptes')
        .select(_compteColumns)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Compte.fromJson(row);
  }

  /// Après une modification de compte : pas de copie périmée hors ligne
  static Future<void> _invalidateComptesCache() async {
    final userId = client?.auth.currentUser?.id;
    await CacheStore.remove(userId, 'comptes');
    await CacheStore.remove(userId, 'default_compte');
  }

  /// Définir un compte comme compte par défaut
  static Future<void> setDefaultCompte({
    required String compteId,
    BuildContext? context,
  }) async {
    try {
      await client!
          .rpc('set_default_compte', params: {'p_compte_id': compteId});
      await _invalidateComptesCache();
      if (context != null && context.mounted) {
        ToastService.showInfo(context, 'Compte défini comme compte par défaut');
      }
    } catch (e) {
      if (context != null && context.mounted) {
        ToastService.showError(
            context, 'Impossible de définir le compte par défaut');
      }
      throw Exception('Erreur lors de la définition du compte par défaut: $e');
    }
  }

  /// Ajout de compte, étape 1 : SMS au numéro saisi. Renvoie le jeton de vérification.
  static Future<String> sendCompteOtp({
    required String numero,
    required String idReseau,
    String? compteId, // modification d'un compte existant
  }) async {
    final res = await _invokeAuth('compte-otp', {
      'action': 'send',
      'numero': numero,
      'id_reseau': idReseau,
      if (compteId != null) 'compte_id': compteId,
    });
    return res['token'] as String;
  }

  static Future<void> resendCompteOtp(String token) async {
    await _invokeAuth('compte-otp', {'action': 'resend', 'token': token});
  }

  /// Ajout de compte, étape 2 : code SMS correct → le compte est créé côté serveur
  static Future<Compte> createCompte({
    required String verificationToken,
    required String otp,
    required bool setAsDefault,
  }) async {
    final res = await _invokeAuth('compte-otp', {
      'action': 'confirm',
      'token': verificationToken,
      'otp': otp,
      'set_as_default': setAsDefault,
    });
    await _invalidateComptesCache();
    return Compte.fromJson(Map<String, dynamic>.from(res['compte'] as Map));
  }

  /// Modification du numéro : code SMS reçu sur le nouveau numéro → mise à jour côté serveur
  static Future<Compte> updateCompte({
    required String verificationToken,
    required String otp,
    BuildContext? context,
  }) async {
    try {
      final res = await _invokeAuth('compte-otp', {
        'action': 'confirm',
        'token': verificationToken,
        'otp': otp,
      });
      await _invalidateComptesCache();
      if (context != null && context.mounted) {
        ToastService.showInfo(context, 'Compte modifié avec succès');
      }
      return Compte.fromJson(Map<String, dynamic>.from(res['compte'] as Map));
    } catch (e) {
      if (context != null && context.mounted) {
        ToastService.showError(context, authErrorMessage(context, e));
      }
      rethrow;
    }
  }

  /// Supprimer un compte (le compte par défaut est retiré automatiquement)
  static Future<void> deleteCompte({
    required String compteId,
    BuildContext? context,
  }) async {
    try {
      await client!.from('comptes').delete().eq('id', compteId);
      await _invalidateComptesCache();
      if (context != null && context.mounted) {
        ToastService.showInfo(context, 'Compte supprimé avec succès');
      }
    } catch (e) {
      if (context != null && context.mounted) {
        ToastService.showError(
            context, 'Erreur lors de la suppression du compte');
      }
      throw Exception('Erreur lors de la suppression du compte: $e');
    }
  }

  // ---------- Envoi d'argent (Jèko) ----------

  /// Lance un envoi : collecte Jèko sur [compteId], puis reversement au
  /// destinataire ([toCompteId] d'un utilisateur Seno, sinon [toNumero] + [toReseauId]).
  /// Renvoie l'id de l'envoi et l'URL de validation opérateur (USSD / Wave).
  /// [idempotencyKey] (UUID) : la même clé renvoie l'envoi déjà créé au lieu
  /// d'en créer un second (double tap, renvoi après timeout).
  static Future<({String id, String redirectUrl})> sendMoney({
    required String idempotencyKey,
    required String compteId,
    required int amount,
    required bool senderPaysFees,
    required String label,
    String? toCompteId,
    String? toNumero,
    String? toReseauId,
  }) async {
    final res = await _invokeAuth('transfer', {
      'action': 'create',
      'idempotency_key': idempotencyKey,
      'compte_id': compteId,
      'amount': amount,
      'sender_pays_fees': senderPaysFees,
      'label': label,
      if (toCompteId != null) 'to_compte_id': toCompteId,
      if (toNumero != null) 'to_numero': toNumero,
      if (toReseauId != null) 'to_reseau_id': toReseauId,
    });
    return (
      id: res['id'] as String,
      redirectUrl: res['redirect_url'] as String
    );
  }

  /// Statut d'un envoi (le serveur interroge Jèko si le webhook tarde)
  static Future<String> getTransfertStatus(String id) async {
    final res = await _invokeAuth('transfer', {'action': 'status', 'id': id});
    return res['statut'] as String;
  }

  /// UUID v4 aléatoire (clé d'idempotence des envois)
  static String newIdempotencyKey() {
    final rnd = Random.secure();
    final b = List<int>.generate(16, (_) => rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Incrémenté quand un envoi se termine : l'historique se recharge
  static final transactionsRevision = ValueNotifier<int>(0);

  static RealtimeChannel? _transactionsChannel;

  static final _transfertEvents =
      StreamController<({String id, String statut})>.broadcast();

  /// Changements de statut reçus en temps réel (id du transfert + statut)
  static Stream<({String id, String statut})> get transfertEvents =>
      _transfertEvents.stream;

  /// Écoute le canal privé de l'utilisateur : chaque envoi / réception qui
  /// change de statut recharge l'historique. Une seule connexion à la fois.
  static void subscribeTransactions() {
    final supabase = client;
    final userId = supabase?.auth.currentUser?.id;
    if (supabase == null || userId == null || _transactionsChannel != null) {
      return;
    }
    _transactionsChannel = supabase
        .channel(
          'transactions:$userId',
          opts: const RealtimeChannelConfig(private: true),
        )
        .onBroadcast(
          event: 'transfert',
          callback: (message) {
            transactionsRevision.value++;
            final data =
                message['payload'] is Map ? message['payload'] as Map : message;
            final id = data['id'], statut = data['statut'];
            if (id is String && statut is String) {
              _transfertEvents.add((id: id, statut: statut));
            }
          },
        )
        .subscribe();
  }

  /// App en arrière-plan / déconnexion : libère la connexion Realtime
  /// Sessions actives de l'utilisateur (appareils connectés)
  static Future<List<Map<String, dynamic>>> listMySessions() async {
    final rows = await client!.rpc('list_my_sessions');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Déconnecte un autre appareil
  static Future<void> revokeSession(String sessionId) =>
      client!.rpc('revoke_my_session', params: {'p_session_id': sessionId});

  /// Déconnecte tous les appareils sauf celui-ci
  static Future<void> signOutOtherDevices() =>
      client!.auth.signOut(scope: SignOutScope.others);

  static Future<void> unsubscribeTransactions() async {
    final channel = _transactionsChannel;
    _transactionsChannel = null;
    if (channel != null) await client?.removeChannel(channel);
  }

  /// Historique : envois et réceptions, du plus récent au plus ancien
  /// Page de l'historique, du plus récent au plus ancien.
  /// [before] : curseur (date de la dernière ligne déjà affichée) pour la page
  /// suivante ; [sens] : 'envoi', 'reception' ou null (tous).
  /// Seule la première page est gardée en cache ([cacheName], une copie par écran).
  static Future<List<SenoTransaction>> getTransactions({
    int limit = 50,
    String cacheName = 'transactions',
    DateTime? before,
    String? sens,
  }) {
    Future<List<SenoTransaction>> fetch() async {
      final rows = await client!.rpc('get_my_transactions', params: {
        'p_limit': limit,
        if (before != null) 'p_before': before.toUtc().toIso8601String(),
        if (sens != null) 'p_sens': sens,
      }) as List;
      return _decodeTransactions(rows);
    }

    if (before != null) return fetch();
    return CacheStore.cached<List<SenoTransaction>>(
      name: cacheName,
      userId: client?.auth.currentUser?.id,
      fetch: fetch,
      encode: (v) => v.map((t) => t.toJson()).toList(),
      decode: _decodeTransactions,
    );
  }

  /// Envoi récent par son id (retour de la page de paiement), sans cache
  static Future<SenoTransaction?> findSentTransaction(String id) async {
    final rows = await client!.rpc('get_my_transactions', params: {
      'p_limit': 50,
      'p_sens': 'envoi',
    }) as List;
    for (final tx in _decodeTransactions(rows)) {
      if (tx.id == id) return tx;
    }
    return null;
  }

  /// Dernière copie de l'historique, sans attendre le réseau
  static List<SenoTransaction>? peekTransactions(
          {String cacheName = 'transactions'}) =>
      CacheStore.peek(
        name: cacheName,
        userId: client?.auth.currentUser?.id,
        decode: _decodeTransactions,
      );

  static List<SenoTransaction> _decodeTransactions(Object? j) => (j as List)
      .map((e) => SenoTransaction.fromJson(e as Map<String, dynamic>))
      .toList();
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

/// Plafonds d'envoi en FCFA (montant reçu par le destinataire)
class AccountLimits {
  final int perTransaction;
  final int daily;
  final int monthly;

  const AccountLimits({
    required this.perTransaction,
    required this.daily,
    required this.monthly,
  });

  factory AccountLimits.fromJson(Map<String, dynamic> json) => AccountLimits(
        perTransaction: (json['par_transaction'] as num).toInt(),
        daily: (json['journalier'] as num).toInt(),
        monthly: (json['mensuel'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'par_transaction': perTransaction,
        'journalier': daily,
        'mensuel': monthly,
      };
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

/// Boutique de l'utilisateur (compte marchand)
class MerchantInfo {
  final String businessName;
  final String? pseudo;
  final String category;
  final String? description;
  final String city;
  final String address;
  final String businessPhone;
  final String? email;
  final String? logoUrl;

  /// Boutique activée par le marchand
  final bool isActive;

  /// Suspendue par Seno : le marchand ne peut pas la réactiver
  final bool adminSuspended;
  final String? adminSuspendedReason;

  const MerchantInfo({
    required this.businessName,
    required this.pseudo,
    required this.category,
    required this.description,
    required this.city,
    required this.address,
    required this.businessPhone,
    required this.email,
    required this.logoUrl,
    required this.isActive,
    this.adminSuspended = false,
    this.adminSuspendedReason,
  });

  factory MerchantInfo.fromJson(Map<String, dynamic> json) => MerchantInfo(
        businessName: json['business_name'] as String,
        pseudo: json['pseudo'] as String?,
        category: json['category'] as String,
        description: json['description'] as String?,
        city: json['city'] as String,
        address: json['address'] as String,
        businessPhone: json['business_phone'] as String,
        email: json['email'] as String?,
        logoUrl: json['logo_url'] as String?,
        // Ancienne copie en cache sans la colonne : boutique active
        isActive: json['is_active'] as bool? ?? true,
        adminSuspended: json['admin_suspended'] as bool? ?? false,
        adminSuspendedReason: json['admin_suspended_reason'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'business_name': businessName,
        'pseudo': pseudo,
        'category': category,
        'description': description,
        'city': city,
        'address': address,
        'business_phone': businessPhone,
        'email': email,
        'logo_url': logoUrl,
        'is_active': isActive,
        'admin_suspended': adminSuspended,
        'admin_suspended_reason': adminSuspendedReason,
      };
}

/// Destinataire trouvé en scannant un QR Seno (aucun identifiant en clair)
class QrPayee {
  final String pseudo;
  final String prenom;
  final String? avatarUrl;
  final String? numeroMasque;
  final String? reseau;
  final String? abreviation;
  final bool isSelf;

  /// Référence chiffrée à transmettre lors de l'envoi d'argent
  final String payeeRef;

  const QrPayee({
    required this.pseudo,
    required this.prenom,
    required this.avatarUrl,
    required this.numeroMasque,
    required this.reseau,
    required this.abreviation,
    required this.isSelf,
    required this.payeeRef,
  });

  factory QrPayee.fromJson(Map<String, dynamic> json) {
    final compte = json['compte'] as Map?;
    return QrPayee(
      pseudo: json['pseudo'] as String? ?? '',
      prenom: json['prenom'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      numeroMasque: compte?['numero_masque'] as String?,
      reseau: compte?['reseau'] as String?,
      abreviation: compte?['abreviation'] as String?,
      isSelf: json['is_self'] == true,
      payeeRef: json['payee_ref'] as String,
    );
  }
}

/// Ligne de l'historique (envoi ou réception)
class SenoTransaction {
  final String id;
  final bool isReceived;

  /// Pseudo de l'autre partie, sinon nom / numéro saisi
  final String label;
  final String? avatarUrl;

  /// FCFA : débité (envoi, frais inclus) ou reçu (réception)
  final int montant;
  final int frais;

  /// collecte_en_attente, collecte_echec, transfert_en_cours, reussi,
  /// reversement_relance, rembourse_en_cours, rembourse, remboursement_echec,
  /// transfert_echec
  final String statut;
  final DateTime createdAt;

  /// FCFA reçus par le destinataire
  final int montantRecu;

  /// Numéro de réception (masqué si c'est le compte d'un autre utilisateur)
  final String numero;
  final String reseauId;

  /// Envoi en attente (Wave / Orange) : page de validation du paiement
  final String? paymentUrl;

  /// Envoi à une boutique : sa catégorie (icône si pas de logo)
  final String? merchantCategory;

  /// Envoi à une boutique : son nom (titre à la place du pseudo)
  final String? merchantName;

  /// Autre partie utilisateur Seno : « Nom Prénoms »
  final String? personName;

  const SenoTransaction({
    required this.id,
    required this.isReceived,
    required this.label,
    required this.avatarUrl,
    required this.montant,
    required this.frais,
    required this.statut,
    required this.createdAt,
    required this.montantRecu,
    required this.numero,
    required this.reseauId,
    this.paymentUrl,
    this.merchantCategory,
    this.merchantName,
    this.personName,
  });

  /// Ligne de get_my_transactions (même format que le cache)
  factory SenoTransaction.fromJson(Map<String, dynamic> r) => SenoTransaction(
        id: r['id'] as String,
        isReceived: r['sens'] == 'reception',
        label: r['label'] as String,
        avatarUrl: r['avatar_url'] as String?,
        montant: r['montant'] as int,
        frais: r['frais'] as int,
        statut: r['statut'] as String,
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        montantRecu: r['montant_recu'] as int,
        numero: r['numero'] as String,
        reseauId: r['reseau_id'] as String,
        paymentUrl: r['payment_url'] as String?,
        merchantCategory: r['merchant_category'] as String?,
        merchantName: r['merchant_name'] as String?,
        personName: r['person_name'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sens': isReceived ? 'reception' : 'envoi',
        'label': label,
        'avatar_url': avatarUrl,
        'montant': montant,
        'frais': frais,
        'statut': statut,
        'created_at': createdAt.toUtc().toIso8601String(),
        'montant_recu': montantRecu,
        'numero': numero,
        'reseau_id': reseauId,
        'payment_url': paymentUrl,
        'merchant_category': merchantCategory,
        'merchant_name': merchantName,
        'person_name': personName,
      };

  bool get isFailed => failedStatuts.contains(statut);
  bool get isPending => pendingStatuts.contains(statut);
  bool get isRefunded => statut == 'rembourse';

  static const failedStatuts = {
    'collecte_echec',
    'transfert_echec',
    'remboursement_echec',
  };

  /// Relance du reversement et remboursement en cours : encore en traitement
  static const pendingStatuts = {
    'collecte_en_attente',
    'transfert_en_cours',
    'reversement_relance',
    'rembourse_en_cours',
  };
}
