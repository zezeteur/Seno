import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../theme/app_colors.dart';

/// Points indiquant le nombre de chiffres saisis
class PinDots extends StatelessWidget {
  final int length;
  final int filled;
  final bool hasError;

  const PinDots({
    super.key,
    required this.length,
    required this.filled,
    this.hasError = false,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (i) {
        final isFilled = i < filled;
        final color = hasError
            ? AppColors.error
            : isFilled
                ? onSurface
                : onSurface.withValues(alpha: 0.15);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 10),
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled || hasError ? color : Colors.transparent,
            border: Border.all(color: color, width: 2),
          ),
        );
      }),
    );
  }
}

/// Clavier numérique intégré : 1-9, puis 0 et effacer
class PinKeypad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;

  const PinKeypad({super.key, required this.onDigit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    Widget key({required Widget child, VoidCallback? onTap}) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              splashColor: Colors.transparent,
              highlightColor: onSurface.withValues(alpha: 0.08),
              child: SizedBox(height: 68, child: Center(child: child)),
            ),
          ),
        ),
      );
    }

    Widget digit(String d) => key(
          onTap: () => onDigit(d),
          child: Text(
            d,
            style:
                textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        );

    return Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(children: row.map(digit).toList()),
        Row(
          children: [
            const Expanded(child: SizedBox()),
            digit('0'),
            key(
              onTap: onDelete,
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedTicketX,
                color: textTheme.bodyLarge?.color ?? Colors.black,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
