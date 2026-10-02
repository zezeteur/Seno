import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

/// Catégorie d'activité d'un marchand. Référentiel unique : formulaire
/// marchand et statistiques par catégorie. L'id est stocké en base
/// (merchant_requests.category) : ne jamais renommer un id existant.
class MerchantCategory {
  const MerchantCategory(this.id, this.icon, this.color);

  final String id;
  final List<List<dynamic>> icon;
  final Color color;

  /// Clé de traduction (app_strings)
  String get labelKey => 'cat_$id';

  static const all = [
    MerchantCategory('groceries', HugeIcons.strokeRoundedShoppingBasket01,
        Color(0xFF4CAF50)),
    MerchantCategory(
        'restaurant', HugeIcons.strokeRoundedRestaurant01, Color(0xFFFF9800)),
    MerchantCategory(
        'cafe', HugeIcons.strokeRoundedCoffee01, Color(0xFF795548)),
    MerchantCategory(
        'shopping', HugeIcons.strokeRoundedShoppingBag01, Color(0xFFE91E63)),
    MerchantCategory(
        'fashion', HugeIcons.strokeRoundedTShirt, Color(0xFFAB47BC)),
    MerchantCategory(
        'electronics', HugeIcons.strokeRoundedLaptop, Color(0xFF3F51B5)),
    MerchantCategory(
        'beauty', HugeIcons.strokeRoundedHairDryer, Color(0xFFF06292)),
    MerchantCategory(
        'health', HugeIcons.strokeRoundedMedicine01, Color(0xFFF44336)),
    MerchantCategory(
        'transport', HugeIcons.strokeRoundedCar01, Color(0xFF2196F3)),
    MerchantCategory(
        'fuel', HugeIcons.strokeRoundedFuelStation, Color(0xFF607D8B)),
    MerchantCategory(
        'housing', HugeIcons.strokeRoundedHome01, Color(0xFF8D6E63)),
    MerchantCategory(
        'utilities', HugeIcons.strokeRoundedFlash, Color(0xFFFFC107)),
    MerchantCategory(
        'telecom', HugeIcons.strokeRoundedWifi01, Color(0xFF00BCD4)),
    MerchantCategory(
        'education', HugeIcons.strokeRoundedMortarboard01, Color(0xFF5C6BC0)),
    MerchantCategory(
        'entertainment', HugeIcons.strokeRoundedPlay, Color(0xFF9C27B0)),
    MerchantCategory(
        'sports', HugeIcons.strokeRoundedFootball, Color(0xFF26A69A)),
    MerchantCategory(
        'travel', HugeIcons.strokeRoundedAirplane01, Color(0xFF29B6F6)),
    MerchantCategory(
        'services', HugeIcons.strokeRoundedWrench01, Color(0xFF78909C)),
    MerchantCategory(
        'online', HugeIcons.strokeRoundedShoppingCart01, Color(0xFF7E57C2)),
    MerchantCategory(
        'other', HugeIcons.strokeRoundedMoreHorizontal, Color(0xFF9E9E9E)),
  ];

  static MerchantCategory byId(String? id) =>
      all.firstWhere((c) => c.id == id, orElse: () => all.last);
}
