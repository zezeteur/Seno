import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shimmer/shimmer.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';

class AccountLimitsScreen extends StatefulWidget {
  const AccountLimitsScreen({super.key});

  @override
  State<AccountLimitsScreen> createState() => _AccountLimitsScreenState();
}

class _AccountLimitsScreenState extends State<AccountLimitsScreen> {
  // Plafonds identiques pour tous (table plafonds_transfert, mis en cache)
  AccountLimits? _limits;
  // Montant déjà envoyé ce mois-ci
  ({int monthly})? _usage;
  // Premier chargement en cours : shimmers à la place des montants
  bool _limitsLoading = true;
  bool _usageLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLimits();
    _loadUsage();
    SupabaseService.transactionsRevision.addListener(_loadUsage);
  }

  @override
  void dispose() {
    SupabaseService.transactionsRevision.removeListener(_loadUsage);
    super.dispose();
  }

  Future<void> _loadLimits() async {
    try {
      final limits = await SupabaseService.getAccountLimits();
      if (mounted) setState(() => _limits = limits);
    } catch (_) {
      // Hors ligne sans cache : montants masqués
    } finally {
      if (mounted) setState(() => _limitsLoading = false);
    }
  }

  Future<void> _loadUsage() async {
    try {
      final usage = await SupabaseService.getLimitsUsage();
      if (mounted) setState(() => _usage = usage);
    } catch (_) {
      // Hors ligne : restants masqués
    } finally {
      if (mounted) setState(() => _usageLoading = false);
    }
  }

  static String _format(int? amount) {
    if (amount == null) return '—';
    final digits = amount.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return '$buffer FCFA';
  }

  /// Bloc gris animé à la place d'un montant ou de la jauge
  Widget _buildShimmer(double width, double height) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  Widget _buildIcon(dynamic icon) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.secondary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: HugeIcon(icon: icon, size: 20, color: AppColors.secondary),
      ),
    );
  }

  /// Plafond par envoi : pas de cumul, montant seul
  Widget _buildItem(dynamic icon, String title, int? amount) {
    return ListTile(
      leading: _buildIcon(icon),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
      ),
      trailing: _limitsLoading
          ? _buildShimmer(110, 16)
          : Text(
              _format(amount),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
            ),
    );
  }

  /// Cumul : montant restant, plafond et jauge de consommation
  Widget _buildUsageItem(
      dynamic icon, String title, int? limit, int? remaining) {
    final loading = _limitsLoading || _usageLoading;
    final progress = (limit != null && remaining != null && limit > 0)
        ? (limit - remaining) / limit
        : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildIcon(icon),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '${context.tr('limit_remaining')} ',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    Expanded(
                      child: loading
                          ? Align(
                              alignment: Alignment.centerLeft,
                              child: _buildShimmer(100, 16),
                            )
                          : Text(
                              _format(remaining),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (loading)
                  _buildShimmer(double.infinity, 6)
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor:
                          AppColors.textSecondary.withOpacity(0.15),
                      color: AppColors.secondary,
                    ),
                  ),
                const SizedBox(height: 6),
                if (loading)
                  _buildShimmer(120, 12)
                else
                  Text(
                    context.tr('limit_of', {'amount': _format(limit)}),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final divider =
        Divider(height: 1, color: AppColors.textSecondary.withOpacity(0.2));

    final limits = _limits;
    final usage = _usage;
    int? remainingMonthly;
    if (limits != null && usage != null) {
      remainingMonthly =
          (limits.monthly - usage.monthly).clamp(0, limits.monthly);
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SizedBox(height: mediaQuery.viewPadding.top),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadUsage,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header avec bouton retour
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.arrow_back,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            context.tr('account_limits'),
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 28,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        children: [
                          _buildItem(
                              HugeIcons
                                  .strokeRoundedArrowDataTransferHorizontal,
                              context.tr('limit_transaction'),
                              limits?.perTransaction),
                          divider,
                          _buildUsageItem(
                              HugeIcons.strokeRoundedCalendar03,
                              context.tr('limit_monthly'),
                              limits?.monthly,
                              remainingMonthly),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 12),
                      child: Text(
                        context.tr('account_limits_info'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ),
                    SizedBox(height: mediaQuery.viewPadding.bottom),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
