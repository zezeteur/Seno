import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import 'package:hugeicons/hugeicons.dart';
import '../models/merchant_category.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import '../widgets/date_range_sheet.dart';

enum _Period { week, month, year, range }

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  _Period _period = _Period.month;

  /// Jour ou intervalle choisi (bornes incluses), pour range
  DateTimeRange? _custom;

  /// Copie en cache tout de suite, puis version fraîche
  late SenoStatistics? _stats = SupabaseService.peekStatistics(_cacheName);
  bool _error = false;
  int _loadId = 0;
  bool _graph = true;
  int _selected = 0;
  final _pageController = PageController(viewportFraction: 0.6);

  /// Dates choisies : une entrée de cache par jour / intervalle
  String get _cacheName => switch (_period) {
        _Period.range =>
          'statistics_${_period.name}_${_dayKey(_from)}_${_dayKey(_to)}',
        _ => 'statistics_${_period.name}',
      };

  static String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// 16 Oct 2026
  String _fmtDate(DateTime d) =>
      '${d.day} ${context.tr('months_short').split(',')[d.month - 1]} ${d.year}';

  /// Début de la période en cours (semaine du lundi, mois, année)
  DateTime get _from {
    final now = DateTime.now();
    return switch (_period) {
      _Period.week => DateTime(now.year, now.month, now.day - (now.weekday - 1)),
      _Period.month => DateTime(now.year, now.month),
      _Period.year => DateTime(now.year),
      _Period.range => _custom!.start,
    };
  }

  /// Fin exclusive de la période
  DateTime get _to {
    final from = _from;
    return switch (_period) {
      _Period.week => DateTime(from.year, from.month, from.day + 7),
      _Period.month => DateTime(from.year, from.month + 1),
      _Period.year => DateTime(from.year + 1),
      _Period.range => DateTime(_custom!.end.year,
          _custom!.end.month, _custom!.end.day + 1),
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
    _pageController.dispose();
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

  void _setPeriod(_Period period, [DateTimeRange? custom]) {
    if (period == _period && custom == null) return;
    setState(() {
      _period = period;
      _custom = custom;
      _selected = 0;
      _stats = SupabaseService.peekStatistics(_cacheName);
      _error = false;
    });
    if (_pageController.hasClients) _pageController.jumpToPage(0);
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

  /// « Total dépensé en Oct 2026 »
  String get _totalLabel {
    final from = _from;
    return switch (_period) {
      _Period.week => context.tr('total_spent_week'),
      _Period.month => context.tr('total_spent_month', {
          'period':
              '${context.tr('months_short').split(',')[from.month - 1]} ${from.year}',
        }),
      _Period.year =>
        context.tr('total_spent_year', {'period': '${from.year}'}),
      _Period.range when _custom!.start == _custom!.end =>
        context.tr('total_spent_on', {'period': _fmtDate(from)}),
      _Period.range => context.tr('total_spent_between', {
          'from': _fmtDate(from),
          'to': _fmtDate(_custom!.end),
        }),
    };
  }

  /// Libellé, couleur et icône d'une catégorie de dépense
  ({String label, Color color, dynamic icon}) _categoryInfo(String id) {
    // Argent reçu sur la période
    if (id == 'income') {
      return (
        label: context.tr('income'),
        color: AppColors.success,
        icon: HugeIcons.strokeRoundedArrowDown01,
      );
    }
    // Envois à des personnes : pas de catégorie marchande
    if (id == 'transfer') {
      return (
        label: context.tr('transfer'),
        color: AppColors.secondary,
        icon: HugeIcons.strokeRoundedArrowUp01,
      );
    }
    final merchant = MerchantCategory.byId(id);
    return (
      label: context.tr(merchant.labelKey),
      color: merchant.color,
      icon: merchant.icon,
    );
  }

  Future<void> _pickPeriod() async {
    final period = await showModalBottomSheet<_Period>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                ctx.tr('stats_period'),
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              for (final p in _Period.values)
                ListTile(
                  title: Text(ctx.tr('period_${p.name}')),
                  subtitle: p == _period && _custom != null
                      ? Text(_custom!.start == _custom!.end
                          ? _fmtDate(_custom!.start)
                          : '${_fmtDate(_custom!.start)} – ${_fmtDate(_custom!.end)}')
                      : null,
                  trailing: p == _period
                      ? const Icon(Icons.check, color: AppColors.secondary)
                      : null,
                  onTap: () => Navigator.pop(ctx, p),
                ),
            ],
          ),
        ),
      ),
    );
    if (period == null || !mounted) return;
    if (period != _Period.range) return _setPeriod(period);
    // Même sheet que l'historique : un jour (début = fin) ou un intervalle
    final range = await showModalBottomSheet<DateTimeRange>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DateRangeSheet(initial: _custom),
    );
    if (range != null && mounted) _setPeriod(period, range);
  }

  Widget _buildToggle() {
    final scheme = Theme.of(context).colorScheme;
    Widget tab(String key, bool graph) {
      final selected = _graph == graph;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _graph = graph),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.secondary : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              context.tr(key),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : scheme.onSurface,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 252,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(children: [tab('stats_graph', true), tab('stats_list', false)]),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Text(
          context.tr('stats_empty'),
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
        ),
      ),
    );
  }

  /// Catégories de dépense, puis les revenus de la période
  List<({String category, int amount, int count})> _entries(
          SenoStatistics stats) =>
      [
        ...stats.categories,
        if (stats.income > 0)
          (category: 'income', amount: stats.income, count: 0),
      ];

  Widget _buildGraph(SenoStatistics stats) {
    final categories = _entries(stats);
    if (categories.isEmpty) return _buildEmpty();
    final selected = _selected.clamp(0, categories.length - 1);
    final scheme = Theme.of(context).colorScheme;
    final amount = _fmt(categories[selected].amount);

    return Column(
      children: [
        SizedBox(
          width: 270,
          height: 270,
          child: CustomPaint(
            painter: _DonutPainter(
              values: [
                for (final c in stats.categories) c.amount.toDouble()
              ],
              colors: [
                for (final c in stats.categories)
                  _categoryInfo(c.category).color
              ],
              selected: selected,
              selectedColor: AppColors.success,
              track: scheme.surface,
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: FittedBox(
                  child: Text(
                    amount,
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          height: 64,
          child: PageView.builder(
            controller: _pageController,
            itemCount: categories.length,
            onPageChanged: (i) => setState(() => _selected = i),
            itemBuilder: (context, i) {
              final info = _categoryInfo(categories[i].category);
              final active = i == selected;
              return GestureDetector(
                onTap: () => _pageController.animateToPage(
                  i,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: active
                        ? info.color.withValues(alpha: 0.18)
                        : scheme.surface,
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: info.color,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: HugeIcon(
                            icon: info.icon,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          info.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < categories.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: i == selected ? 8 : 6,
                height: i == selected ? 8 : 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == selected
                      ? _categoryInfo(categories[i].category).color
                      : AppColors.textSecondary.withValues(alpha: 0.4),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildList(SenoStatistics stats) {
    final categories = _entries(stats);
    if (categories.isEmpty) return _buildEmpty();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          for (final c in categories)
            () {
              final info = _categoryInfo(c.category);
              final isIncome = c.category == 'income';
              final percent = stats.expenses == 0
                  ? 0
                  : (c.amount * 100 / stats.expenses).round();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: info.color.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: HugeIcon(
                          icon: info.icon,
                          size: 20,
                          color: info.color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            info.label,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: scheme.onSurface,
                            ),
                          ),
                          // Revenus : pas de part des dépenses
                          if (!isIncome) ...[
                            const SizedBox(height: 2),
                            Text(
                              '$percent%',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${isIncome ? '+' : '-'} ${_fmt(c.amount)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              );
            }(),
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
                    // En-tête : titre centré + choix de la période
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 8, 8),
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
                          IconButton(
                            onPressed: _pickPeriod,
                            icon: HugeIcon(
                              icon: HugeIcons.strokeRoundedCalendar03,
                              size: 24,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildToggle(),
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
                      const SizedBox(height: 32),
                      // Total dépensé sur la période
                      Text(
                        _fmt(stats.expenses),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _totalLabel,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      SizedBox(height: _graph ? 40 : 24),
                      _graph ? _buildGraph(stats) : _buildList(stats),
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

/// Anneau segmenté : chaque catégorie dans sa couleur,
/// la sélectionnée plus épaisse, les autres atténuées
class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.values,
    required this.colors,
    required this.selected,
    required this.selectedColor,
    required this.track,
  });

  final List<double> values;
  final List<Color> colors;
  final int selected;

  /// Couleur de l'anneau plein quand les revenus sont sélectionnés
  final Color selectedColor;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 30.0;
    const selectedStroke = 40.0;
    const gap = 0.05; // radians entre deux segments
    final total = values.fold<double>(0, (a, b) => a + b);
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 - selectedStroke / 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    // Revenus sélectionnés ou aucune dépense : anneau plein
    if (selected >= values.length || total <= 0) {
      paint.color = selected >= values.length ? selectedColor : track;
      canvas.drawCircle(rect.center, rect.width / 2, paint);
      return;
    }
    final withGap = values.length > 1;
    var start = -3.14159265 / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * 2 * 3.14159265;
      final drawn = withGap ? (sweep - gap).clamp(0.005, sweep) : sweep;
      final active = i == selected;
      paint
        ..color = active ? colors[i] : colors[i].withValues(alpha: 0.3)
        ..strokeWidth = active ? selectedStroke : stroke;
      canvas.drawArc(rect, start + (withGap ? gap / 2 : 0), drawn.toDouble(),
          false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.selected != selected ||
      old.selectedColor != selectedColor ||
      old.track != track ||
      !_same(old.values, values) ||
      !_same(old.colors, colors);

  static bool _same<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
