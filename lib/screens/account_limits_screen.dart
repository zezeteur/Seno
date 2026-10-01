import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import 'package:hugeicons/hugeicons.dart';
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

  @override
  void initState() {
    super.initState();
    _loadLimits();
  }

  Future<void> _loadLimits() async {
    try {
      final limits = await SupabaseService.getAccountLimits();
      if (mounted) setState(() => _limits = limits);
    } catch (_) {
      // Hors ligne sans cache : montants masqués
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

  Widget _buildItem(
      BuildContext context, dynamic icon, String title, int? amount) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.secondary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: HugeIcon(icon: icon, size: 20, color: AppColors.secondary),
        ),
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
      ),
      trailing: Text(
        _format(amount),
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final divider =
        Divider(height: 1, color: AppColors.textSecondary.withOpacity(0.2));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SizedBox(height: mediaQuery.viewPadding.top),
          Expanded(
            child: SingleChildScrollView(
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
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                                fontSize: 28,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      children: [
                        _buildItem(
                            context,
                            HugeIcons.strokeRoundedArrowDataTransferHorizontal,
                            context.tr('limit_transaction'),
                            _limits?.perTransaction),
                        divider,
                        _buildItem(context, HugeIcons.strokeRoundedCalendar01,
                            context.tr('limit_daily'), _limits?.daily),
                        divider,
                        _buildItem(context, HugeIcons.strokeRoundedCalendar03,
                            context.tr('limit_monthly'), _limits?.monthly),
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
        ],
      ),
    );
  }
}
