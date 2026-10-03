import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import '../l10n/app_strings.dart';
import '../models/reseau.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import '../utils/pair_digits_formatter.dart';
import '../utils/toast_service.dart';
import '../widgets/photo_viewer.dart';
import '../widgets/transaction_list.dart';
import '../widgets/user_avatar.dart';
import 'help_support_screen.dart';
import 'send_money_screen.dart';

/// Détail d'une transaction de l'historique (envoi ou réception)
class TransactionDetailsScreen extends StatefulWidget {
  final SenoTransaction transaction;

  /// Nom du répertoire si l'autre partie est un contact
  final String? contactName;

  const TransactionDetailsScreen({
    super.key,
    required this.transaction,
    this.contactName,
  });

  @override
  State<TransactionDetailsScreen> createState() =>
      _TransactionDetailsScreenState();
}

class _TransactionDetailsScreenState extends State<TransactionDetailsScreen>
    with WidgetsBindingObserver {
  Reseau? _reseau;

  /// Statut à jour (rafraîchi à l'ouverture et au retour dans l'app)
  late String _statut = widget.transaction.statut;
  bool get _isFailed => SenoTransaction.failedStatuts.contains(_statut);
  bool get _isPending => SenoTransaction.pendingStatuts.contains(_statut);
  bool get _isRefunded => _statut == 'rembourse';

  /// Message d'aide quand le reversement n'a pas abouti
  String? get _refundHelpKey => switch (_statut) {
        'rembourse_en_cours' => 'tx_refund_pending_help',
        'rembourse' => 'tx_refunded_help',
        'transfert_echec' || 'remboursement_echec' => 'tx_payout_failed_help',
        _ => null,
      };
  final _receiptKey = GlobalKey();
  bool _sharing = false;

  SenoTransaction get _tx => widget.transaction;

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
    Icons.show_chart,
    Icons.pie_chart,
  ];

  /// Icônes de déco : au plus une par case d'une grille 4 × 8, position
  /// aléatoire dans la case (pas de chevauchement), tirées une fois par écran
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
              opacity: 0.04 + random.nextDouble() * 0.06,
              angle: random.nextDouble() * 2 * math.pi,
            ),
    ];
  }();

  Widget _buildDecoIcons(Color color) {
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
                      color: color.withValues(alpha: d.opacity),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Capture la zone du reçu en PNG et ouvre le partage système
  Future<void> _shareReceipt() async {
    HapticFeedback.lightImpact();
    setState(() => _sharing = true);
    try {
      final boundary = _receiptKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(
          pixelRatio: MediaQuery.devicePixelRatioOf(context));
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null || !mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(ShareParams(
        files: [
          XFile.fromData(
            bytes.buffer.asUint8List(),
            mimeType: 'image/png',
            name: 'recu-seno-${_tx.id.split('-').first}.png',
          ),
        ],
        fileNameOverrides: ['recu-seno-${_tx.id.split('-').first}.png'],
        // iPad : ancre de la feuille de partage
        sharePositionOrigin:
            box != null ? box.localToGlobal(Offset.zero) & box.size : null,
      ));
    } catch (_) {
      if (mounted) {
        ToastService.showError(context, context.tr('tx_share_error'));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadReseau();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour depuis Wave / Orange après validation
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  /// Envoi en cours : interroge le serveur (qui interroge Jèko si besoin)
  Future<void> _refreshStatus() async {
    if (_tx.isReceived || !_isPending) return;
    try {
      final statut = await SupabaseService.getTransfertStatus(_tx.id);
      if (!mounted || statut == _statut) return;
      setState(() => _statut = statut);
      SupabaseService.transactionsRevision.value++;
    } catch (_) {
      // Hors ligne : le dernier statut connu reste affiché
    }
  }

  Future<void> _confirmPayment() async {
    final uri = Uri.tryParse(_tx.paymentUrl ?? '');
    if (uri == null) return;
    HapticFeedback.lightImpact();
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// À la place de « Envoyer à nouveau » tant que l'envoi est en cours
  Widget _buildPendingAction(BuildContext context) {
    // Wave / Orange : page de validation à rouvrir
    if (_statut == 'collecte_en_attente' && _tx.paymentUrl != null) {
      return ElevatedButton(
        onPressed: _confirmPayment,
        style: ElevatedButton.styleFrom(
          overlayColor: Colors.transparent,
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 20),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        ),
        child: Text(
          context.tr('tx_confirm_payment'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      );
    }
    // Reversement en cours : aucun message
    if (_statut != 'collecte_en_attente') return const SizedBox.shrink();
    // MTN / Moov (USSD) : simple indication
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        context.tr('tx_pending_ussd'),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.orange.shade800,
              height: 1.4,
            ),
      ),
    );
  }

  Future<void> _loadReseau() async {
    try {
      final reseaux = await SupabaseService.getReseaux();
      final reseau = reseaux.where((r) => r.id == _tx.reseauId).firstOrNull;
      if (mounted) setState(() => _reseau = reseau);
    } catch (_) {
      // Hors ligne : la ligne « Réseau » reste masquée
    }
  }

  /// 25000 → « 25 000 FCFA »
  String _fcfa(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return '$buffer FCFA';
  }

  String _date(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} · ${two(d.hour)}:${two(d.minute)}';
  }

  /// Numéro complet groupé par paires ; numéro masqué laissé tel quel
  String get _numero => RegExp(r'^\d{10}$').hasMatch(_tx.numero)
      ? PairDigitsFormatter.group(_tx.numero)
      : _tx.numero;

  /// Destinataire saisi par numéro (sinon pseudo Seno)
  bool get _isPhoneLabel => RegExp(r'^[\d ]+$').hasMatch(_tx.label);

  Future<void> _copyReference() async {
    await Clipboard.setData(ClipboardData(text: _tx.id));
    HapticFeedback.lightImpact();
    if (mounted) ToastService.showInfo(context, context.tr('tx_copied'));
  }

  ({String label, Color color, dynamic icon}) _status(BuildContext context) {
    if (_isRefunded) {
      return (
        label: context.tr('tx_refunded'),
        color: Colors.blueGrey,
        icon: HugeIcons.strokeRoundedArrowTurnBackward,
      );
    }
    if (_isFailed) {
      return (
        label: context.tr('tx_failed'),
        color: Colors.redAccent,
        icon: HugeIcons.strokeRoundedCancelCircle,
      );
    }
    if (_isPending) {
      return (
        label: context.tr('tx_pending'),
        color: Colors.orange,
        icon: HugeIcons.strokeRoundedClock01,
      );
    }
    return (
      label: context.tr('tx_success'),
      color: AppColors.success,
      icon: HugeIcons.strokeRoundedCheckmarkCircle02,
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {bool bold = false, Widget? trailing}) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ],
      ),
    );
  }

  Widget _card(BuildContext context, List<Widget> rows) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 20,
                endIndent: 20,
                color: Colors.black.withValues(alpha: 0.06),
              ),
            rows[i],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final textTheme = Theme.of(context).textTheme;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final status = _status(context);
    final sign = _tx.isReceived ? '+' : '-';
    final handle = _isPhoneLabel ? _numero : '@${_tx.label}';
    // Nom en titre (pseudo / numéro dessous) : contact du répertoire,
    // boutique, sinon « Nom Prénoms » de l'utilisateur Seno
    // Envoi à soi-même : « Moi-même »
    final name = TransactionTile.isSelf(_tx)
        ? context.tr('send_myself')
        : widget.contactName ?? _tx.merchantName ?? _tx.personName;
    final title = name ?? handle;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SizedBox(height: mediaQuery.viewPadding.top),
          Expanded(
            child: SingleChildScrollView(
              padding:
                  EdgeInsets.only(bottom: mediaQuery.viewPadding.bottom + 24),
              child: Column(
                children: [
                  // Header avec bouton retour
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back, color: onSurface),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          context.tr('tx_details'),
                          style: textTheme.headlineSmall?.copyWith(
                            color: onSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 28,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Zone capturée pour le reçu partagé (fond opaque)
                  RepaintBoundary(
                    key: _receiptKey,
                    child: Container(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Stack(
                        children: [
                          _buildDecoIcons(onSurface),
                          Column(
                            children: [
                              // Autre partie, montant et statut
                              GestureDetector(
                                onTap: _tx.avatarUrl != null
                                    ? () => showPhotoViewer(
                                        context, _tx.avatarUrl!,
                                        heroTag: 'tx-photo')
                                    : null,
                                child: Hero(
                                  tag: 'tx-photo',
                                  child: UserAvatar(
                                    pseudo: title,
                                    avatarUrl: _tx.avatarUrl,
                                    merchantCategory: _tx.merchantCategory,
                                    radius: 36,
                                    backgroundColor: AppColors.secondary,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                child: Text(
                                  title,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.titleMedium?.copyWith(
                                    color: onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (name != null)
                                Text(
                                  handle,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Text(
                                '$sign ${_fcfa(_tx.montant)}',
                                style: textTheme.headlineMedium?.copyWith(
                                  color: _isFailed || _isRefunded
                                      ? onSurface.withValues(alpha: 0.35)
                                      : _tx.isReceived
                                          ? AppColors.success
                                          : onSurface,
                                  decoration: _isFailed || _isRefunded
                                      ? TextDecoration.lineThrough
                                      : null,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: status.color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(50),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    HugeIcon(
                                        icon: status.icon,
                                        size: 16,
                                        color: status.color),
                                    const SizedBox(width: 6),
                                    Text(
                                      status.label,
                                      style: textTheme.bodySmall?.copyWith(
                                        color: status.color,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Reversement impossible : remboursement intégral, ou support si bloqué
                              if (!_tx.isReceived && _refundHelpKey != null)
                                Container(
                                  margin:
                                      const EdgeInsets.fromLTRB(20, 0, 20, 8),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    context.tr(_refundHelpKey!),
                                    style: textTheme.bodySmall?.copyWith(
                                      color: Colors.redAccent,
                                      height: 1.4,
                                    ),
                                  ),
                                ),

                              _card(context, [
                                _row(
                                  context,
                                  context
                                      .tr(_tx.isReceived ? 'tx_from' : 'tx_to'),
                                  name != null && !_isPhoneLabel
                                      ? '$title · $handle'
                                      : title,
                                ),
                                _row(context, context.tr('tx_number'), _numero),
                                if (_reseau != null)
                                  _row(context, context.tr('tx_network'),
                                      _reseau!.nom),
                              ]),

                              _card(context, [
                                if (_tx.isReceived)
                                  _row(
                                      context,
                                      context.tr('tx_amount_received'),
                                      _fcfa(_tx.montantRecu),
                                      bold: true)
                                else ...[
                                  _row(context, context.tr('tx_amount_sent'),
                                      _fcfa(_tx.montantRecu)),
                                  _row(context, context.tr('tx_fees'),
                                      _fcfa(_tx.frais)),
                                  _row(context, context.tr('tx_total_debited'),
                                      _fcfa(_tx.montant),
                                      bold: true),
                                ],
                              ]),

                              _card(context, [
                                _row(context, context.tr('tx_date'),
                                    _date(_tx.createdAt)),
                                _row(
                                  context,
                                  context.tr('tx_reference'),
                                  _tx.id.split('-').first.toUpperCase(),
                                  trailing: GestureDetector(
                                    onTap: _copyReference,
                                    child: const HugeIcon(
                                      icon: HugeIcons.strokeRoundedCopy01,
                                      size: 18,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ]),

                              // Signature du reçu
                              const SizedBox(height: 8),
                              Image.asset(
                                'assets/images/seno-logo.png',
                                height: 24,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Renvoyer à la même personne ; reçu partageable si réussi
                        if (!_isPending)
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => Navigator.of(context)
                                      .pushReplacement(MaterialPageRoute(
                                    builder: (_) => SendMoneyScreen(
                                      initialCategory: _tx.merchantCategory,
                                      initialShopName: _tx.merchantName,
                                      initialRecipient: (
                                        value: _tx.label,
                                        avatarUrl: _tx.avatarUrl,
                                        phone:
                                            _isPhoneLabel ? _tx.numero : null,
                                      ),
                                    ),
                                  )),
                                  style: ElevatedButton.styleFrom(
                                    overlayColor: Colors.transparent,
                                    backgroundColor: Colors.black,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 20),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(50)),
                                  ),
                                  child: Text(
                                    context.tr('tx_send_again'),
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                              if (_statut == 'reussi') ...[
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 62,
                                  height: 62,
                                  child: IconButton.filled(
                                    tooltip: context.tr('tx_share_receipt'),
                                    onPressed: _sharing ? null : _shareReceipt,
                                    style: IconButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.black,
                                    ),
                                    icon: _sharing
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.black),
                                          )
                                        : const HugeIcon(
                                            icon:
                                                HugeIcons.strokeRoundedShare08,
                                            size: 22,
                                            color: Colors.black,
                                          ),
                                  ),
                                ),
                              ],
                            ],
                          )
                        else
                          _buildPendingAction(context),
                        if (_isFailed) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const HelpSupportScreen(contactOnly: true),
                              ),
                            ),
                            child: Text(context.tr('help_support')),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
