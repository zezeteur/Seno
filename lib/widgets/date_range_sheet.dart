import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';

/// Sheet de choix de période : onglets Début / Fin sur un même calendrier
class DateRangeSheet extends StatefulWidget {
  final DateTimeRange? initial;

  const DateRangeSheet({super.key, this.initial});

  @override
  State<DateRangeSheet> createState() => DateRangeSheetState();
}

class DateRangeSheetState extends State<DateRangeSheet> {
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
