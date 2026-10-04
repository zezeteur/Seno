import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_strings.dart';
import '../services/banner_gate.dart';
import '../theme/app_colors.dart';
import 'account_limits_screen.dart';
import 'connected_devices_screen.dart';
import 'help_support_screen.dart';
import 'history_screen.dart';
import 'merchant_request_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'qr_code_viewer_screen.dart';
import 'security_screen.dart';
import 'send_money_screen.dart';
import 'settings_screen.dart';
import 'statistics_screen.dart';

/// Détail d'une bannière du back-office (titre, sous-titre, image, lien).
/// Ouverte depuis la bannière de l'accueil ; l'image n'est affichée qu'ici.
/// Fond couleur principale avec icônes de déco tirées au hasard.
class BannerDetailsScreen extends StatefulWidget {
  const BannerDetailsScreen({super.key, required this.banner});

  final Map<String, dynamic> banner;

  static Future<void> open(BuildContext context, Map<String, dynamic> banner) =>
      Navigator.of(context).push(route(banner));

  static MaterialPageRoute<void> route(Map<String, dynamic> banner) =>
      MaterialPageRoute(builder: (_) => BannerDetailsScreen(banner: banner));

  @override
  State<BannerDetailsScreen> createState() => _BannerDetailsScreenState();
}

class _BannerDetailsScreenState extends State<BannerDetailsScreen>
    with WidgetsBindingObserver {
  static const _fg = AppColors.textOnPrimary;

  /// Accès bloqué : la page ne se ferme que lorsque le blocage est levé
  late bool _locked = widget.banner['bloquer_acces'] == true;

  @override
  void initState() {
    super.initState();
    if (_locked) WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _locked) _recheck();
  }

  /// Retour dans l'app : blocage retiré du back-office → la page se ferme
  Future<void> _recheck() async {
    final b = await BannerGate.fetchBlocking();
    if (!mounted || b?['id'] == widget.banner['id']) return;
    setState(() => _locked = false);
    Navigator.of(context).pop();
  }

  static const _decoIconSet = [
    Icons.account_balance,
    Icons.account_balance_wallet,
    Icons.credit_card,
    Icons.payment,
    Icons.attach_money,
    Icons.monetization_on,
    Icons.savings,
    Icons.wallet,
    Icons.receipt,
    Icons.point_of_sale,
    Icons.currency_exchange,
    Icons.trending_up,
    Icons.campaign,
    Icons.notifications,
    Icons.star,
    Icons.favorite,
  ];

  /// Icônes de déco : au plus une par case d'une grille 4 × 10, position
  /// aléatoire dans la case (pas de chevauchement), tirées une fois par ouverture
  final List<
      ({
        IconData icon,
        double left,
        double top,
        double size,
        double opacity,
        double angle
      })> _decoIcons = () {
    final random = math.Random();
    const cols = 4, rows = 10;
    return [
      for (var row = 0; row < rows; row++)
        for (var col = 0; col < cols; col++)
          if (random.nextDouble() < 0.6)
            (
              icon: _decoIconSet[random.nextInt(_decoIconSet.length)],
              left: (col + 0.15 + random.nextDouble() * 0.5) / cols,
              top: (row + 0.15 + random.nextDouble() * 0.5) / rows,
              size: 18 + random.nextDouble() * 20,
              opacity: 0.06 + random.nextDouble() * 0.08,
              angle: random.nextDouble() * 2 * math.pi,
            ),
    ];
  }();

  Widget _buildDecoIcons() {
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              for (final d in _decoIcons)
                Positioned(
                  left: d.left * constraints.maxWidth,
                  top: d.top * constraints.maxHeight,
                  child: Transform.rotate(
                    angle: d.angle,
                    child: Icon(
                      d.icon,
                      size: d.size,
                      color: _fg.withValues(alpha: d.opacity),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Pages de l'app ouvrables depuis le bouton (clé `page_app` du back-office)
  static final Map<String, Widget Function()> _pages = {
    'envoyer': () => const SendMoneyScreen(),
    'encaisser': () => const QRCodeViewerScreen(),
    'historique': () => const HistoryScreen(),
    'statistiques': () => const StatisticsScreen(),
    'profil': () => const ProfileScreen(),
    'securite': () => const SecurityScreen(),
    'plafonds': () => const AccountLimitsScreen(),
    'devenir_marchand': () => const MerchantRequestScreen(),
    'aide': () => const HelpSupportScreen(),
    'notifications': () => const NotificationsScreen(),
    'parametres': () => const SettingsScreen(),
    'appareils': () => const ConnectedDevicesScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final textTheme = Theme.of(context).textTheme;
    final banner = widget.banner;
    final image = banner['image_url'] as String?;
    final sousTitre = banner['sous_titre'] as String?;
    final lien = banner['lien'] as String?;
    final page = _pages[banner['page_app']];
    final boutonTexte = (banner['bouton_texte'] as String?)?.trim();
    // Accès bloqué : ni croix ni retour, l'app reste derrière cette page
    final bloque = _locked;

    return PopScope(
      canPop: !bloque,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        // Fond jaune : icônes de la barre d'état foncées, quel que soit le thème
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: AppColors.primary,
          body: Stack(
            children: [
              _buildDecoIcons(),
              Column(
                children: [
                  SizedBox(height: mediaQuery.viewPadding.top),
                  // Croix de fermeture (absente si l'accès est bloqué)
                  if (bloque)
                    const SizedBox(height: 68)
                  else
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                        child: IconButton(
                          tooltip: context.tr('banner_close'),
                          icon: const HugeIcon(
                            icon: HugeIcons.strokeRoundedCancel01,
                            size: 26,
                            color: _fg,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                          20,
                          0,
                          20,
                          lien != null || page != null
                              ? 16
                              : mediaQuery.viewPadding.bottom + 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (image != null) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: AspectRatio(
                                aspectRatio: 1.6,
                                child: CachedNetworkImage(
                                  imageUrl: image,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) =>
                                      const SizedBox.shrink(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ] else ...[
                            // Sans image : mégaphone dans un cercle
                            Center(
                              child: Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: _fg.withValues(alpha: 0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: HugeIcon(
                                    icon: HugeIcons.strokeRoundedMegaphone01,
                                    size: 56,
                                    color: _fg,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),
                          ],
                          Text(
                            banner['titre'] as String,
                            style: textTheme.headlineSmall?.copyWith(
                              color: _fg,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                          if (sousTitre != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              sousTitre,
                              style: textTheme.bodyLarge?.copyWith(
                                color: _fg.withValues(alpha: 0.8),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // Bouton du lien : fixé en bas de l'écran
                  if (lien != null || page != null)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                          20, 8, 20, mediaQuery.viewPadding.bottom + 16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _fg,
                            foregroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: () => page != null
                              ? (bloque
                                  ? Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => page()))
                                  : Navigator.of(context).pushReplacement(
                                      MaterialPageRoute(
                                          builder: (_) => page())))
                              : launchUrl(Uri.parse(lien!),
                                  mode: LaunchMode.externalApplication),
                          icon: HugeIcon(
                            icon: page != null
                                ? HugeIcons.strokeRoundedArrowRight01
                                : HugeIcons.strokeRoundedLinkSquare02,
                            size: 20,
                            color: AppColors.primary,
                          ),
                          label: Text(
                            boutonTexte ?? context.tr('banner_learn_more'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
