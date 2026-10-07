import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_strings.dart';
import '../models/compte.dart';
import '../models/reseau.dart';
import '../services/recents_store.dart';
import '../services/payment_return_service.dart';
import '../services/supabase_service.dart';
import '../services/live_update_service.dart';
import '../theme/app_colors.dart';
import '../utils/pair_digits_formatter.dart';
import '../utils/toast_service.dart';
import '../widgets/photo_viewer.dart';
import '../widgets/pin_pad.dart';
import '../widgets/slide_button.dart';
import '../widgets/user_avatar.dart';
import 'payment_request_details_screen.dart';
import 'qr_code_viewer_screen.dart';

enum _Step { recipient, amount }

/// Envoi d'argent : destinataire (pseudo ou numéro) → montant
class SendMoneyScreen extends StatefulWidget {
  /// Destinataire déjà choisi (récent de l'accueil) : ouvre sur le montant
  final RecentRecipient? initialRecipient;

  /// Destinataire boutique : sa catégorie (icône si pas de logo)
  final String? initialCategory;

  /// Destinataire boutique : son nom
  final String? initialShopName;

  /// Ouvert depuis « Encaisser » : demande de paiement à un compte Seno
  final bool collect;

  /// Paiement d'une demande reçue : destinataire, montant et compte imposés
  final PaymentRequest? paymentRequest;

  const SendMoneyScreen(
      {super.key,
      this.initialRecipient,
      this.initialCategory,
      this.initialShopName,
      this.collect = false,
      this.paymentRequest});

  @override
  State<SendMoneyScreen> createState() => _SendMoneyScreenState();
}

class _SendMoneyScreenState extends State<SendMoneyScreen> {
  // Envoi en cours : bloque le double tap
  bool _sending = false;
  // Requête d'envoi en cours (avant la redirection opérateur) : loader
  bool _loading = false;
  // Clé d'idempotence de l'envoi en cours, gardée tant que la requête n'a pas
  // abouti (un renvoi après timeout réutilise la même clé)
  String? _idempotencyKey;
  String? _idempotencyPayload;
  static const int _minAmount = 200;
  // Plafond par envoi (table plafonds_transfert) et restants du jour / du
  // mois : la saisie est bornée au plus petit, le serveur revérifie
  int _perTransactionLimit = 1000000;
  int? _remainingDaily;
  int? _remainingMonthly;
  // La dernière touche a été refusée : le plafond s'affiche en rouge
  bool _hitMax = false;
  static final _phonePattern = RegExp(r'^[\d ]+$');

  List<RecentRecipient> get _recents => RecentsStore.recents.value;

  /// Contacts du téléphone et leurs numéros locaux (10 chiffres)
  List<PhoneContact> get _phoneContacts => RecentsStore.phoneContacts.value;

  /// Numéros du répertoire ayant un compte Seno → pseudo et photo
  Map<String, ({String pseudo, String? avatarUrl})> get _senoAccounts =>
      RecentsStore.senoAccounts.value;

  /// Recherche d'utilisateurs Seno par pseudo (hors répertoire)
  List<
      ({
        String pseudo,
        String? avatarUrl,
        String? displayName,
        bool isMerchant,
        String? category
      })> _pseudoResults = [];
  Timer? _pseudoDebounce;
  int _pseudoSearchId = 0;

  final _recipientController = TextEditingController();
  _Step _step = _Step.recipient;
  String _recipient = '';
  String? _recipientAvatarUrl;

  /// Boutique choisie : sa catégorie (icône à la place du logo manquant)
  String? _recipientCategory;

  /// Boutique choisie : son nom (au-dessus du @pseudo)
  String? _recipientShopName;
  String _amount = '';

  /// Compte débité : le compte par défaut, modifiable depuis le bandeau
  Compte? _compte;
  String? _defaultCompteId;
  List<Compte> _comptes = [];
  List<Reseau> _reseaux = [];

  /// Profil de l'utilisateur : entrée « Moi-même » (virement entre ses comptes)
  String? _myPseudo;
  String? _myAvatarUrl;

  Reseau? get _reseau =>
      _reseaux.where((r) => r.id == _compte?.idReseau).firstOrNull;

  /// Réseau sur lequel le destinataire reçoit (par défaut : celui du compte débité)
  Reseau? _toReseauChoice;
  List<Reseau> get _activeReseaux => _reseaux.where((r) => r.statut).toList();

  /// Préfixes (2 premiers chiffres) acceptés par réseau, par abréviation.
  /// Réseau absent de la table : aucun filtre.
  static const _reseauPrefixes = {
    'WAVE': ['01', '05', '07'],
    'OM': ['07'],
    'MOOV': ['01'],
    'MTN': ['05'],
  };

  /// Utilisateur Seno : ses comptes de réception (vide sinon ou pas encore chargés)
  List<({String id, String idReseau, String numeroMasque, bool isDefault})>
      _recipientComptes = [];
  String? _toCompteChoiceId;
  int _recipientComptesLoadId = 0;

  /// Compte de réception choisi, sinon son compte par défaut, sinon le premier
  ({
    String id,
    String idReseau,
    String numeroMasque,
    bool isDefault
  })? get _toCompte =>
      _recipientComptes.where((c) => c.id == _toCompteChoiceId).firstOrNull ??
      _recipientComptes.where((c) => c.isDefault).firstOrNull ??
      _recipientComptes.firstOrNull;

  /// Numéro affiché sous le pseudo : compte choisi (masqué), sinon numéro connu
  String? get _recipientNumeroLabel =>
      _toCompte?.numeroMasque ??
      (_recipientPhone != null
          ? PairDigitsFormatter.group(_recipientPhone!)
          : null);

  /// Envoi vers l'un de ses propres comptes
  bool get _isSelf =>
      !_phonePattern.hasMatch(_recipient) && _recipient == _myPseudo;

  /// Moi-même : le compte débité n'est pas proposé en réception, et inversement
  List<({String id, String idReseau, String numeroMasque, bool isDefault})>
      get _toCompteOptions => _isSelf
          ? _recipientComptes.where((c) => c.id != _compte?.id).toList()
          : _recipientComptes;

  List<Compte> get _compteOptions => _isSelf
      ? _comptes.where((c) => c.id != _toCompte?.id).toList()
      : _comptes;

  Reseau? _reseauById(String id) =>
      _reseaux.where((r) => r.id == id).firstOrNull;

  /// Réseau affiché dans la pastille : celui du compte Seno choisi, sinon
  /// le réseau de réception déduit du numéro
  Reseau? get _chipReseau {
    final compte = _toCompte;
    return compte != null ? _reseauById(compte.idReseau) : _toReseau;
  }

  Future<void> _loadRecipientComptes(String pseudo) async {
    final id = ++_recipientComptesLoadId;
    // Marchand : frais à sa charge (vérifié aussi par le serveur)
    SupabaseService.isSenoMerchant(pseudo).then((merchant) {
      if (mounted && id == _recipientComptesLoadId) {
        setState(() => _recipientIsMerchant = merchant);
      }
    }).catchError((_) {});
    try {
      final comptes = await SupabaseService.getSenoUserComptes(pseudo);
      // Ignore une réponse arrivée après un changement de destinataire
      if (mounted && id == _recipientComptesLoadId) {
        setState(() => _recipientComptes = comptes);
      }
    } catch (_) {
      // Hors ligne : choix du réseau à partir du numéro
    }
  }

  Future<void> _chooseToCompte() async {
    final textTheme = Theme.of(context).textTheme;
    final compteId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(sheetContext).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                context.tr('send_choose_recipient_account'),
                style: textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            for (final c in _toCompteOptions)
              if (_reseauById(c.idReseau) case final reseau)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  leading: _buildReseauLogo(reseau),
                  title: Text([
                    if (reseau != null) reseau.nom,
                    c.numeroMasque,
                  ].join(' · ')),
                  subtitle: c.isDefault
                      ? Text(context.tr('send_default_account'))
                      : null,
                  trailing: c.id == _toCompte?.id
                      ? const HugeIcon(
                          icon: HugeIcons.strokeRoundedTick02,
                          color: AppColors.secondary,
                        )
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(c.id),
                ),
          ],
        ),
      ),
    );
    if (compteId != null && mounted) {
      setState(() => _toCompteChoiceId = compteId);
    }
  }

  /// Numéro du destinataire (10 chiffres) ; null s'il est choisi par pseudo
  String? _recipientPhone;

  /// Réseaux possibles pour le numéro du destinataire
  List<Reseau> get _toReseaux {
    final phone = _recipientPhone;
    if (phone == null) return _activeReseaux;
    final prefix = phone.substring(0, 2);
    return _activeReseaux
        .where((r) =>
            _reseauPrefixes[r.abreviation.toUpperCase()]?.contains(prefix) ??
            true)
        .toList();
  }

  /// Choix de l'utilisateur, sinon le réseau du compte débité s'il est
  /// possible, sinon le premier réseau possible
  Reseau? get _toReseau {
    final options = _toReseaux;
    bool allowed(Reseau? r) => r != null && options.any((o) => o.id == r.id);
    if (allowed(_toReseauChoice)) return _toReseauChoice;
    if (allowed(_reseau)) return _reseau;
    return options.firstOrNull;
  }

  /// Pourcentage des frais (backend) ; null tant qu'il n'est pas connu
  double? _feePercent;

  /// Coché : l'expéditeur paie les frais ; sinon ils sont retirés du montant reçu
  bool _senderPaysFees = true;

  /// Destinataire marchand (boutique active) : il paie toujours les frais
  bool _recipientIsMerchant = false;

  bool get _effectiveSenderPaysFees =>
      widget.paymentRequest != null ||
      (!_recipientIsMerchant && _senderPaysFees);

  @override
  void initState() {
    super.initState();
    _recipientController.addListener(() => setState(() {}));
    _recipientController.addListener(_onRecipientChanged);
    // Copie en cache tout de suite : pas d'apparition tardive de « Moi-même »
    _comptes = SupabaseService.peekComptes() ?? [];
    _loadCompte();
    _loadFeePercent();
    _loadLimits();
    _loadMyProfile();
    // Dernières copies tout de suite, mise à jour silencieuse en fond
    RecentsStore.phoneContacts.addListener(_onContactsChanged);
    RecentsStore.senoAccounts.addListener(_onContactsChanged);
    RecentsStore.recents.addListener(_onContactsChanged);
    RecentsStore.refresh(askPermission: true);
    RecentsStore.load();
    final request = widget.paymentRequest;
    if (request != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _selectRecipient(request.pseudo,
            avatarUrl: request.avatarUrl, saveRecent: false);
        setState(() {
          _amount = request.amount.toString();
          _toCompteChoiceId = request.compteDestination;
        });
      });
    }
    final initial = widget.initialRecipient;
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _selectRecipient(initial.value,
              avatarUrl: initial.avatarUrl,
              phone: initial.phone,
              category: widget.initialCategory,
              shopName: widget.initialShopName);
        }
      });
    }
  }

  void _onContactsChanged() {
    if (mounted) setState(() {});
  }

  /// Contacts du téléphone filtrés par nom ou numéro
  List<({String name, List<String> numbers})> get _filteredPhoneContacts {
    final text = _recipientController.text.trim().toLowerCase();
    if (text.isEmpty) return const [];
    final digitsQuery = text.replaceAll(RegExp(r'\D'), '');
    return _phoneContacts
        .where((c) =>
            c.name.toLowerCase().contains(text) ||
            (digitsQuery.isNotEmpty &&
                c.numbers.any((n) => n.contains(digitsQuery))))
        .take(30)
        .toList();
  }

  /// Pseudo saisi (sans « @ ») : recherche après une courte pause de frappe
  void _onRecipientChanged() {
    final query =
        _recipientController.text.trim().replaceAll('@', '').toLowerCase();
    _pseudoDebounce?.cancel();
    if (query.length < 3 || _phonePattern.hasMatch(query)) {
      _pseudoSearchId++;
      if (_pseudoResults.isNotEmpty) setState(() => _pseudoResults = []);
      return;
    }
    _pseudoDebounce = Timer(const Duration(milliseconds: 300), () async {
      final id = ++_pseudoSearchId;
      try {
        final results = await SupabaseService.searchSenoUsers(query);
        // Ignore une réponse arrivée après une saisie plus récente
        if (mounted && id == _pseudoSearchId) {
          setState(() => _pseudoResults = results);
        }
      } catch (_) {
        // Hors ligne : seuls les contacts locaux sont proposés
      }
    });
  }

  Future<void> _loadMyProfile() async {
    final cached = SupabaseService.peekLockProfile();
    if (cached != null) {
      _myPseudo = cached.pseudo;
      _myAvatarUrl = cached.avatarUrl;
    }
    try {
      final profile = await SupabaseService.getLockProfile();
      if (mounted) {
        setState(() {
          _myPseudo = profile.pseudo;
          _myAvatarUrl = profile.avatarUrl;
        });
      }
    } catch (_) {
      // Hors ligne sans cache : pas d'entrée « Moi-même »
    }
  }

  Future<void> _loadLimits() async {
    try {
      final limits = await SupabaseService.getAccountLimits();
      if (mounted) setState(() => _perTransactionLimit = limits.perTransaction);
      final usage = await SupabaseService.getLimitsUsage();
      if (!mounted) return;
      setState(() {
        _remainingDaily = (limits.daily - usage.daily).clamp(0, limits.daily);
        _remainingMonthly =
            (limits.monthly - usage.monthly).clamp(0, limits.monthly);
      });
    } catch (_) {
      // Hors ligne : plafond par envoi seul, le serveur tranche
    }
  }

  /// Restant le plus contraignant (jour ou mois), null si inconnu
  /// Encaisser : les plafonds d'envoi de l'utilisateur ne s'appliquent pas
  int? get _remaining => widget.collect ? null : _remainingOrNull;

  int? get _remainingOrNull => switch ((_remainingDaily, _remainingMonthly)) {
        (final d?, final m?) => d < m ? d : m,
        (final d?, null) => d,
        (null, final m?) => m,
        _ => null,
      };

  int get _maxAmount {
    final remaining = _remaining;
    return remaining != null && remaining < _perTransactionLimit
        ? remaining
        : _perTransactionLimit;
  }

  Future<void> _loadFeePercent() async {
    try {
      final percent = await SupabaseService.getFeePercent();
      if (mounted) setState(() => _feePercent = percent);
    } catch (_) {
      // Hors ligne sans cache : frais et total restent masqués
    }
  }

  @override
  void dispose() {
    RecentsStore.phoneContacts.removeListener(_onContactsChanged);
    RecentsStore.senoAccounts.removeListener(_onContactsChanged);
    RecentsStore.recents.removeListener(_onContactsChanged);
    _pseudoDebounce?.cancel();
    _recipientController.dispose();
    super.dispose();
  }

  Future<void> _loadCompte() async {
    try {
      final results = await Future.wait([
        SupabaseService.getDefaultCompte(),
        SupabaseService.getComptes(),
        SupabaseService.getReseaux(),
      ]);
      final defaultCompte = results[0] as Compte?;
      final comptes = results[1] as List<Compte>;
      if (!mounted) return;
      setState(() {
        _comptes = comptes;
        _reseaux = results[2] as List<Reseau>;
        _defaultCompteId = defaultCompte?.id;
        // Compte par défaut en priorité, sinon le premier
        _compte = comptes.where((c) => c.id == defaultCompte?.id).firstOrNull ??
            defaultCompte ??
            comptes.firstOrNull;
      });
    } catch (_) {
      // Hors ligne : la ligne du compte débité reste masquée
    }
  }

  Future<void> _chooseCompte() async {
    final textTheme = Theme.of(context).textTheme;
    final compte = await showModalBottomSheet<Compte>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(sheetContext).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                // Encaisser : compte crédité, pas débité
                context.tr(widget.collect
                    ? 'collect_choose_account'
                    : 'send_choose_account'),
                style: textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            for (final c in _compteOptions)
              if (_reseaux.where((r) => r.id == c.idReseau).firstOrNull
                  case final reseau)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  leading: _buildReseauLogo(reseau),
                  title: Text([
                    if (reseau != null) reseau.nom,
                    PairDigitsFormatter.group(c.numero),
                  ].join(' · ')),
                  subtitle: c.id == _defaultCompteId
                      ? Text(context.tr('send_default_account'))
                      : null,
                  trailing: c.id == _compte?.id
                      ? const HugeIcon(
                          icon: HugeIcons.strokeRoundedTick02,
                          color: AppColors.secondary,
                        )
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(c),
                ),
          ],
        ),
      ),
    );
    if (compte != null && mounted) setState(() => _compte = compte);
  }

  Future<void> _chooseToReseau() async {
    final textTheme = Theme.of(context).textTheme;
    final reseau = await showModalBottomSheet<Reseau>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(sheetContext).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                context.tr('send_choose_network'),
                style: textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            for (final r in _toReseaux)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                leading: _buildReseauLogo(r),
                title: Text(r.nom),
                trailing: r.id == _toReseau?.id
                    ? const HugeIcon(
                        icon: HugeIcons.strokeRoundedTick02,
                        color: AppColors.secondary,
                      )
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(r),
              ),
          ],
        ),
      ),
    );
    if (reseau != null && mounted) setState(() => _toReseauChoice = reseau);
  }

  /// Logo du réseau (abréviation si l'image ne charge pas)
  Widget _buildReseauLogo(Reseau? reseau, {double size = 44}) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    Widget fallback() => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onSurface.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(size / 4),
          ),
          child: Text(
            reseau?.abreviation ?? '',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        );
    if (reseau == null || reseau.logo.isEmpty) return fallback();
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 4),
      child: Image(
        image: CachedNetworkImageProvider(reseau.logo),
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => fallback(),
      ),
    );
  }

  String? _recentContactName(RecentRecipient recent) =>
      RecentsStore.contactName(recent, _phoneContacts, _senoAccounts);

  /// Nom du destinataire dans le répertoire (hors envoi à soi-même)
  String? get _recipientContactName => _recipient == _myPseudo
      ? null
      : _recipientShopName ??
          _recentContactName(
              (value: _recipient, avatarUrl: null, phone: _recipientPhone));

  /// Récents filtrés par la saisie (pseudo ou numéro, sans « @ » ni espaces)
  List<({String value, String? avatarUrl, String? phone})>
      get _filteredRecents {
    String norm(String v) =>
        v.toLowerCase().replaceAll('@', '').replaceAll(' ', '');
    final query = norm(_recipientController.text.trim());
    if (query.isEmpty) return _recents;
    return _recents
        .where((r) =>
            norm(r.value).contains(query) ||
            (r.phone?.contains(query) ?? false) ||
            (_recentContactName(r)
                    ?.toLowerCase()
                    .replaceAll(' ', '')
                    .contains(query) ??
                false))
        .toList();
  }

  /// Un seul numéro : sélection directe ; sinon choix du numéro
  /// Numéro avec compte Seno : envoi au pseudo (avec sa photo)
  void _selectNumber(String number) {
    final account = _senoAccounts[number];
    if (account != null) {
      _selectRecipient(account.pseudo,
          avatarUrl: account.avatarUrl, phone: number);
    } else {
      _selectRecipient(PairDigitsFormatter.group(number));
    }
  }

  /// Premier compte Seno parmi les numéros du contact
  ({String pseudo, String? avatarUrl})? _senoAccountOf(List<String> numbers) {
    for (final n in numbers) {
      final account = _senoAccounts[n];
      if (account != null) return account;
    }
    return null;
  }

  Future<void> _onPhoneContactTap(
      ({String name, List<String> numbers}) contact) async {
    // Encaisser : on choisit le compte Seno, jamais un numéro
    if (widget.collect) {
      if (_senoAccountOf(contact.numbers) case final account?) {
        _selectRecipient(account.pseudo, avatarUrl: account.avatarUrl);
      }
      return;
    }
    if (contact.numbers.length == 1) {
      _selectNumber(contact.numbers.first);
      return;
    }
    FocusScope.of(context).unfocus();
    final textTheme = Theme.of(context).textTheme;
    final number = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        // Marge sous la barre de navigation système (affichage bord à bord)
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(sheetContext).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                context.tr('send_choose_number'),
                style: textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                contact.name,
                style: textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 8),
            for (final n in contact.numbers)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                leading: const HugeIcon(
                  icon: HugeIcons.strokeRoundedCall,
                  size: 20,
                  color: AppColors.secondary,
                ),
                title: Text(PairDigitsFormatter.group(n)),
                subtitle: _senoAccounts[n] != null
                    ? Text('@${_senoAccounts[n]!.pseudo}')
                    : null,
                trailing: _senoAccounts[n] != null
                    ? UserAvatar(
                        pseudo: _senoAccounts[n]!.pseudo,
                        avatarUrl: _senoAccounts[n]!.avatarUrl,
                        radius: 16,
                        backgroundColor: AppColors.secondary,
                        foregroundColor: Colors.white,
                      )
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(n),
              ),
          ],
        ),
      ),
    );
    if (number != null && mounted) _selectNumber(number);
  }

  static const _headerDuration = Duration(milliseconds: 250);

  /// Saisie en cours : en-tête compact (titre à côté du retour, sans sous-titre)
  bool get _headerCollapsed =>
      _step == _Step.recipient && _recipientController.text.isNotEmpty;

  /// Pseudos Seno des contacts du répertoire
  Set<String> get _contactSenoPseudos =>
      {for (final a in _senoAccounts.values) a.pseudo};

  bool get _recipientValid {
    final text = _recipientController.text.trim();
    if (text.isEmpty) return false;
    // Encaisser : pseudo d'un compte Seno du répertoire uniquement
    if (widget.collect) {
      return _contactSenoPseudos.any(
          (p) => p.toLowerCase() == text.replaceAll('@', '').toLowerCase());
    }
    if (!_phonePattern.hasMatch(text)) return text.length >= 3;
    final digits = text.replaceAll(' ', '');
    return digits.length == 10 && _validPhonePrefix.hasMatch(digits);
  }

  /// Numéros locaux acceptés : 01, 05 ou 07
  static final _validPhonePrefix = RegExp(r'^0[157]');

  void _selectRecipient(String value,
      {String? avatarUrl,
      String? phone,
      String? category,
      String? shopName,
      bool saveRecent = true}) {
    FocusScope.of(context).unfocus();
    setState(() {
      _recipient = value;
      _recipientAvatarUrl = avatarUrl;
      _recipientCategory = category;
      _recipientShopName = shopName;
      _toReseauChoice = null;
      _recipientComptes = [];
      _toCompteChoiceId = null;
      _recipientIsMerchant = false;
      // Numéro saisi ou choisi : sert à filtrer les réseaux de réception
      _recipientPhone = phone ??
          (_phonePattern.hasMatch(value) ? value.replaceAll(' ', '') : null);
      _amount = '';
      _step = _Step.amount;
    });
    if (saveRecent) {
      RecentsStore.add(value, avatarUrl: avatarUrl, phone: _recipientPhone);
    }
    // Utilisateur Seno (pseudo) : proposer ses comptes de réception
    _recipientComptesLoadId++;
    if (value == _myPseudo) {
      // Moi-même : choix parmi ses propres comptes ajoutés
      setState(() => _recipientComptes = [
            for (final c in _comptes)
              (
                id: c.id,
                idReseau: c.idReseau,
                numeroMasque: PairDigitsFormatter.group(c.numero),
                isDefault: c.id == _defaultCompteId,
              ),
          ]);
      // Par défaut : un autre compte que celui débité
      _toCompteChoiceId =
          _comptes.where((c) => c.id != _compte?.id).firstOrNull?.id;
    } else if (!_phonePattern.hasMatch(value)) {
      _loadRecipientComptes(value);
    }
  }

  void _showRecipientPhoto() {
    final url = _recipientAvatarUrl;
    if (url != null) showPhotoViewer(context, url, heroTag: 'recipient-photo');
  }

  void _onDigit(String digit) {
    if (_amount.isEmpty && digit == '0') return;
    // Au-delà du maximum : la touche est ignorée
    if (int.parse(_amount + digit) > _maxAmount) {
      HapticFeedback.heavyImpact();
      setState(() => _hitMax = true);
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _amount += digit;
      _hitMax = false;
    });
  }

  void _onDelete() {
    if (_amount.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _amount = _amount.substring(0, _amount.length - 1);
      _hitMax = false;
    });
  }

  /// Encaisser : envoie la demande de paiement (crédit sur le compte choisi)
  Future<void> _submitCollect() async {
    final compte = _compte;
    if (_sending || compte == null) return;
    _sending = true;
    HapticFeedback.mediumImpact();
    setState(() => _loading = true);
    try {
      final id = await SupabaseService.createPaymentRequest(
        payerPseudo: _recipient,
        compteId: compte.id,
        amount: _amountValue,
      );
      SupabaseService.paymentRequestsRevision.value++;
      if (!mounted) return;
      ToastService.showSuccess(
          context, context.tr('collect_sent', {'pseudo': '@$_recipient'}));
      // Détail de la demande posé directement sur l'accueil : son retour y
      // ramène (comme la page de suivi d'un envoi)
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => PaymentRequestDetailsScreen(
            request: PaymentRequest(
              id: id,
              received: false,
              pseudo: _recipient,
              avatarUrl: _recipientAvatarUrl,
              amount: _amountValue,
              compteDestination: null,
              statut: 'en_attente',
              createdAt: DateTime.now(),
            ),
          ),
        ),
        (route) => route.isFirst,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ToastService.showError(
          context,
          context.tr(e is AuthOtpException && e.code == 'too_many_requests'
              ? 'collect_too_many'
              : e is AuthOtpException && e.code == 'invalid_recipient'
                  ? 'collect_invalid_recipient'
                  : 'collect_failed'));
    } finally {
      _sending = false;
    }
  }

  /// Sheet de confirmation : se valide automatiquement après 15 s
  Future<void> _submit() async {
    if (_sending) return;
    _sending = true;
    try {
      await _doSubmit();
    } finally {
      _sending = false;
    }
  }

  Future<void> _doSubmit() async {
    HapticFeedback.mediumImpact();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (_) => _SendConfirmSheet(
        recipient: _isSelf ? context.tr('send_myself') : _recipient,
        // Demande reçue : numéro du demandeur non affiché
        recipientDetail:
            widget.paymentRequest == null ? _recipientNumeroLabel : null,
        received: '${_formatAmount(_received.toString())} FCFA',
        fees: '${_formatAmount(_fee.toString())} FCFA',
        total: '${_formatAmount(_total.toString())} FCFA',
      ),
    );
    if (confirmed != true || !mounted) return;

    final compte = _compte;
    final isPhone = _phonePattern.hasMatch(_recipient);
    final toCompte = isPhone ? null : _toCompte;
    final toReseau = _toReseau;
    if (compte == null) {
      ToastService.showError(context, context.tr('send_failed'));
      return;
    }
    if (!isPhone && toCompte == null) {
      ToastService.showError(context, context.tr('send_no_recipient_account'));
      return;
    }
    if (isPhone && (_recipientPhone == null || toReseau == null)) {
      ToastService.showError(context, context.tr('send_failed'));
      return;
    }

    // Nouvelle clé si les paramètres de l'envoi ont changé depuis la dernière tentative
    final payload = [
      compte.id,
      _amountValue,
      _effectiveSenderPaysFees,
      toCompte?.id,
      isPhone ? _recipientPhone : null,
      isPhone ? toReseau!.id : null,
    ].join('|');
    if (_idempotencyKey == null || _idempotencyPayload != payload) {
      _idempotencyKey = SupabaseService.newIdempotencyKey();
      _idempotencyPayload = payload;
    }

    ({String id, String redirectUrl}) started;
    setState(() => _loading = true);
    try {
      started = await SupabaseService.sendMoney(
        idempotencyKey: _idempotencyKey!,
        compteId: compte.id,
        amount: _amountValue,
        senderPaysFees: _effectiveSenderPaysFees,
        label: _isSelf ? (_myPseudo ?? _recipient) : _recipient,
        toCompteId: toCompte?.id,
        toNumero: isPhone ? _recipientPhone : null,
        toReseauId: isPhone ? toReseau!.id : null,
        paymentRequestId: widget.paymentRequest?.id,
      );
    } catch (e) {
      // Échec définitif côté serveur : la clé est consommée, la prochaine
      // tentative en génère une nouvelle. Erreur réseau : on la garde.
      final limitExceeded = e is AuthOtpException && e.code == 'limit_exceeded';
      final blocked = e is AuthOtpException && e.code == 'number_blocked';
      if (e is AuthOtpException && e.code == 'payment_failed') {
        _idempotencyKey = null;
      }
      if (mounted) {
        setState(() => _loading = false);
        ToastService.showError(
            context,
            context.tr(limitExceeded
                ? 'send_limit_exceeded'
                : blocked
                    ? 'send_number_blocked'
                    : 'send_failed'));
        // Restants périmés (envoi depuis un autre appareil) : rechargés
        if (limitExceeded) _loadLimits();
      }
      return;
    }
    _idempotencyKey = null;
    if (!mounted) return;

    // Live Update Android : suivi visible hors de l'app (validation Wave…)
    LiveTransferTracker.start(
      transfertId: started.id,
      amount: '${_formatAmount(_total.toString())} FCFA',
      locale: Localizations.localeOf(context),
    );

    // Page de suivi posée directement sur l'accueil : sa fermeture y ramène,
    // quel que soit l'écran d'origine (QR, détails de transaction…)
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => _SendProgressPage(
          transfertId: started.id,
          redirectUrl: started.redirectUrl,
        ),
      ),
      (route) => route.isFirst,
    );
  }

  /// Ouvert sur un destinataire (scan, récent, renvoi) : le retour depuis
  /// le montant ferme l'écran au lieu de revenir à la recherche
  bool get _backClosesFromAmount =>
      widget.initialRecipient != null || widget.paymentRequest != null;

  void _onBack() {
    if (_loading) return;
    if (_step == _Step.amount && !_backClosesFromAmount) {
      setState(() => _step = _Step.recipient);
      return;
    }
    Navigator.of(context).pop();
  }

  int get _amountValue => int.tryParse(_amount) ?? 0;
  bool get _amountValid =>
      _amountValue >= _minAmount && _amountValue <= _maxAmount;
  int get _fee => (_amountValue * (_feePercent ?? 0) / 100).ceil();
  int get _total =>
      _effectiveSenderPaysFees ? _amountValue + _fee : _amountValue;
  int get _received =>
      _effectiveSenderPaysFees ? _amountValue : _amountValue - _fee;

  /// 25000 → « 25 000 »
  String _formatAmount(String digits) {
    if (digits.isEmpty) return '0';
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final viewPadding = MediaQuery.of(context).viewPadding;

    return PopScope(
      canPop: !_loading && (_step == _Step.recipient || _backClosesFromAmount),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Stack(
          children: [
            // En recherche : le titre remonte à hauteur du bouton retour
            AnimatedPadding(
              duration: _headerDuration,
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.fromLTRB(
                24,
                viewPadding.top + (_headerCollapsed ? 8 : 72),
                24,
                viewPadding.bottom + 32,
              ),
              child: _step == _Step.recipient
                  ? _buildRecipientStep(textTheme)
                  : _buildAmountStep(textTheme),
            ),
            Positioned(
              top: viewPadding.top + 8,
              left: 8,
              child: IconButton(
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowLeft01,
                  color: textTheme.bodyLarge?.color ?? Colors.black,
                ),
                onPressed: _onBack,
              ),
            ),
            // Montant : « Demander à » / « Envoyer à » à côté du bouton retour
            if (_step == _Step.amount)
              Positioned(
                top: viewPadding.top + 8,
                left: 56,
                right: 24,
                height: 48,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context
                        .tr(widget.collect ? 'collect_from' : 'send_to_title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecipientStep(TextTheme textTheme) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final pill = OutlineInputBorder(
      borderRadius: BorderRadius.circular(50),
      borderSide: BorderSide.none,
    );
    // Encaisser : seulement les contacts ayant un compte Seno
    final phoneContacts = widget.collect
        ? _filteredPhoneContacts
            .where((c) => _senoAccountOf(c.numbers) != null)
            .toList()
        : _filteredPhoneContacts;
    // Récents du répertoire (numéro ou pseudo) : affichés dans « Contacts »
    final contactNumbers = {for (final c in phoneContacts) ...c.numbers};
    final contactPseudos = {
      for (final c in phoneContacts)
        if (_senoAccountOf(c.numbers) case final account?) account.pseudo,
    };
    final contacts = _filteredRecents
        // Encaisser : seulement les comptes Seno du répertoire
        .where((r) => !widget.collect || _contactSenoPseudos.contains(r.value))
        .where((r) =>
            !(r.phone != null && contactNumbers.contains(r.phone)) &&
            !(_phonePattern.hasMatch(r.value)
                ? contactNumbers.contains(r.value.replaceAll(' ', ''))
                : contactPseudos.contains(r.value)))
        .toList();
    // Déjà visibles plus haut (récents ou répertoire) : pas de doublon
    final shownPseudos = {
      for (final c in contacts)
        if (!_phonePattern.hasMatch(c.value)) c.value,
      for (final c in phoneContacts)
        if (_senoAccountOf(c.numbers) case final account?) account.pseudo,
    };
    // Encaisser : pas de recherche hors répertoire (ni boutiques)
    final pseudoResults = widget.collect
        ? const <Never>[]
        : _pseudoResults
            .where((u) => !shownPseudos.contains(u.pseudo))
            .toList();
    final searching = _recipientController.text.trim().isNotEmpty;
    // Plusieurs comptes : envoi vers un autre de ses propres comptes
    final showSelf = !widget.collect &&
        !searching &&
        _comptes.length > 1 &&
        (_myPseudo?.isNotEmpty ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Titre : glisse à côté du bouton retour (48 px + marges)
        AnimatedContainer(
          duration: _headerDuration,
          curve: Curves.easeOutCubic,
          height: _headerCollapsed ? 48 : 40,
          padding: EdgeInsets.symmetric(horizontal: _headerCollapsed ? 40 : 0),
          alignment: Alignment.centerLeft,
          child: AnimatedDefaultTextStyle(
            duration: _headerDuration,
            curve: Curves.easeOutCubic,
            style: (_headerCollapsed
                    ? textTheme.titleLarge
                    : textTheme.headlineLarge)!
                .copyWith(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: Text(
                context.tr(widget.collect ? 'collect_title' : 'send_money')),
          ),
        ),
        // Sous-titre : se replie en fondu
        ClipRect(
          child: AnimatedAlign(
            duration: _headerDuration,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            heightFactor: _headerCollapsed ? 0 : 1,
            child: AnimatedOpacity(
              duration: _headerDuration,
              opacity: _headerCollapsed ? 0 : 1,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  context.tr(widget.collect
                      ? 'collect_recipient_subtitle'
                      : 'send_recipient_subtitle'),
                  style: textTheme.bodyLarge
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ),
            ),
          ),
        ),
        AnimatedContainer(
          duration: _headerDuration,
          curve: Curves.easeOutCubic,
          height: _headerCollapsed ? 16 : 32,
        ),
        TextField(
          controller: _recipientController,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            // Numéro : chiffres groupés 2 par 2 ; pseudo : texte libre
            TextInputFormatter.withFunction((oldValue, newValue) =>
                _phonePattern.hasMatch(newValue.text)
                    ? PairDigitsFormatter(maxDigits: 10)
                        .formatEditUpdate(oldValue, newValue)
                    : newValue),
          ],
          onSubmitted: (_) {
            if (_recipientValid) {
              _selectRecipient(_recipientController.text.trim());
            }
          },
          decoration: InputDecoration(
            hintText: context.tr('send_recipient_hint'),
            filled: true,
            fillColor: onSurface.withValues(alpha: 0.05),
            prefixIcon: Padding(
              padding: const EdgeInsets.all(14),
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedSearch01,
                size: 20,
                color: onSurface.withValues(alpha: 0.5),
              ),
            ),
            // Scanner : ouvre l'écran QR sur l'onglet « Envoyer » (caméra)
            // Masqué en mode Encaisser
            suffixIcon: widget.collect
                ? null
                : IconButton(
                    icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedQrCode01,
                      size: 20,
                      color: onSurface.withValues(alpha: 0.7),
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const QRCodeViewerScreen(scanOnly: true),
                      ),
                    ),
                  ),
            // Pilule : tous les états (le thème peut surcharger enabled/focused)
            border: pill,
            enabledBorder: pill,
            focusedBorder: pill,
          ),
        ),
        const SizedBox(height: 32),
        if (showSelf) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: UserAvatar(
              pseudo: _myPseudo,
              avatarUrl: _myAvatarUrl,
              radius: 22,
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.white,
            ),
            title: Text(context.tr('send_myself'),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('@$_myPseudo'),
            trailing: HugeIcon(
              icon: HugeIcons.strokeRoundedArrowRight01,
              size: 18,
              color: onSurface.withValues(alpha: 0.4),
            ),
            onTap: () => _selectRecipient(_myPseudo!,
                avatarUrl: _myAvatarUrl, saveRecent: false),
          ),
          const SizedBox(height: 16),
        ],
        Text(
          context.tr(searching ? 'send_results' : 'send_recents'),
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              if (contacts.isEmpty &&
                  phoneContacts.isEmpty &&
                  pseudoResults.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    context
                        .tr(searching ? 'send_no_results' : 'send_no_recents'),
                    style: textTheme.bodyMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              for (final c in contacts.where((c) => c.value != _myPseudo))
                if ((
                  isPhone: _phonePattern.hasMatch(c.value),
                  name: _recentContactName(c),
                )
                    case (isPhone: final isPhone, name: final name))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: UserAvatar(
                      pseudo: isPhone ? name : c.value,
                      avatarUrl: c.avatarUrl,
                      radius: 22,
                      backgroundColor: AppColors.secondary,
                      foregroundColor: Colors.white,
                    ),
                    // Dans le répertoire : nom du contact, puis pseudo / numéro
                    title: Text(name ?? (isPhone ? c.value : '@${c.value}'),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: switch ((name, isPhone)) {
                      (_?, true) => Text(c.value),
                      (_?, false) => Text('@${c.value}'),
                      (null, false) when c.phone != null && !widget.collect =>
                        Text(PairDigitsFormatter.group(c.phone!)),
                      _ => null,
                    },
                    trailing: HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowRight01,
                      size: 18,
                      color: onSurface.withValues(alpha: 0.4),
                    ),
                    onTap: () => _selectRecipient(c.value,
                        avatarUrl: c.avatarUrl, phone: c.phone),
                  ),
              if (pseudoResults.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  context.tr('send_seno_users'),
                  style: textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                for (final u in pseudoResults)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: UserAvatar(
                      pseudo: u.pseudo,
                      avatarUrl: u.avatarUrl,
                      merchantCategory: u.isMerchant ? u.category : null,
                      radius: 22,
                      backgroundColor: AppColors.secondary,
                      foregroundColor: Colors.white,
                    ),
                    title: Text(
                        u.isMerchant && u.displayName != null
                            ? u.displayName!
                            : '@${u.pseudo}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    subtitle: u.isMerchant
                        ? Row(
                            children: [
                              Flexible(
                                child: Text('@${u.pseudo}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.secondary
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(50),
                                ),
                                child: Text(
                                  context.tr('send_shop_badge'),
                                  style: textTheme.labelSmall?.copyWith(
                                      color: AppColors.secondary,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          )
                        : null,
                    trailing: HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowRight01,
                      size: 18,
                      color: onSurface.withValues(alpha: 0.4),
                    ),
                    // Boutique : pas ajoutée aux récents
                    onTap: () => _selectRecipient(u.pseudo,
                        avatarUrl: u.avatarUrl,
                        category: u.isMerchant ? u.category : null,
                        shopName: u.isMerchant ? u.displayName : null,
                        saveRecent: !u.isMerchant),
                  ),
              ],
              if (phoneContacts.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  context.tr('send_contacts'),
                  style: textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                for (final c in phoneContacts)
                  if (_senoAccountOf(c.numbers) case final seno)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      // Compte Seno : photo et pseudo ; sinon initiales du nom
                      leading: UserAvatar(
                        pseudo: seno?.pseudo ?? c.name,
                        avatarUrl: seno?.avatarUrl,
                        radius: 22,
                        backgroundColor: AppColors.secondary,
                        foregroundColor: Colors.white,
                      ),
                      title: Text(seno != null ? '@${seno.pseudo}' : c.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        [
                          if (seno != null) c.name,
                          // Encaisser : pas de numéros affichés
                          if (!widget.collect) ...[
                            PairDigitsFormatter.group(c.numbers.first),
                            if (c.numbers.length > 1)
                              context.tr('send_more_numbers',
                                  {'count': '${c.numbers.length - 1}'}),
                          ],
                        ].join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: HugeIcon(
                        icon: HugeIcons.strokeRoundedArrowRight01,
                        size: 18,
                        color: onSurface.withValues(alpha: 0.4),
                      ),
                      onTap: () => _onPhoneContactTap(c),
                    ),
              ],
            ],
          ),
        ),
        _buildPrimaryButton(
          label: context.tr('continue'),
          onPressed: _recipientValid
              ? () => _selectRecipient(_recipientController.text.trim())
              : null,
        ),
      ],
    );
  }

  /// Sous le montant : plafond atteint, ou maximum / minimum non respecté
  /// (le maximum seulement quand une touche le dépasse)
  Widget _buildLimitHint(TextTheme textTheme) {
    final remaining = _remaining;
    final String? text;
    var error = _hitMax;
    if (remaining != null && remaining < _minAmount) {
      text = context.tr('send_limit_reached');
      error = true;
    } else if (_hitMax) {
      text = context.tr('send_max_amount',
          {'amount': '${_formatAmount(_maxAmount.toString())} FCFA'});
    } else if (_amount.isNotEmpty && _amountValue < _minAmount) {
      text = context.tr('send_min_amount',
          {'amount': '${_formatAmount(_minAmount.toString())} FCFA'});
      error = true;
    } else {
      text = null;
    }
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: textTheme.bodySmall?.copyWith(
          color: error ? Colors.red : AppColors.textSecondary,
          fontWeight: error ? FontWeight.w600 : null,
        ),
      ),
    );
  }

  /// Ligne du destinataire : les infos prennent la place restante, sauf en
  /// Encaisser (colonne centrée, pas de contrainte de hauteur)
  Widget _expandedUnlessCollect(Widget child) =>
      _centeredRecipient ? child : Expanded(child: child);

  /// Encaisser ou demande reçue : infos de l'autre partie centrées
  bool get _centeredRecipient =>
      widget.collect || widget.paymentRequest != null;

  Widget _buildAmountStep(TextTheme textTheme) {
    final isPhone = _phonePattern.hasMatch(_recipient);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Destinataire (Encaisser / demande reçue : centré, photo au-dessus)
        Flex(
          direction: _centeredRecipient ? Axis.vertical : Axis.horizontal,
          children: [
            // Photo : agrandie en plein écran au toucher
            GestureDetector(
              onTap: _recipientAvatarUrl != null ? _showRecipientPhoto : null,
              child: Hero(
                tag: 'recipient-photo',
                child: UserAvatar(
                  pseudo: isPhone ? null : _recipient,
                  avatarUrl: _recipientAvatarUrl,
                  merchantCategory: _recipientCategory,
                  radius: _centeredRecipient ? 32 : 22,
                  backgroundColor: AppColors.secondary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            SizedBox(
                width: _centeredRecipient ? 0 : 12,
                height: _centeredRecipient ? 8 : 0),
            _expandedUnlessCollect(
              Column(
                crossAxisAlignment: _centeredRecipient
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: [
                  // « Envoyer à » / « Demander à » : dans l'en-tête
                  // Contact du répertoire : son nom au-dessus du pseudo/numéro
                  if (_recipientContactName != null)
                    Text(
                      _recipientContactName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  Text(
                    // Envoi à soi-même : « Moi-même » à la place du pseudo
                    isPhone
                        ? _recipient
                        : _recipient == _myPseudo
                            ? context.tr('send_myself')
                            : '@$_recipient',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _recipientContactName != null
                        ? textTheme.bodyMedium
                            ?.copyWith(color: AppColors.textSecondary)
                        : textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  // Pseudo : numéro du compte choisi (masqué), sinon numéro connu
                  // (Encaisser : jamais de numéro)
                  // (demande reçue : ni numéro ni réseau du demandeur)
                  if (!isPhone &&
                      !widget.collect &&
                      widget.paymentRequest == null &&
                      _recipientNumeroLabel != null)
                    Text(
                      _recipientNumeroLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                ],
              ),
            ),
            // Réseau de réception : logo + flèche, choix parmi les réseaux actifs
            // Encaisser / demande reçue : pas de réseau du destinataire
            if (_chipReseau != null &&
                !widget.collect &&
                widget.paymentRequest == null) ...[
              const SizedBox(width: 12),
              GestureDetector(
                // Demande reçue : compte crédité imposé par le demandeur
                onTap: widget.paymentRequest != null
                    ? null
                    : _recipientComptes.isNotEmpty
                        ? (_toCompteOptions.length > 1 ? _chooseToCompte : null)
                        : (_toReseaux.length > 1 ? _chooseToReseau : null),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildReseauLogo(_chipReseau, size: 32),
                      const SizedBox(width: 6),
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedArrowDown01,
                        size: 16,
                        color: textTheme.bodyLarge?.color ?? Colors.black,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        const Spacer(),
        // Montant
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: _formatAmount(_amount)),
                TextSpan(
                  text: ' FCFA',
                  style: textTheme.titleLarge
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
            style: textTheme.displayMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: _amount.isEmpty ? AppColors.textSecondary : null,
            ),
          ),
        ),
        _buildLimitHint(textTheme),
        const SizedBox(height: 16),
        if (_compte != null)
          Center(
            child: GestureDetector(
              // Plusieurs comptes : choix du compte à débiter
              onTap: _compteOptions.length > 1 ? _chooseCompte : null,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        context
                            .tr(widget.collect ? 'collect_to' : 'send_from', {
                          'account': [
                            if (_reseau != null) _reseau!.nom,
                            PairDigitsFormatter.group(_compte!.numero),
                          ].join(' · '),
                        }),
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.textOnPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (_compteOptions.length > 1) ...[
                      const SizedBox(width: 4),
                      const HugeIcon(
                        icon: HugeIcons.strokeRoundedArrowDown01,
                        size: 16,
                        color: AppColors.textOnPrimary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        const Spacer(),
        // Encaisser : les frais sont à la charge du payeur, rien à afficher
        if (_feePercent != null && !widget.collect) ...[
          // Boutique : le client paie le montant saisi, rien à afficher
          if (!_recipientIsMerchant) ...[
            // Demande reçue : frais à la charge du payeur, non modifiable
            if (widget.paymentRequest == null) _buildFeesToggle(textTheme),
            const SizedBox(height: 8),
            _buildSummaryRow(textTheme, context.tr('send_receives'), _received),
            const SizedBox(height: 4),
            _buildSummaryRow(textTheme, context.tr('send_total'), _total,
                bold: true),
          ],
          const SizedBox(height: 24),
        ],
        // Demande reçue : montant imposé, pas de clavier
        if (widget.paymentRequest == null) ...[
          IgnorePointer(
            ignoring: _loading,
            child: PinKeypad(onDigit: _onDigit, onDelete: _onDelete),
          ),
          const SizedBox(height: 24),
        ],
        SlideButton(
          label: context.tr(widget.collect ? 'collect_slide' : 'send_slide'),
          loading: _loading,
          onConfirmed: widget.collect
              ? (_amountValid && _compte != null ? _submitCollect : null)
              : !_amountValid || _feePercent == null || _received <= 0
                  ? null
                  : _submit,
        ),
      ],
    );
  }

  Widget _buildFeesToggle(TextTheme textTheme) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr('send_pay_fees'), style: textTheme.bodyMedium),
              Text(
                '${_formatAmount(_fee.toString())} FCFA',
                style: textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        Transform.scale(
          scale: 0.8,
          alignment: Alignment.centerRight,
          child: Switch(
            value: _senderPaysFees,
            activeTrackColor: AppColors.secondary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (value) {
              HapticFeedback.selectionClick();
              setState(() => _senderPaysFees = value);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(TextTheme textTheme, String label, int value,
      {bool bold = false}) {
    final style = textTheme.bodyMedium?.copyWith(
      fontWeight: bold ? FontWeight.bold : FontWeight.w500,
      color: bold ? null : AppColors.textSecondary,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text('${_formatAmount(value.toString())} FCFA', style: style),
      ],
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required VoidCallback? onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        overlayColor: Colors.transparent,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.black.withValues(alpha: 0.2),
        disabledForegroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _SendConfirmSheet extends StatefulWidget {
  final String recipient;
  final String? recipientDetail;
  final String received;
  final String fees;
  final String total;

  const _SendConfirmSheet({
    required this.recipient,
    required this.recipientDetail,
    required this.received,
    required this.fees,
    required this.total,
  });

  @override
  State<_SendConfirmSheet> createState() => _SendConfirmSheetState();
}

class _SendConfirmSheetState extends State<_SendConfirmSheet> {
  static const _delay = 15;
  int _secondsLeft = _delay;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft <= 1) {
        _confirm();
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  void _confirm() {
    _timer?.cancel();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Widget _row(TextTheme textTheme, String label, String value,
      {bool bold = false}) {
    final style = textTheme.bodyMedium?.copyWith(
      fontWeight: bold ? FontWeight.bold : FontWeight.w500,
      color: bold ? null : AppColors.textSecondary,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          const SizedBox(width: 16),
          Flexible(
            child: Text(value, style: style, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 0, 24, MediaQuery.viewPaddingOf(context).bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr('send_confirm_title'),
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          _row(
            textTheme,
            context.tr('send_confirm_to'),
            [widget.recipient, if (widget.recipientDetail case final d?) d]
                .join(' · '),
          ),
          _row(textTheme, context.tr('send_receives'), widget.received),
          _row(textTheme, context.tr('send_confirm_fees'), widget.fees),
          _row(textTheme, context.tr('send_total'), widget.total, bold: true),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 1, end: 0),
              duration: const Duration(seconds: _delay),
              builder: (context, value, child) => LinearProgressIndicator(
                value: value,
                minHeight: 4,
                color: AppColors.secondary,
                backgroundColor: Colors.black.withValues(alpha: 0.08),
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _confirm,
            style: ElevatedButton.styleFrom(
              overlayColor: Colors.transparent,
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 20),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50)),
            ),
            child: Text(
              context.tr('send_confirm_now', {'seconds': '$_secondsLeft'}),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('cancel')),
          ),
        ],
      ),
    );
  }
}

/// Page de suivi d'un envoi : validation du paiement par l'expéditeur, puis reversement.
class _SendProgressPage extends StatefulWidget {
  final String transfertId;
  final String redirectUrl;

  const _SendProgressPage({
    required this.transfertId,
    required this.redirectUrl,
  });

  @override
  State<_SendProgressPage> createState() => _SendProgressPageState();
}

class _SendProgressPageState extends State<_SendProgressPage>
    with WidgetsBindingObserver {
  // Filet de sécurité si le canal Realtime tombe : le statut arrive en direct
  static const _pollEvery = Duration(seconds: 20);
  // Paiement jamais validé : on arrête d'attendre
  static const _waitLimit = Duration(minutes: 10);

  String _statut = 'collecte_en_attente';
  Timer? _timer;
  StreamSubscription<({String id, String statut})>? _events;
  Timer? _expiry;
  bool _expired = false;
  bool _polling = false;

  bool get _done => const {
        'reussi',
        'collecte_echec',
        'transfert_echec',
        'rembourse_en_cours',
        'rembourse',
        'remboursement_echec',
      }.contains(_statut);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Retour de la page de paiement sur cet envoi : on reste ici
    PaymentReturnService.trackedTransfertId = widget.transfertId;
    // Nouvel envoi « en cours » visible dans l'historique
    SupabaseService.transactionsRevision.value++;
    // Wave / MTN / Moov : validation via l'app ou la page de l'opérateur
    _openPayment();
    // Canal ouvert par l'accueil, fermé en arrière-plan : on le rouvre ici
    SupabaseService.subscribeTransactions();
    _events = SupabaseService.transfertEvents
        .where((e) => e.id == widget.transfertId)
        .listen((e) => _apply(e.statut, notify: false));
    _timer = Timer.periodic(_pollEvery, (_) => _poll());
    _expiry = Timer(_waitLimit, _expire);
  }

  /// Dernière vérification puis écran d'échec si toujours en attente.
  /// Le canal Realtime reste ouvert : un paiement tardif s'affiche quand même.
  Future<void> _expire() async {
    await _poll();
    if (!mounted || _statut != 'collecte_en_attente') return;
    _timer?.cancel();
    setState(() => _expired = true);
    HapticFeedback.mediumImpact();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour dans l'app après validation : réabonnement + statut tout de suite
    if (state == AppLifecycleState.resumed) {
      SupabaseService.subscribeTransactions();
      _poll();
    }
  }

  /// [notify] : false quand l'événement Realtime a déjà rechargé l'historique
  void _apply(String statut, {bool notify = true}) {
    if (!mounted || _done) return;
    final changed = statut != _statut;
    setState(() => _statut = statut);
    LiveTransferTracker.update(widget.transfertId, statut);
    if (statut != 'collecte_en_attente') {
      _expiry?.cancel();
      _expired = false;
    }
    if (_done) {
      _timer?.cancel();
      _events?.cancel();
      HapticFeedback.mediumImpact();
    }
    // Historique de l'accueil à jour (statut changé)
    if (changed && notify) SupabaseService.transactionsRevision.value++;
  }

  Future<void> _openPayment() async {
    final uri = Uri.tryParse(widget.redirectUrl);
    if (uri != null && uri.hasScheme) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _poll() async {
    if (_polling || _done) return;
    _polling = true;
    try {
      _apply(await SupabaseService.getTransfertStatus(widget.transfertId));
    } catch (_) {
      // Réseau instable : nouvel essai au prochain tick
    } finally {
      _polling = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _expiry?.cancel();
    _events?.cancel();
    if (PaymentReturnService.trackedTransfertId == widget.transfertId) {
      PaymentReturnService.trackedTransfertId = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final (title, body) = switch (_statut) {
      'reussi' => (context.tr('send_success'), null),
      'collecte_echec' => (context.tr('send_payment_failed'), null),
      'transfert_echec' || 'remboursement_echec' => (
          context.tr('send_payout_failed'),
          null
        ),
      'rembourse_en_cours' || 'rembourse' => (
          context.tr('send_refunded'),
          null
        ),
      'transfert_en_cours' || 'reversement_relance' => (
          context.tr('send_processing'),
          null
        ),
      _ when _expired => (
          context.tr('send_expired_title'),
          context.tr('send_expired_body')
        ),
      _ => (context.tr('send_waiting_title'), context.tr('send_waiting_body')),
    };

    final padding = MediaQuery.viewPaddingOf(context);
    final closeButton = ElevatedButton(
      onPressed: () => Navigator.of(context).pop(),
      style: ElevatedButton.styleFrom(
        overlayColor: Colors.transparent,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
      ),
      child: Text(
        context.tr('send_close'),
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding:
            EdgeInsets.fromLTRB(24, padding.top + 12, 24, padding.bottom + 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Fermer à tout moment : le suivi continue (historique en direct)
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: Icon(
                  Icons.close,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const Spacer(),
            Center(
              child: _done || _expired
                  ? Icon(
                      _statut == 'reussi'
                          ? Icons.check_circle_rounded
                          : Icons.error_rounded,
                      size: 88,
                      color: _statut == 'reussi'
                          ? AppColors.secondary
                          : Colors.redAccent,
                    )
                  : const SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(strokeWidth: 4),
                    ),
            ),
            const SizedBox(height: 28),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (body != null) ...[
              const SizedBox(height: 12),
              Text(
                body,
                textAlign: TextAlign.center,
                style: textTheme.bodyLarge
                    ?.copyWith(color: AppColors.textSecondary, height: 1.4),
              ),
            ],
            const Spacer(),
            if (_statut == 'collecte_en_attente' && !_expired)
              ElevatedButton(
                onPressed: _openPayment,
                style: ElevatedButton.styleFrom(
                  overlayColor: Colors.transparent,
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50)),
                ),
                child: Text(
                  context.tr('send_open_payment'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            if (_done || _expired) closeButton,
          ],
        ),
      ),
    );
  }
}
