import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import 'package:hugeicons/hugeicons.dart';
import '../models/merchant_category.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';

enum _Period { week, month, year }

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  _Period _period = _Period.month;

  /// Copie en cache tout de suite, puis version fraîche
  late SenoStatistics? _stats = SupabaseService.peekStatistics(_cacheName);
  bool _error = false;
  int _loadId = 0;

  String get _cacheName => 'statistics_${_period.name}';

  /// Début de la période en cours (semaine du lundi, mois, année)
  DateTime get _from {
    final now = DateTime.now();
    return switch (_period) {
      _Period.week => DateTime(now.year, now.month, now.day - (now.weekday - 1)),
      _Period.month => DateTime(now.year, now.month),
      _Period.year => DateTime(now.year),
    };
  }

  /// Fin exclusive de la période
  DateTime get _to {
    final from = _from;
    return switch (_period) {
      _Period.week => DateTime(from.year, from.month, from.day + 7),
      _Period.month => DateTime(from.year, from.month + 1),
      _Period.year => DateTime(from.year + 1),
    };
  }

  @override
  void initState() {
    super.initState();
    _load();
    // Nouvel envoi ou changement de statut : chiffres à jour
    SupabaseService.transactionsRevision.addListener(_load);
  }

  @override
  void dispose() {
    SupabaseService.transactionsRevision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final id = ++_loadId;
    try {
      final stats = await SupabaseService.getStatistics(
        from: _from,
        to: _to,
        cacheName: _cacheName,
      );
      if (!mounted || id != _loadId) return;
      setState(() {
        _stats = stats;
        _error = false;
      });
    } catch (_) {
      if (mounted && id == _loadId) setState(() => _error = true);
    }
  }

  void _setPeriod(_Period period) {
    if (period == _period) return;
    setState(() {
      _period = period;
      _stats = SupabaseService.peekStatistics(_cacheName);
      _error = false;
    });
    _load();
  }

  /// 12500 → « 12 500 F »
  String _fmt(int amount) {
    final digits = amount.abs().toString();
    final buf = StringBuffer(amount < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    return '$buf F';
  }

  /// Dépenses regroupées par barre : jours (semaine), semaines (mois), mois (année)
  List<({String label, int amount})> _buckets(SenoStatistics stats) {
    final from = _from;
    final labels = switch (_period) {
      _Period.week => context.tr('weekdays_short').split(','),
      _Period.month => [
          for (var i = 1;
              i <= ((DateUtils.getDaysInMonth(from.year, from.month) + 6) ~/ 7);
              i++)
            context.tr('week_short', {'n': '$i'}),
        ],
      _Period.year => context.tr('months_short').split(','),
    };
    final totals = List<int>.filled(labels.length, 0);
    stats.daily.forEach((day, v) {
      final index = switch (_period) {
        _Period.week => day.weekday - 1,
        _Period.month => (day.day - 1) ~/ 7,
        _Period.year => day.month - 1,
      };
      if (index >= 0 && index < totals.length) totals[index] += v.expenses;
    });
    return [
      for (var i = 0; i < labels.length; i++)
        (label: labels[i], amount: totals[i]),
    ];
  }

  /// Barre de la journée / semaine / mois en cours (mise en avant)
  int get _currentBucket {
    final now = DateTime.now();
    return switch (_period) {
      _Period.week => now.weekday - 1,
      _Period.month => (now.day - 1) ~/ 7,
      _Period.year => now.month - 1,
    };
  }

  Widget _buildStatCard({
    required String title,
    required String amount,
    required Color color,
    required dynamic icon,
  }) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: HugeIcon(
                  icon: icon,
                  size: 20,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                amount,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 18,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryStat({
    required String category,
    required String amount,
    required String subtitle,
    required double percentage,
    required Color color,
    required dynamic icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: HugeIcon(
                icon: icon,
                size: 24,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        category,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                      ),
                    ),
                    Text(
                      amount,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percentage,
                    minHeight: 6,
                    backgroundColor: color.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard(SenoStatistics stats) {
    final buckets = _buckets(stats);
    final maxValue =
        buckets.fold<int>(0, (m, b) => b.amount > m ? b.amount : m);
    final current = _currentBucket;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('spending_${_period.name}'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            _fmt(stats.expenses),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < buckets.length; i++)
                  Expanded(
                    child: Tooltip(
                      message: _fmt(buckets[i].amount),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                            width: buckets.length > 7 ? 14 : 28,
                            // Barre minimale visible même à zéro
                            height: maxValue == 0
                                ? 4
                                : 4 + (buckets[i].amount / maxValue) * 120,
                            decoration: BoxDecoration(
                              color: i == current
                                  ? AppColors.secondary
                                  : AppColors.secondary.withOpacity(0.35),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            buckets[i].label,
                            maxLines: 1,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppColors.textSecondary,
                                  fontSize: 10,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategories(SenoStatistics stats) {
    final categories = stats.categories;
    if (categories.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            context.tr('stats_empty'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final c in categories)
          () {
            // Envois à des personnes : pas de catégorie marchande
            final isTransfer = c.category == 'transfer';
            final merchant = MerchantCategory.byId(c.category);
            return _buildCategoryStat(
              category: context
                  .tr(isTransfer ? 'transfer' : merchant.labelKey),
              amount: _fmt(c.amount),
              subtitle: context.tr('stats_ops', {'n': '${c.count}'}),
              percentage:
                  stats.expenses == 0 ? 0 : c.amount / stats.expenses,
              color: isTransfer ? AppColors.secondary : merchant.color,
              icon: isTransfer
                  ? HugeIcons.strokeRoundedArrowUp01
                  : merchant.icon,
            );
          }(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.viewPadding.top;
    // Navbar flottante : barre système + bouton (56) + marges (8 + 32)
    final bottomPadding = mediaQuery.viewPadding.bottom + 96;
    final stats = _stats;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          // SafeArea en haut
          SizedBox(height: topPadding),
          // Contenu scrollable
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    // Header avec sélecteur de période
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            context.tr('nav_stats'),
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
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: DropdownButton<_Period>(
                              value: _period,
                              underline: const SizedBox(),
                              icon: Icon(
                                Icons.arrow_drop_down,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              items: _Period.values.map((period) {
                                return DropdownMenuItem<_Period>(
                                  value: period,
                                  child: Text(
                                    context.tr('period_${period.name}'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface,
                                        ),
                                  ),
                                );
                              }).toList(),
                              onChanged: (period) {
                                if (period != null) _setPeriod(period);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (stats == null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 80),
                        child: _error
                            ? Column(
                                children: [
                                  Text(
                                    context.tr('stats_load_error'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      setState(() => _error = false);
                                      _load();
                                    },
                                    child: Text(context.tr('retry')),
                                  ),
                                ],
                              )
                            : const CircularProgressIndicator(),
                      )
                    else ...[
                      // Cartes de statistiques
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          children: [
                            _buildStatCard(
                              title: context.tr('income'),
                              amount: _fmt(stats.income),
                              color: AppColors.success,
                              icon: HugeIcons.strokeRoundedArrowDown01,
                            ),
                            _buildStatCard(
                              title: context.tr('expenses'),
                              amount: _fmt(stats.expenses),
                              color: Colors.red,
                              icon: HugeIcons.strokeRoundedArrowUp01,
                            ),
                            _buildStatCard(
                              title: context.tr('balance'),
                              amount: _fmt(stats.income - stats.expenses),
                              color: AppColors.secondary,
                              icon: HugeIcons.strokeRoundedWallet01,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Graphique
                      _buildChartCard(stats),
                      // Dépenses par catégorie
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr('by_category'),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            _buildCategories(stats),
                          ],
                        ),
                      ),
                    ],
                    // Fin de page : rien n'est caché derrière la navbar
                    SizedBox(height: bottomPadding + 40),
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
