import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shimmer/shimmer.dart';
import '../l10n/app_strings.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import '../utils/toast_service.dart';
import '../widgets/user_avatar.dart';
import 'payment_request_details_screen.dart';
import 'send_money_screen.dart';

/// Demandes de paiement : reçues (Payer / Refuser) et envoyées (Annuler),
/// au choix par les chips du haut
class PaymentRequestsScreen extends StatefulWidget {
  const PaymentRequestsScreen({super.key});

  @override
  State<PaymentRequestsScreen> createState() => _PaymentRequestsScreenState();
}

class _PaymentRequestsScreenState extends State<PaymentRequestsScreen> {
  List<PaymentRequest>? _requests;
  int _loadId = 0;
  final _busy = <String>{};

  /// Chip sélectionnée : demandes reçues (sinon envoyées)
  bool _showReceived = true;

  @override
  void initState() {
    super.initState();
    SupabaseService.paymentRequestsRevision.addListener(_load);
    // Une demande payée change de statut quand l'envoi aboutit
    SupabaseService.transactionsRevision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    SupabaseService.paymentRequestsRevision.removeListener(_load);
    SupabaseService.transactionsRevision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final id = ++_loadId;
    try {
      final all = await SupabaseService.getMyPaymentRequests();
      if (mounted && id == _loadId) setState(() => _requests = all);
    } catch (_) {
      // Hors ligne : la dernière liste reste affichée
      if (mounted && id == _loadId) setState(() => _requests ??= []);
    }
  }

  /// Payeur : `refuser` ; demandeur : `annuler`
  Future<void> _respond(PaymentRequest r, String action) async {
    setState(() => _busy.add(r.id));
    try {
      await SupabaseService.respondPaymentRequest(r.id, action);
      if (mounted) {
        ToastService.showSuccess(
            context,
            context.tr(action == 'refuser'
                ? 'payment_request_declined'
                : 'payment_request_cancelled'));
      }
    } catch (_) {
      if (mounted) {
        ToastService.showError(context, context.tr('payment_request_error'));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  /// Annulation : confirmée dans un sheet avant l'envoi au serveur
  Future<void> _confirmCancel(PaymentRequest r) async {
    if (await confirmCancelPaymentRequest(context, r) && mounted) {
      await _respond(r, 'annuler');
    }
  }

  void _pay(PaymentRequest r) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SendMoneyScreen(paymentRequest: r)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final viewPadding = MediaQuery.of(context).viewPadding;
    final requests =
        _requests?.where((r) => r.received == _showReceived).toList();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: EdgeInsets.only(top: viewPadding.top + 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Titre à côté du bouton retour
            Row(
              children: [
                const SizedBox(width: 8),
                IconButton(
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedArrowLeft01,
                    color: textTheme.bodyLarge?.color ?? Colors.black,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    context.tr('payment_requests_title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 24),
              ],
            ),
            const SizedBox(height: 12),
            // Chips : reçues / envoyées
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  _buildChip(textTheme, 'payment_requests_received', true),
                  const SizedBox(width: 8),
                  _buildChip(textTheme, 'payment_requests_sent', false),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: requests == null
                  ? _buildShimmer(viewPadding)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                            24, 0, 24, viewPadding.bottom + 24),
                        children: [
                          if (requests.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                context.tr(_showReceived
                                    ? 'payment_requests_empty'
                                    : 'payment_requests_sent_empty'),
                                style: textTheme.bodyMedium
                                    ?.copyWith(color: AppColors.textSecondary),
                              ),
                            ),
                          for (final r in requests) _buildTile(textTheme, r),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Premier chargement : lignes fantômes (avatar, libellé, montant, bouton)
  Widget _buildShimmer(EdgeInsets viewPadding) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget box(double width, double height, {double radius = 6}) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radius),
          ),
        );
    return Shimmer.fromColors(
      baseColor: dark ? AppColors.darkSurfaceVariant : Colors.grey.shade300,
      highlightColor: dark ? AppColors.darkSurface : Colors.grey.shade100,
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(24, 8, 24, viewPadding.bottom + 24),
        children: [
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  box(44, 44, radius: 22),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        box(120, 12),
                        const SizedBox(height: 8),
                        box(90, 16),
                      ],
                    ),
                  ),
                  box(72, 36, radius: 18),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChip(TextTheme textTheme, String label, bool received) {
    final selected = _showReceived == received;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final count =
        _requests?.where((r) => r.received == received && r.isPending).length ??
            0;
    return GestureDetector(
      onTap: () => setState(() => _showReceived = received),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? onSurface
              : Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkSurfaceVariant
                  : onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(50),
        ),
        child: Text(
          // En attente : nombre à côté du libellé
          count > 0 ? '${context.tr(label)} · $count' : context.tr(label),
          style: textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: selected ? Theme.of(context).colorScheme.surface : null,
          ),
        ),
      ),
    );
  }

  Widget _buildTile(TextTheme textTheme, PaymentRequest r) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => PaymentRequestDetailsScreen(request: r)),
      ),
      leading: UserAvatar(
        pseudo: r.pseudo,
        avatarUrl: r.avatarUrl,
        radius: 22,
        backgroundColor: AppColors.secondary,
        foregroundColor: Colors.white,
      ),
      title: Text(
        context.tr(r.received ? 'payment_request_asks' : 'payment_request_to',
            {'pseudo': '@${r.pseudo}'}),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
      ),
      subtitle: Text(
        '${formatPaymentAmount(r.amount)} FCFA',
        style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
      trailing: _busy.contains(r.id)
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : !r.isPending
              ? PaymentRequestStatusPill(statut: r.statut)
              : r.received
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Refuser : icône (libellé pour l'accessibilité)
                        IconButton(
                          tooltip: context.tr('payment_request_decline'),
                          onPressed: () => _respond(r, 'refuser'),
                          icon: HugeIcon(
                            icon: HugeIcons.strokeRoundedCancel01,
                            size: 20,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(width: 4),
                        FilledButton(
                          // Inversé selon le thème : lisible en clair et en sombre
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.onSurface,
                            foregroundColor:
                                Theme.of(context).colorScheme.surface,
                          ),
                          onPressed: () => _pay(r),
                          child: Text(context.tr('payment_request_pay')),
                        ),
                      ],
                    )
                  : TextButton(
                      onPressed: () => _confirmCancel(r),
                      child: Text(context.tr('payment_request_cancel')),
                    ),
    );
  }
}

/// 25000 → « 25 000 »
String formatPaymentAmount(int v) =>
    v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');

/// Sheet de confirmation avant d'annuler une demande envoyée
Future<bool> confirmCancelPaymentRequest(
    BuildContext context, PaymentRequest r) async {
  final textTheme = Theme.of(context).textTheme;
  final onSurface = Theme.of(context).colorScheme.onSurface;
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      // Marge sous la barre de navigation système (affichage bord à bord)
      padding: EdgeInsets.fromLTRB(
          24, 0, 24, MediaQuery.viewPaddingOf(sheetContext).bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr('payment_request_cancel_title'),
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('payment_request_cancel_body', {
              'amount': '${formatPaymentAmount(r.amount)} FCFA',
              'pseudo': '@${r.pseudo}',
            }),
            style:
                textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: () => Navigator.pop(sheetContext, true),
            child: Text(context.tr('payment_request_cancel_confirm')),
          ),
          const SizedBox(height: 8),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: onSurface,
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: () => Navigator.pop(sheetContext, false),
            child: Text(context.tr('payment_request_cancel_keep')),
          ),
        ],
      ),
    ),
  );
  return confirmed == true;
}

/// Pastille de statut d'une demande (payée, refusée…)
class PaymentRequestStatusPill extends StatelessWidget {
  final String statut;

  const PaymentRequestStatusPill({super.key, required this.statut});

  @override
  Widget build(BuildContext context) {
    final color = switch (statut) {
      'payee' => AppColors.success,
      'en_paiement' => AppColors.warning,
      'refusee' => AppColors.error,
      _ => AppColors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Text(
        context.tr('payment_request_status_$statut'),
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
