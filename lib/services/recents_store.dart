import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import 'cache_store.dart';
import 'supabase_service.dart';

/// Destinataire récent : pseudo ou numéro groupé ([value]), photo, numéro
/// local (10 chiffres) s'il est connu
typedef RecentRecipient = ({String value, String? avatarUrl, String? phone});

/// Contact du répertoire et ses numéros locaux (10 chiffres)
typedef PhoneContact = ({String name, List<String> numbers});

/// Derniers destinataires, partagés entre l'accueil et l'envoi d'argent.
/// Gardés dans le cache chiffré de l'utilisateur (effacé à la déconnexion).
class RecentsStore {
  RecentsStore._();

  static const _recentsKey = 'send_recents';
  static const _phoneContactsKey = 'phone_contacts';
  static const maxRecents = 8;
  static final _phonePattern = RegExp(r'^[\d ]+$');

  /// Du plus récent au plus ancien ; notifie l'accueil à chaque ajout
  static final recents = ValueNotifier<List<RecentRecipient>>([]);

  static String? get _userId => SupabaseService.isInitialized
      ? SupabaseService.client?.auth.currentUser?.id
      : null;

  static String? _loadedFor;

  /// Lit les récents de l'utilisateur connecté (une fois par utilisateur :
  /// ensuite la liste en mémoire est à jour, via [add])
  static void load() {
    final userId = _userId;
    if (userId != null && userId == _loadedFor) return;
    _loadedFor = userId;
    recents.value = CacheStore.peek<List<RecentRecipient>>(
          name: _recentsKey,
          userId: _userId,
          decode: (json) => [
            for (final e in (json as List).cast<Map<String, dynamic>>())
              (
                value: e['value'] as String,
                avatarUrl: e['avatar_url'] as String?,
                phone: e['phone'] as String?,
              ),
          ],
        ) ??
        [];
  }

  /// Destinataire choisi : en tête des récents (sans doublon)
  static void add(String value, {String? avatarUrl, String? phone}) {
    String key(String v) => v.toLowerCase().replaceAll(' ', '');
    recents.value = [
      (value: value, avatarUrl: avatarUrl, phone: phone),
      ...recents.value.where((r) => key(r.value) != key(value)),
    ].take(maxRecents).toList();
    CacheStore.put(_userId, _recentsKey, [
      for (final r in recents.value)
        {'value': r.value, 'avatar_url': r.avatarUrl, 'phone': r.phone},
    ]);
  }

  /// Dernière copie du répertoire (vide si jamais lu ou accès retiré)
  static List<PhoneContact> peekPhoneContacts() =>
      CacheStore.peek<List<PhoneContact>>(
        name: _phoneContactsKey,
        userId: _userId,
        decode: (json) => [
          for (final e in (json as List).cast<Map<String, dynamic>>())
            (
              name: e['name'] as String,
              numbers: (e['numbers'] as List).cast<String>(),
            ),
        ],
      ) ??
      [];

  static Future<void> savePhoneContacts(List<PhoneContact> contacts) =>
      CacheStore.put(_userId, _phoneContactsKey, [
        for (final c in contacts) {'name': c.name, 'numbers': c.numbers},
      ]);

  static Future<void> removePhoneContacts() =>
      CacheStore.remove(_userId, _phoneContactsKey);

  /// Nom du récent dans le répertoire : par son numéro, sinon par son pseudo
  /// (numéro du répertoire lié à ce compte Seno)
  static String? contactName(
    RecentRecipient recent,
    List<PhoneContact> contacts,
    Map<String, ({String pseudo, String? avatarUrl})> senoAccounts,
  ) {
    final phone = recent.phone ??
        (_phonePattern.hasMatch(recent.value)
            ? recent.value.replaceAll(' ', '')
            : null);
    final pseudo = recent.value.toLowerCase();
    for (final c in contacts) {
      for (final n in c.numbers) {
        if (n == phone || senoAccounts[n]?.pseudo.toLowerCase() == pseudo) {
          return c.name;
        }
      }
    }
    return null;
  }

  /// Récents sans doublon : une même personne enregistrée par son pseudo et
  /// par son numéro (ou par deux numéros du même contact) n'apparaît qu'une
  /// fois, à sa position la plus récente
  static List<RecentRecipient> distinct(
    List<RecentRecipient> recents,
    List<PhoneContact> contacts,
    Map<String, ({String pseudo, String? avatarUrl})> senoAccounts,
  ) {
    String identity(RecentRecipient r) {
      if (contactName(r, contacts, senoAccounts) case final name?) {
        return 'contact:${name.toLowerCase()}';
      }
      final phone = r.phone ??
          (_phonePattern.hasMatch(r.value)
              ? r.value.replaceAll(' ', '')
              : null);
      // Numéro d'un compte Seno : même identité que son pseudo
      final pseudo = phone != null ? senoAccounts[phone]?.pseudo : null;
      return pseudo != null
          ? pseudo.toLowerCase()
          : r.value.toLowerCase().replaceAll(' ', '');
    }

    final seen = <String>{};
    return [
      for (final r in recents)
        if (seen.add(identity(r))) r,
    ];
  }

  /// Répertoire (dernière copie, puis version rafraîchie)
  static final phoneContacts = ValueNotifier<List<PhoneContact>>([]);

  /// Numéros du répertoire ayant un compte Seno → pseudo et photo
  static final senoAccounts =
      ValueNotifier<Map<String, ({String pseudo, String? avatarUrl})>>({});

  static String? _contactsLoadedFor;
  static Future<void>? _refreshing;

  /// Affiche tout de suite les dernières copies (une fois par utilisateur)
  static void peekContacts() {
    final userId = _userId;
    if (userId != null && userId == _contactsLoadedFor) return;
    _contactsLoadedFor = userId;
    phoneContacts.value = peekPhoneContacts();
    senoAccounts.value = SupabaseService.peekSenoContacts();
  }

  /// Mise à jour silencieuse en arrière-plan : répertoire, comptes Seno,
  /// photos et pseudos des récents. Aucun indicateur, aucune erreur affichée ;
  /// les écrans se mettent à jour via les ValueNotifier.
  /// [askPermission] : demande l'accès aux contacts (écran d'envoi) ;
  /// sinon seul un accès déjà accordé est utilisé (accueil).
  static Future<void> refresh({bool askPermission = false}) {
    peekContacts();
    return _refreshing ??=
        _refresh(askPermission).whenComplete(() => _refreshing = null);
  }

  static Future<void> _refresh(bool askPermission) async {
    try {
      final status = askPermission
          ? await FlutterContacts.permissions.request(PermissionType.read)
          : await FlutterContacts.permissions.check(PermissionType.read);
      if (status == PermissionStatus.granted ||
          status == PermissionStatus.limited) {
        final contacts = await _readPhoneContacts();
        phoneContacts.value = contacts;
        await savePhoneContacts(contacts);
      } else if (askPermission) {
        // Accès retiré : on oublie la copie du répertoire
        phoneContacts.value = [];
        await removePhoneContacts();
      }
    } catch (_) {
      // Plateforme non supportée : on garde la dernière copie
    }
    try {
      senoAccounts.value = await SupabaseService.lookupSenoContacts(
          [for (final c in phoneContacts.value) ...c.numbers]);
    } catch (_) {
      // Hors ligne : dernière copie conservée
    }
    await _refreshRecents();
  }

  static Future<List<PhoneContact>> _readPhoneContacts() async {
    final contacts = await FlutterContacts.getAll(
      properties: {ContactProperty.name, ContactProperty.phone},
    );
    final result = <PhoneContact>[];
    for (final c in contacts) {
      // Numéros uniques du contact, dans l'ordre du répertoire
      final numbers = <String>{
        for (final phone in c.phones)
          if (localDigits(phone.number) case final digits?) digits,
      }.toList();
      if (numbers.isEmpty) continue;
      final name = c.displayName?.trim() ?? '';
      result.add((name: name.isEmpty ? numbers.first : name, numbers: numbers));
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  /// « +225 07 00 00 00 00 » → « 0700000000 » ; null si pas un numéro local
  static String? localDigits(String number) {
    var digits = number.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('00225')) digits = digits.substring(5);
    if (digits.startsWith('225') && digits.length == 13) {
      digits = digits.substring(3);
    }
    return digits.length == 10 ? digits : null;
  }

  /// Photos et pseudos des récents à jour (pseudo changé, nouvelle photo)
  static Future<void> _refreshRecents() async {
    final current = recents.value;
    if (current.isEmpty) return;
    final byPhone = <String, ({String pseudo, String? avatarUrl})>{};
    try {
      final phones = [
        for (final r in current)
          if (r.phone case final phone?) phone,
      ];
      byPhone.addAll(await SupabaseService.lookupSenoContacts(phones));
    } catch (_) {
      return; // Hors ligne : rien à mettre à jour
    }

    final updated = <RecentRecipient>[];
    for (final r in current) {
      final isPhone = _phonePattern.hasMatch(r.value);
      final account = r.phone != null ? byPhone[r.phone] : null;
      if (account != null) {
        updated.add((
          value: account.pseudo,
          avatarUrl: account.avatarUrl,
          phone: r.phone
        ));
        continue;
      }
      if (!isPhone) {
        // Pseudo sans numéro connu : photo relue par recherche exacte
        try {
          final match = (await SupabaseService.searchSenoUsers(r.value))
              .where((u) => u.pseudo.toLowerCase() == r.value.toLowerCase())
              .firstOrNull;
          // Boutique (enregistrée avant ce filtre) : retirée des récents
          if (match != null && match.isMerchant) continue;
          if (match != null) {
            updated.add((
              value: match.pseudo,
              avatarUrl: match.avatarUrl,
              phone: r.phone
            ));
            continue;
          }
        } catch (_) {}
      }
      updated.add(r);
    }

    // Seulement si quelque chose a changé, et sans écraser un ajout récent
    if (!identical(recents.value, current) || listEquals(updated, current)) {
      return;
    }
    recents.value = updated;
    await CacheStore.put(_userId, _recentsKey, [
      for (final r in updated)
        {'value': r.value, 'avatar_url': r.avatarUrl, 'phone': r.phone},
    ]);
  }
}
