import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_strings.dart';
import '../screens/banner_details_screen.dart';
import '../services/banner_gate.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';

/// Bannières d'information gérées depuis le back-office (table `app_banners`).
/// La RLS ne renvoie que les bannières en cours et ciblant l'utilisateur.
/// Relues à chaque retour dans l'app ; une bannière fermée ne réapparaît pas.
class AppBanners extends StatefulWidget {
  const AppBanners({super.key});

  @override
  State<AppBanners> createState() => _AppBannersState();
}

class _AppBannersState extends State<AppBanners> with WidgetsBindingObserver {
  static const _dismissedKey = 'dismissed_banners';
  static const _openedKey = 'opened_startup_banners';

  /// Bannières déjà ouvertes depuis le lancement de l'app (mode « à chaque ouverture »)
  static final Set<String> _openedThisLaunch = {};
  List<Map<String, dynamic>> _banners = [];
  Set<String> _dismissed = {};

  /// Bannières retirées côté back-office : gardées le temps de leur sortie animée
  final Set<String> _leaving = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final client = SupabaseService.client;
    if (client?.auth.currentUser == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final rows = await client!
          .from('app_banners')
          .select(
              'id, titre, sous_titre, image_url, niveau, lien, page_app, bouton_texte, fermable, ouvrir_demarrage, demarrage_chaque_fois, bloquer_acces, version_cible, version_mode')
          .order('created_at', ascending: false)
          .limit(20);
      final version = (await PackageInfo.fromPlatform()).version;
      if (!mounted) return;
      setState(() {
        _dismissed = (prefs.getStringList(_dismissedKey) ?? []).toSet();
        final fresh = List<Map<String, dynamic>>.from(rows)
            .where((b) => BannerGate.matchesVersion(b, version))
            .take(3)
            .toList();
        final ids = fresh.map((b) => b['id']).toSet();
        final gone = _banners.where((b) => !ids.contains(b['id'])).toList();
        _leaving
          ..removeWhere(ids.contains)
          ..addAll(gone.map((b) => b['id'] as String));
        _banners = [...fresh, ...gone];
      });
      BannerGate.showIfBlocked(Navigator.of(context));
      _openStartupBanner(prefs);
    } catch (_) {
      // Hors ligne : on garde l'affichage précédent
    }
  }

  /// Bannière « ouvrir au démarrage » : détail en plein écran,
  /// une seule fois par bannière ou à chaque lancement de l'app
  Future<void> _openStartupBanner(SharedPreferences prefs) async {
    final opened = prefs.getStringList(_openedKey) ?? [];
    final b = _banners.where((b) {
      final id = b['id'] as String;
      if (b['ouvrir_demarrage'] != true ||
          _leaving.contains(id) ||
          _dismissed.contains(id) ||
          _openedThisLaunch.contains(id)) {
        return false;
      }
      return b['demarrage_chaque_fois'] == true || !opened.contains(id);
    }).firstOrNull;
    if (b == null || b['bloquer_acces'] == true) return;
    final id = b['id'] as String;
    _openedThisLaunch.add(id);
    if (b['demarrage_chaque_fois'] != true) {
      await prefs.setStringList(_openedKey, [...opened.take(19), id]);
    }
    if (mounted) BannerDetailsScreen.open(context, b);
  }

  Future<void> _dismiss(String id) async {
    setState(() => _dismissed = {..._dismissed, id});
    final prefs = await SharedPreferences.getInstance();
    // Seuls les ids encore en ligne sont gardés : la liste ne grossit pas
    final live = _banners
        .map((b) => b['id'] as String)
        .where((id) => !_leaving.contains(id))
        .toSet();
    await prefs.setStringList(
        _dismissedKey, _dismissed.where(live.contains).toList());
  }

  /// Couleur principale de l'app pour toutes les bannières ; seule l'icône indique le niveau
  ({Color bg, Color fg, dynamic icon}) _style(String niveau) => (
        bg: AppColors.primary,
        fg: AppColors.textOnPrimary,
        icon: switch (niveau) {
          'critical' => HugeIcons.strokeRoundedAlert02,
          'warning' => HugeIcons.strokeRoundedAlertCircle,
          _ => HugeIcons.strokeRoundedInformationCircle,
        },
      );

  @override
  Widget build(BuildContext context) {
    // Toutes les bannières restent dans l'arbre : entrée et sortie animées
    final shown = _banners
        .where(
            (b) => !_dismissed.contains(b['id']) && !_leaving.contains(b['id']))
        .isNotEmpty;
    return AnimatedPadding(
      duration: _Reveal.duration,
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(20, 0, 20, shown ? 4 : 0),
      child: Column(
        children: [
          for (final b in _banners)
            _Reveal(
              key: ValueKey(b['id']),
              visible:
                  !_dismissed.contains(b['id']) && !_leaving.contains(b['id']),
              onHidden: () {
                if (_leaving.remove(b['id'])) {
                  setState(() => _banners.remove(b));
                }
              },
              child: _buildBanner(context, b),
            ),
        ],
      ),
    );
  }

  Widget _buildBanner(BuildContext context, Map<String, dynamic> b) {
    final s = _style(b['niveau'] as String? ?? 'info');
    final sousTitre = b['sous_titre'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => BannerDetailsScreen.open(context, b),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                child: _buildBody(context, b, s, sousTitre),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    Map<String, dynamic> b,
    ({Color bg, Color fg, dynamic icon}) s,
    String? sousTitre,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: HugeIcon(icon: s.icon, size: 20, color: s.fg),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                b['titre'] as String,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: s.fg,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              if (sousTitre != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    sousTitre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: s.fg, fontSize: 13, height: 1.35),
                  ),
                ),
            ],
          ),
        ),
        if (b['fermable'] == true && b['bloquer_acces'] != true)
          IconButton(
            tooltip: context.tr('banner_close'),
            visualDensity: VisualDensity.compact,
            onPressed: () => _dismiss(b['id'] as String),
            icon: HugeIcon(
                icon: HugeIcons.strokeRoundedCancel01, size: 18, color: s.fg),
          )
        else
          const SizedBox(width: 10),
      ],
    );
  }
}

/// Apparition / disparition d'une bannière : hauteur, fondu et léger glissement.
class _Reveal extends StatefulWidget {
  const _Reveal({
    super.key,
    required this.visible,
    required this.onHidden,
    required this.child,
  });

  static const duration = Duration(milliseconds: 380);

  final bool visible;
  final VoidCallback onHidden;
  final Widget child;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: _Reveal.duration,
    reverseDuration: const Duration(milliseconds: 300),
  );
  late final _size = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  late final _fade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.3, 1, curve: Curves.easeOut),
    reverseCurve: const Interval(0.4, 1, curve: Curves.easeIn),
  );
  late final _slide =
      Tween(begin: const Offset(0, -0.15), end: Offset.zero).animate(_size);

  @override
  void initState() {
    super.initState();
    if (widget.visible) _controller.forward();
  }

  @override
  void didUpdateWidget(_Reveal old) {
    super.didUpdateWidget(old);
    if (widget.visible == old.visible) return;
    if (widget.visible) {
      _controller.forward();
    } else {
      _controller.reverse().then((_) {
        if (mounted && !widget.visible) widget.onHidden();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _size,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(position: _slide, child: widget.child),
      ),
    );
  }
}
