import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../services/supabase_service.dart';
import '../widgets/transaction_list.dart';

enum _Filter { all, sent, received }

/// Historique complet des transactions, filtrable (tous / envois / reçus)
/// et par période (bouton flottant)
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  /// Transactions chargées par page ; la suivante arrive en approchant du bas
  static const _pageSize = 30;

  /// Distance au bas de la liste (px) qui déclenche la page suivante
  static const _loadMoreThreshold = 400.0;

  _Filter _filter = _Filter.all;

  /// Période choisie (jours inclus) ; null = toutes les dates
  DateTimeRange? _range;

  /// Borne haute exclusive envoyée au serveur : lendemain du dernier jour
  DateTime? get _rangeEnd => _range == null
      ? null
      : DateTime(_range!.end.year, _range!.end.month, _range!.end.day + 1);

  /// Page ayant atteint le début de la période : inutile d'aller plus loin
  bool _reachedRangeStart(List<SenoTransaction> page) =>
      _range != null &&
      page.isNotEmpty &&
      page.last.createdAt.isBefore(_range!.start);

  /// Première page en cache par filtre (affichage immédiat, hors ligne)
  String get _cacheName => 'transactions_all_${_filter.name}';

  /// Sens demandé au serveur (le filtre s'applique avant la pagination)
  String? get _sens => switch (_filter) {
        _Filter.all => null,
        _Filter.sent => 'envoi',
        _Filter.received => 'reception',
      };

  /// Copie en cache tout de suite, puis version fraîche
  late List<SenoTransaction>? _transactions =
      SupabaseService.peekTransactions(cacheName: _cacheName);
  bool _error = false;
  int _loadId = 0;
  bool _hasMore = true;
  bool _loadingMore = false;
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _scrollController.addListener(_onScroll);
    // Changement de statut en direct (Realtime) ou nouvel envoi
    SupabaseService.transactionsRevision.addListener(_load);
  }

  @override
  void dispose() {
    SupabaseService.transactionsRevision.removeListener(_load);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Première page (ouverture, filtre, actualisation, temps réel).
  /// Les pages plus anciennes déjà chargées sont conservées.
  Future<void> _load() async {
    final id = ++_loadId;
    try {
      final page = await SupabaseService.getTransactions(
        limit: _pageSize,
        cacheName: _cacheName,
        // Période : hors cache (le cache ne garde que la première page sans date)
        before: _rangeEnd,
        sens: _sens,
      );
      if (!mounted || id != _loadId) return;
      final previous = _transactions ?? const <SenoTransaction>[];
      final older = page.length < _pageSize
          ? const <SenoTransaction>[]
          : previous
              .where((t) => t.createdAt.isBefore(page.last.createdAt))
              .toList();
      setState(() {
        _transactions = [...page, ...older];
        _hasMore = older.isNotEmpty ? _hasMore : page.length == _pageSize;
        if (_reachedRangeStart(page)) _hasMore = false;
        _error = false;
      });
      _fillViewport();
    } catch (_) {
      if (mounted && id == _loadId) setState(() => _error = true);
    }
  }

  /// Page suivante : transactions antérieures à la dernière affichée
  Future<void> _loadMore() async {
    final current = _transactions;
    if (!_hasMore || _loadingMore || current == null || current.isEmpty) {
      return;
    }
    final id = _loadId;
    setState(() => _loadingMore = true);
    try {
      final page = await SupabaseService.getTransactions(
        limit: _pageSize,
        before: current.last.createdAt,
        sens: _sens,
      );
      // Filtre changé ou liste rechargée entre-temps : page ignorée
      if (!mounted || id != _loadId) return;
      final known = current.map((t) => t.id).toSet();
      setState(() {
        _transactions = [
          ...current,
          ...page.where((t) => !known.contains(t.id)),
        ];
        _hasMore = page.length == _pageSize && !_reachedRangeStart(page);
      });
      _fillViewport();
    } catch (_) {
      // Hors ligne : nouvel essai au prochain défilement
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onScroll() {
    final position = _scrollController.position;
    if (position.extentAfter < _loadMoreThreshold) _loadMore();
  }

  /// Liste trop courte pour défiler (peu de résultats, recherche) : on charge
  /// la suite sans attendre un défilement impossible
  void _fillViewport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_scrollController.position.extentAfter < _loadMoreThreshold) {
        _loadMore();
      }
    });
  }

  void _setFilter(_Filter filter) {
    if (filter == _filter) return;
    _reload(() => _filter = filter);
  }

  void _setRange(DateTimeRange? range) {
    if (range == _range) return;
    _reload(() => _range = range);
  }

  /// Applique un changement de critère puis repart de la première page
  void _reload(VoidCallback change) {
    setState(() {
      change();
      _transactions = _range == null
          ? SupabaseService.peekTransactions(cacheName: _cacheName)
          : null;
      _hasMore = true;
      _error = false;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    _load();
  }

  List<SenoTransaction> get _filtered {
    var all = _transactions ?? const <SenoTransaction>[];
    final range = _range;
    if (range != null) {
      all = all
          .where((t) =>
              !t.createdAt.isBefore(range.start) &&
              t.createdAt.isBefore(_rangeEnd!))
          .toList();
    }
    final byType = switch (_filter) {
      _Filter.all => all,
      _Filter.sent => all.where((t) => !t.isReceived).toList(),
      _Filter.received => all.where((t) => t.isReceived).toList(),
    };
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return byType;
    // Montants et numéros comparés sans espaces (« 25 000 » → 25000)
    final digits = q.replaceAll(' ', '');
    return byType.where((t) {
      if (t.label.toLowerCase().contains(q)) return true;
      if (digits.isEmpty) return false;
      return t.numero.replaceAll(' ', '').contains(digits) ||
          t.montant.toString().contains(digits);
    }).toList();
  }

  Widget _searchBar(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    // Bordures explicites : sinon celles du thème écrasent l'arrondi
    final pill = OutlineInputBorder(
      borderRadius: BorderRadius.circular(50),
      borderSide: BorderSide.none,
    );
    return TextField(
      controller: _searchController,
      onChanged: (v) {
        setState(() => _query = v);
        // Recherche dans les transactions chargées : charger la suite si peu de résultats
        _fillViewport();
      },
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: context.tr('history_search_hint'),
        hintStyle: TextStyle(color: onSurface.withValues(alpha: 0.4)),
        prefixIcon: Icon(Icons.search, color: onSurface.withValues(alpha: 0.5)),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon:
                    Icon(Icons.close, color: onSurface.withValues(alpha: 0.5)),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),
        filled: true,
        fillColor: onSurface.withValues(alpha: 0.05),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: pill,
        enabledBorder: pill,
        // Bordure visible uniquement quand le champ est sélectionné
        focusedBorder: pill.copyWith(
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, _Filter filter, String label) {
    final selected = _filter == filter;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GestureDetector(
      onTap: () => _setFilter(filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.transparent,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: selected ? Colors.black : onSurface.withValues(alpha: 0.15),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Future<void> _pickRange() async {
    final picked = await showModalBottomSheet<DateTimeRange>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DateRangeSheet(initial: _range),
    );
    if (picked != null && mounted) _setRange(picked);
  }

  /// 03/09 – 15/09 (année affichée si différente de l'année en cours)
  String _rangeLabel(DateTimeRange range) {
    String d(DateTime x) {
      final dm = '${x.day.toString().padLeft(2, '0')}/'
          '${x.month.toString().padLeft(2, '0')}';
      return x.year == DateTime.now().year ? dm : '$dm/${x.year}';
    }

    return range.start == range.end
        ? d(range.start)
        : '${d(range.start)} – ${d(range.end)}';
  }

  Widget _dateButton(BuildContext context) {
    final range = _range;
    if (range == null) {
      return FloatingActionButton.extended(
        onPressed: _pickRange,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
        icon: const Icon(Icons.calendar_today_outlined, size: 20),
        label: Text(
          context.tr('history_filter_date'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      );
    }
    // Période active : affichée sur le bouton, croix pour l'effacer
    return Material(
      color: Colors.black,
      shape: const StadiumBorder(),
      elevation: 6,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            customBorder: const StadiumBorder(),
            onTap: _pickRange,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 4, 16),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 20, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    _rangeLabel(range),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
            onPressed: () => _setRange(null),
          ),
        ],
      ),
    );
  }

  Widget _message(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewPaddingOf(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final transactions = _transactions;
    final filtered = _filtered;

    final Widget content;
    if (transactions == null) {
      content = _error
          ? _message(context, context.tr('tx_load_error'))
          : const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
    } else if (transactions.isEmpty) {
      content = _message(context, context.tr('tx_empty'));
    } else if (filtered.isEmpty) {
      content = _message(
        context,
        context.tr(_query.trim().isEmpty
            ? 'history_empty_filter'
            : 'history_search_empty'),
      );
    } else {
      content = TransactionList(transactions: filtered);
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // Remonté au-dessus de la barre système, comme le bouton du sheet
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: padding.bottom + 16),
        child: _dateButton(context),
      ),
      body: Column(
        children: [
          SizedBox(height: padding.top),
          // Header avec bouton retour
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: onSurface),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                Text(
                  context.tr('history'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 28,
                      ),
                ),
              ],
            ),
          ),
          // Recherche
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: _searchBar(context),
          ),
          // Filtres
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _chip(context, _Filter.all, context.tr('history_all')),
                const SizedBox(width: 8),
                _chip(context, _Filter.sent, context.tr('history_sent')),
                const SizedBox(width: 8),
                _chip(
                    context, _Filter.received, context.tr('history_received')),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(20, 0, 20, padding.bottom + 120),
                children: [
                  content,
                  // Page suivante en cours de chargement
                  if (_loadingMore)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
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

/// Sheet de choix de période : onglets Début / Fin sur un même calendrier
class _DateRangeSheet extends StatefulWidget {
  final DateTimeRange? initial;

  const _DateRangeSheet({this.initial});

  @override
  State<_DateRangeSheet> createState() => _DateRangeSheetState();
}

class _DateRangeSheetState extends State<_DateRangeSheet> {
  static final _firstDate = DateTime(2024);
  late final DateTime _today = DateUtils.dateOnly(DateTime.now());
  late DateTime _start = widget.initial?.start ?? _today;
  late DateTime _end = widget.initial?.end ?? _today;
  bool _editingStart = true;

  String _format(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  void _onDate(DateTime d) {
    setState(() {
      if (_editingStart) {
        _start = d;
        // Début après la fin : la fin suit, puis on passe à la fin
        if (_end.isBefore(d)) _end = d;
        _editingStart = false;
      } else {
        _end = d;
        if (d.isBefore(_start)) _start = d;
      }
    });
  }

  Widget _tab(String label, DateTime date, bool selected) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _editingStart = label == 'start'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: selected ? Colors.black : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
                  selected ? Colors.black : onSurface.withValues(alpha: 0.15),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(label == 'start' ? 'history_from' : 'history_to'),
                style: TextStyle(
                  fontSize: 12,
                  color: (selected ? Colors.white : onSurface)
                      .withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _format(date),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: selected ? Colors.white : onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Marge sous le bouton + barre système (le SafeArea seul ne suffit pas)
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _tab('start', _start, _editingStart),
                const SizedBox(width: 12),
                _tab('end', _end, !_editingStart),
              ],
            ),
            CalendarDatePicker(
              // Clé : le calendrier se replace sur la date de l'onglet actif
              key: ValueKey(_editingStart),
              initialDate: _editingStart ? _start : _end,
              firstDate: _firstDate,
              lastDate: _today,
              onDateChanged: _onDate,
            ),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                ),
                onPressed: () => Navigator.of(context)
                    .pop(DateTimeRange(start: _start, end: _end)),
                child: Text(
                  context.tr('history_apply'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
