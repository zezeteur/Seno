import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import 'package:hugeicons/hugeicons.dart';
import '../theme/app_colors.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  String _selectedPeriod = 'period_month';

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
            Text(
              amount,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 18,
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
                    Text(
                      category,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
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

  Widget _buildChartCard() {
    // Données d'exemple pour le graphique
    final chartData = [0.3, 0.5, 0.4, 0.7, 0.6, 0.8, 0.5];
    final maxValue = chartData.reduce((a, b) => a > b ? a : b);

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
            context.tr('weekly_spending'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: chartData.asMap().entries.map((entry) {
                final index = entry.key;
                final value = entry.value;
                final height = (value / maxValue) * 130;
                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      width: 30,
                      height: height,
                      decoration: BoxDecoration(
                        color: AppColors.secondary,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.tr('weekdays_short').split(',')[index],
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                          ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.viewPadding.top;
    // Navbar flottante : barre système + bouton (56) + marges (8 + 32)
    final bottomPadding = mediaQuery.viewPadding.bottom + 96;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          // SafeArea en haut
          SizedBox(height: topPadding),
          // Contenu scrollable
          Expanded(
            child: SingleChildScrollView(
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
                                color: Theme.of(context).colorScheme.onSurface,
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
                          child: DropdownButton<String>(
                            value: _selectedPeriod,
                            underline: const SizedBox(),
                            icon: Icon(
                              Icons.arrow_drop_down,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            items: [
                              'period_week',
                              'period_month',
                              'period_year'
                            ].map((String period) {
                              return DropdownMenuItem<String>(
                                value: period,
                                child: Text(
                                  context.tr(period),
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
                            onChanged: (String? newValue) {
                              if (newValue != null) {
                                setState(() {
                                  _selectedPeriod = newValue;
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Cartes de statistiques
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        _buildStatCard(
                          title: context.tr('income'),
                          amount: '12 500 F',
                          color: AppColors.success,
                          icon: HugeIcons.strokeRoundedArrowDown01,
                        ),
                        _buildStatCard(
                          title: context.tr('expenses'),
                          amount: '8 300 F',
                          color: Colors.red,
                          icon: HugeIcons.strokeRoundedArrowUp01,
                        ),
                        _buildStatCard(
                          title: context.tr('balance'),
                          amount: '4 200 F',
                          color: AppColors.secondary,
                          icon: HugeIcons.strokeRoundedWallet01,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Graphique
                  _buildChartCard(),
                  // Statistiques par catégorie
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                        ),
                        const SizedBox(height: 12),
                        _buildCategoryStat(
                          category: context.tr('cat_restaurant'),
                          amount: '2 500 F',
                          percentage: 0.6,
                          color: Colors.orange,
                          icon: HugeIcons.strokeRoundedRestaurant01,
                        ),
                        _buildCategoryStat(
                          category: context.tr('cat_shopping'),
                          amount: '1 800 F',
                          percentage: 0.45,
                          color: Colors.pink,
                          icon: HugeIcons.strokeRoundedShoppingBag01,
                        ),
                        _buildCategoryStat(
                          category: context.tr('cat_transport'),
                          amount: '1 200 F',
                          percentage: 0.3,
                          color: Colors.blue,
                          icon: HugeIcons.strokeRoundedCar01,
                        ),
                        _buildCategoryStat(
                          category: context.tr('cat_entertainment'),
                          amount: '1 500 F',
                          percentage: 0.38,
                          color: Colors.purple,
                          icon: HugeIcons.strokeRoundedPlay,
                        ),
                        _buildCategoryStat(
                          category: context.tr('cat_other'),
                          amount: '1 300 F',
                          percentage: 0.32,
                          color: Colors.grey,
                          icon: HugeIcons.strokeRoundedSettings01,
                        ),
                      ],
                    ),
                  ),
                  // Fin de page : rien n'est caché derrière la navbar
                  SizedBox(height: bottomPadding + 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
