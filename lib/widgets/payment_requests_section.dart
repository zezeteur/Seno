import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../l10n/app_strings.dart';
import '../screens/payment_requests_screen.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';

/// Accueil : card résumant les demandes de paiement en attente (reçues et
/// envoyées) ;
/// le toucher ouvre la page des demandes. Rien n'est affiché sans demande.
class PaymentRequestsSection extends StatefulWidget {
  const PaymentRequestsSection({super.key});

  /// Card affichée : l'accueil masque alors les récents
  static final visible = ValueNotifier<bool>(false);

  @override
  State<PaymentRequestsSection> createState() => _PaymentRequestsSectionState();
}

class _PaymentRequestsSectionState extends State<PaymentRequestsSection>
    with WidgetsBindingObserver {
  int _received = 0;
  int _sent = 0;
  int _loadId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SupabaseService.paymentRequestsRevision.addListener(_load);
    SupabaseService.transactionsRevision.addListener(_load);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SupabaseService.paymentRequestsRevision.removeListener(_load);
    SupabaseService.transactionsRevision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final id = ++_loadId;
    try {
      final pending = (await SupabaseService.getMyPaymentRequests())
          .where((r) => r.isPending);
      if (mounted && id == _loadId) {
        setState(() {
          _received = pending.where((r) => r.received).length;
          _sent = pending.length - _received;
        });
        PaymentRequestsSection.visible.value = pending.isNotEmpty;
      }
    } catch (_) {
      // Hors ligne : le dernier nombre reste affiché
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_received == 0 && _sent == 0) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Material(
        // Mode sombre : fond plus marqué (5 % d'onSurface s'y voit à peine)
        color: Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkSurfaceVariant
            : onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PaymentRequestsScreen()),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: AppColors.secondary,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const HugeIcon(
                    icon: HugeIcons.strokeRoundedArrowDownLeft01,
                    size: 22,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('payment_requests_title'),
                        style: textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      // Ex. « 2 reçues · 1 envoyée » (en attente)
                      Text(
                        [
                          if (_received > 0)
                            context.tr(
                                _received == 1
                                    ? 'payment_requests_received_one'
                                    : 'payment_requests_received_count',
                                {'count': '$_received'}),
                          if (_sent > 0)
                            context.tr(
                                _sent == 1
                                    ? 'payment_requests_sent_one'
                                    : 'payment_requests_sent_count',
                                {'count': '$_sent'}),
                        ].join(' · '),
                        style: textTheme.bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowRight01,
                  size: 18,
                  color: onSurface.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
