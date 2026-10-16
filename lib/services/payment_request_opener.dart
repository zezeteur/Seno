import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/payment_request_details_screen.dart';
import 'supabase_service.dart';

/// Demande de paiement reçue (boutique ou particulier) : son détail s'ouvre
/// automatiquement, pour payer sans chercher la demande.
class PaymentRequestOpener {
  static GlobalKey<NavigatorState>? _navigatorKey;
  static StreamSubscription<String>? _sub;

  /// Demandes déjà ouvertes : une seule ouverture par demande
  static final _opened = <String>{};

  static void init(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    _sub ??= SupabaseService.paymentRequestEvents.listen(_handle);
  }

  static Future<void> _handle(String id) async {
    if (_opened.contains(id)) return;
    try {
      final request = (await SupabaseService.getMyPaymentRequests())
          .where((r) => r.id == id)
          .firstOrNull;
      if (request == null ||
          !request.received ||
          !request.isPending ||
          !_opened.add(id)) {
        return;
      }
      _navigatorKey?.currentState?.push(MaterialPageRoute(
          builder: (_) => PaymentRequestDetailsScreen(request: request)));
    } catch (_) {
      // Hors ligne : la demande reste visible sur l'accueil
    }
  }
}
