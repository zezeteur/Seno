import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Photo en plein écran : zoom (pincer), fermeture au toucher ou retour.
/// [heroTag] : même tag que l'avatar d'origine pour l'animation d'agrandissement.
void showPhotoViewer(BuildContext context, String url, {Object? heroTag}) {
  Widget image = Image(
    image: CachedNetworkImageProvider(url),
    fit: BoxFit.contain,
    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
  );
  if (heroTag != null) image = Hero(tag: heroTag, child: image);

  Navigator.of(context).push(PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.black87,
    barrierDismissible: true,
    pageBuilder: (context, _, __) => GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: InteractiveViewer(maxScale: 4, child: image),
        ),
      ),
    ),
  ));
}
