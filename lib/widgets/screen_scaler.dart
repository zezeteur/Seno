import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Réduit proportionnellement toute l'interface sur les petits écrans.
///
/// Les pages sont dessinées pour un écran de référence ([referenceSize]) :
/// plus petit, le contenu est rendu sur un écran virtuel à cette taille puis
/// réduit pour tenir dans l'écran réel (textes, icônes, marges, boutons).
/// Sur les écrans assez grands, rien ne change.
class ScreenScaler extends StatelessWidget {
  const ScreenScaler({super.key, required this.child});

  final Widget child;

  static const referenceSize = Size(390, 800);

  /// Taille de police système maximale tolérée (évite les débordements).
  static const maxTextScale = 1.15;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final textScaler = mq.textScaler.clamp(maxScaleFactor: maxTextScale);

    final scale = size.isEmpty
        ? 1.0
        : math.min(
            1.0,
            math.min(size.width / referenceSize.width,
                size.height / referenceSize.height),
          );

    if (scale >= 0.99) {
      return MediaQuery(
          data: mq.copyWith(textScaler: textScaler), child: child);
    }

    final virtual = size / scale;
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: virtual.width,
          height: virtual.height,
          child: MediaQuery(
            data: mq.copyWith(
              size: virtual,
              devicePixelRatio: mq.devicePixelRatio * scale,
              textScaler: textScaler,
              padding: mq.padding / scale,
              viewPadding: mq.viewPadding / scale,
              viewInsets: mq.viewInsets / scale,
              systemGestureInsets: mq.systemGestureInsets / scale,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
