import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

/// Bouton « glisser pour valider » : le pouce doit être amené au bout de la
/// piste. [onConfirmed] null = désactivé ; [loading] garde le pouce au bout
/// avec un indicateur de chargement.
class SlideButton extends StatefulWidget {
  final String label;
  final VoidCallback? onConfirmed;
  final bool loading;

  const SlideButton({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.loading = false,
  });

  @override
  State<SlideButton> createState() => _SlideButtonState();
}

class _SlideButtonState extends State<SlideButton>
    with SingleTickerProviderStateMixin {
  static const double _height = 64;
  static const double _padding = 4;
  static const double _thumb = _height - _padding * 2;
  static const double _threshold = 0.85;

  // Position du pouce, 0 (début) → 1 (bout)
  late final AnimationController _pos = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  bool _dragging = false;

  bool get _enabled => widget.onConfirmed != null && !widget.loading;

  @override
  void didUpdateWidget(SlideButton old) {
    super.didUpdateWidget(old);
    // Fin du chargement (échec) : le pouce revient au début
    if (old.loading && !widget.loading) {
      _pos.animateTo(0, curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _pos.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d, double track) {
    if (!_enabled) return;
    _dragging = true;
    _pos.value = (_pos.value + d.delta.dx / track).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails _) {
    if (!_dragging) return;
    _dragging = false;
    if (_pos.value >= _threshold) {
      HapticFeedback.mediumImpact();
      _pos.animateTo(1, curve: Curves.easeOutCubic);
      widget.onConfirmed?.call();
      // Pas de chargement déclenché (ex. confirmation annulée) : retour au début
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && !widget.loading) {
          _pos.animateTo(0, curve: Curves.easeOutCubic);
        }
      });
    } else {
      _pos.animateTo(0, curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onConfirmed == null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final track = constraints.maxWidth - _thumb - _padding * 2;
        return AnimatedBuilder(
          animation: _pos,
          builder: (context, _) {
            final x = (widget.loading ? 1.0 : _pos.value) * track;
            return Container(
              height: _height,
              decoration: BoxDecoration(
                color: disabled
                    ? Colors.black.withValues(alpha: 0.2)
                    : Colors.black,
                borderRadius: BorderRadius.circular(_height / 2),
              ),
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // Libellé qui s'efface à mesure que le pouce avance
                  Center(
                    child: Opacity(
                      opacity: widget.loading
                          ? 0
                          : (1 - _pos.value * 1.5).clamp(0.0, 1.0),
                      child: Text(
                        widget.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: _padding + x,
                    child: GestureDetector(
                      onHorizontalDragUpdate: (d) => _onDragUpdate(d, track),
                      onHorizontalDragEnd: _onDragEnd,
                      child: Container(
                        width: _thumb,
                        height: _thumb,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: widget.loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.black,
                                ),
                              )
                            : HugeIcon(
                                icon: HugeIcons.strokeRoundedArrowRight01,
                                color: disabled
                                    ? Colors.black.withValues(alpha: 0.3)
                                    : Colors.black,
                                size: 24,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
