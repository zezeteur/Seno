import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import '../l10n/app_strings.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import '../utils/toast_service.dart';
import '../widgets/user_avatar.dart';
import 'payment_requests_screen.dart';
import 'send_money_screen.dart';

/// Détail d'une demande de paiement : montant, statut, compte à rebours et
/// actions (reçue : Payer / Refuser ; envoyée : Annuler). Fond couleur
/// principale avec icônes de déco aléatoires, quel que soit le thème.
class PaymentRequestDetailsScreen extends StatefulWidget {
  final PaymentRequest request;

  const PaymentRequestDetailsScreen({super.key, required this.request});

  @override
  State<PaymentRequestDetailsScreen> createState() =>
      _PaymentRequestDetailsScreenState();
}

class _PaymentRequestDetailsScreenState
    extends State<PaymentRequestDetailsScreen> {
  bool _busy = false;

  /// Compte à rebours de l'expiration (rafraîchi chaque seconde)
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    if (_r.isPending) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        // Expirée : plus rien à décompter
        if (_expired) _ticker?.cancel();
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  PaymentRequest get _r => widget.request;

  static const _validity = Duration(hours: 24);

  // Fond jaune dans les deux thèmes : textes et icônes toujours foncés
  static const _ink = AppColors.textOnPrimary;
  static final _inkSoft = _ink.withValues(alpha: 0.6);

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
    Icons.request_quote,
  ];

  /// Icônes de déco : au plus une par case d'une grille 4 × 8, position
  /// aléatoire dans la case (pas de chevauchement), tirées une fois par écran
  /// (même principe que le détail d'une transaction)
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
    const cols = 4, rows = 8;
    return [
      for (var row = 0; row < rows; row++)
        for (var col = 0; col < cols; col++)
          if (random.nextDouble() < 0.6)
            (
              icon: _decoIconSet[random.nextInt(_decoIconSet.length)],
              left: (col + 0.15 + random.nextDouble() * 0.5) / cols,
              top: (row + 0.15 + random.nextDouble() * 0.5) / rows,
              size: 16 + random.nextDouble() * 18,
              opacity: 0.05 + random.nextDouble() * 0.07,
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
                      color: _ink.withValues(alpha: d.opacity),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _respond(String action) async {
    setState(() => _busy = true);
    try {
      await SupabaseService.respondPaymentRequest(_r.id, action);
      if (!mounted) return;
      ToastService.showSuccess(
          context,
          context.tr(action == 'refuser'
              ? 'payment_request_declined'
              : 'payment_request_cancelled'));
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ToastService.showError(context, context.tr('payment_request_error'));
    }
  }

  Future<void> _cancel() async {
    if (await confirmCancelPaymentRequest(context, _r) && mounted) {
      await _respond('annuler');
    }
  }

  void _pay() {
    // La page de paiement remplace le détail : le retour ramène à la liste
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => SendMoneyScreen(paymentRequest: _r)),
    );
  }

  /// Délai de 24 h écoulé pendant que la page est ouverte
  bool get _expired => !DateTime.now().isBefore(_r.createdAt.add(_validity));

  /// Temps restant avant expiration, « 23:41:05 » (zéro une fois passée)
  String get _remaining {
    var left = _r.createdAt.add(_validity).difference(DateTime.now());
    if (left.isNegative) left = Duration.zero;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(left.inHours)}:${two(left.inMinutes % 60)}:'
        '${two(left.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme =
        Theme.of(context).textTheme.apply(bodyColor: _ink, displayColor: _ink);
    final viewPadding = MediaQuery.of(context).viewPadding;
    // En attente mais délai écoulé : affichée comme expirée, sans actions
    final expired = _r.isPending && _expired;
    final pending = _r.isPending && !expired;

    // Barre d'état foncée sur le fond jaune
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.primary,
        body: Stack(
          children: [
            _buildDecoIcons(),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  0, viewPadding.top + 8, 0, viewPadding.bottom + 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Titre à côté du bouton retour
                  Row(
                    children: [
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const HugeIcon(
                          icon: HugeIcons.strokeRoundedArrowLeft01,
                          color: _ink,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(
                          context.tr('payment_request_details_title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 24),
                    ],
                  ),
                  // Infos centrées verticalement (défilent si l'écran est petit)
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Autre partie : centrée, photo au-dessus
                            Center(
                              child: UserAvatar(
                                pseudo: _r.pseudo,
                                avatarUrl: _r.avatarUrl,
                                radius: 40,
                                backgroundColor: AppColors.secondary,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              context.tr(
                                  _r.received
                                      ? 'payment_request_asks'
                                      : 'payment_request_to',
                                  {'pseudo': '@${_r.pseudo}'}),
                              textAlign: TextAlign.center,
                              style: textTheme.bodyMedium
                                  ?.copyWith(color: _inkSoft),
                            ),
                            const SizedBox(height: 8),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                        text: formatPaymentAmount(_r.amount)),
                                    TextSpan(
                                      text: ' FCFA',
                                      style: textTheme.titleLarge
                                          ?.copyWith(color: _inkSoft),
                                    ),
                                  ],
                                ),
                                style: textTheme.displaySmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Center(
                                child: PaymentRequestStatusPill(
                                    statut: expired ? 'expiree' : _r.statut)),
                            const SizedBox(height: 32),
                            // En attente : compte à rebours avant expiration
                            if (pending)
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 20),
                                decoration: BoxDecoration(
                                  color: _ink.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                // Compte à rebours centré, en grand
                                child: Column(
                                  children: [
                                    Text(
                                        context
                                            .tr('payment_request_expires_in'),
                                        style: textTheme.bodyMedium
                                            ?.copyWith(color: _inkSoft)),
                                    const SizedBox(height: 4),
                                    Text(
                                      _remaining,
                                      style: textTheme.displaySmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        // Chiffres à largeur fixe : pas de saut à chaque seconde
                                        fontFeatures: const [
                                          FontFeature.tabularFigures()
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Terminée : OK seul (ferme le détail)
                  if (!pending)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _ink,
                          foregroundColor: AppColors.primary,
                          minimumSize: const Size.fromHeight(56),
                          shape: const StadiumBorder(),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: Text(context.tr('payment_request_ok')),
                      ),
                    ),
                  // Actions (demande en attente uniquement)
                  if (pending)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                      child: _busy
                          ? const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: _ink),
                              ),
                            )
                          : _r.received
                              ? Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: _ink,
                                          side: const BorderSide(color: _ink),
                                          minimumSize:
                                              const Size.fromHeight(56),
                                          shape: const StadiumBorder(),
                                        ),
                                        onPressed: () => _respond('refuser'),
                                        child: Text(context
                                            .tr('payment_request_decline')),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: _ink,
                                          foregroundColor: AppColors.primary,
                                          minimumSize:
                                              const Size.fromHeight(56),
                                          shape: const StadiumBorder(),
                                        ),
                                        onPressed: _pay,
                                        child: Text(
                                            context.tr('payment_request_pay')),
                                      ),
                                    ),
                                  ],
                                )
                              // Envoyée : Annuler + OK (ferme le détail)
                              : Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppColors.error,
                                          side: const BorderSide(
                                              color: AppColors.error),
                                          minimumSize:
                                              const Size.fromHeight(56),
                                          shape: const StadiumBorder(),
                                        ),
                                        onPressed: _cancel,
                                        child: Text(context
                                            .tr('payment_request_cancel')),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: _ink,
                                          foregroundColor: AppColors.primary,
                                          minimumSize:
                                              const Size.fromHeight(56),
                                          shape: const StadiumBorder(),
                                        ),
                                        onPressed: () => Navigator.pop(context),
                                        child: Text(
                                            context.tr('payment_request_ok')),
                                      ),
                                    ),
                                  ],
                                ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
