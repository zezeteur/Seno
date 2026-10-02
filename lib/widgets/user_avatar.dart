import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../models/merchant_category.dart';
import '../theme/app_colors.dart';

/// Avatar d'un utilisateur : photo si disponible, sinon initiale du pseudo,
/// sinon icône générique. Boutique sans logo : icône de sa catégorie.
class UserAvatar extends StatelessWidget {
  final String? pseudo;
  final String? avatarUrl;
  final double radius;
  final Color backgroundColor;
  final Color foregroundColor;

  /// Catégorie de la boutique (id de MerchantCategory) ; null = utilisateur
  final String? merchantCategory;

  const UserAvatar({
    super.key,
    this.pseudo,
    this.avatarUrl,
    this.radius = 40,
    this.backgroundColor = AppColors.textOnPrimary,
    this.foregroundColor = AppColors.primary,
    this.merchantCategory,
  });

  @override
  Widget build(BuildContext context) {
    final category = merchantCategory;
    if (category != null) {
      final c = MerchantCategory.byId(category);
      return CircleAvatar(
        radius: radius,
        backgroundColor: c.color,
        foregroundImage:
            avatarUrl != null ? CachedNetworkImageProvider(avatarUrl!) : null,
        onForegroundImageError: avatarUrl != null ? (_, __) {} : null,
        child: HugeIcon(icon: c.icon, size: radius * 0.9, color: Colors.white),
      );
    }
    final initial =
        (pseudo?.isNotEmpty ?? false) ? pseudo![0].toUpperCase() : null;

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      foregroundImage:
          avatarUrl != null ? CachedNetworkImageProvider(avatarUrl!) : null,
      // Photo introuvable : l'initiale ou l'icône reste affichée
      onForegroundImageError: avatarUrl != null ? (_, __) {} : null,
      child: initial != null
          ? Text(
              initial,
              style: TextStyle(
                fontSize: radius * 0.8,
                color: foregroundColor,
                fontWeight: FontWeight.bold,
              ),
            )
          : HugeIcon(
              icon: HugeIcons.strokeRoundedUser,
              size: radius * 0.9,
              color: foregroundColor,
            ),
    );
  }
}
