import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../screens/transaction_details_screen.dart';
import 'supabase_service.dart';

/// Retour de la page de paiement (Wave / Orange) :
/// com.neotech.seno://payment/<id> rouvre l'app sur l'envoi concerné.
class PaymentReturnService {
  static GlobalKey<NavigatorState>? _navigatorKey;
  static StreamSubscription<Uri>? _sub;
  static final _uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false);

  /// Envoi suivi par la page de progression ouverte (elle se met à jour seule)
  static String? trackedTransfertId;

  /// Lien reçu avant l'accueil (démarrage à froid) : ouvert par [homeReady]
  static String? _pendingId;
  static bool _homeReady = false;

  static void init(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    _sub ??= AppLinks().uriLinkStream.listen(_handle);
  }

  /// Accueil affiché (session ouverte) : traite un lien en attente
  static void homeReady() {
    _homeReady = true;
    final id = _pendingId;
    _pendingId = null;
    if (id != null) _open(id);
  }

  static void _handle(Uri uri) {
    if (uri.scheme != 'com.neotech.seno' || uri.host != 'payment') return;
    final id = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
    if (id == null || !_uuid.hasMatch(id)) return;
    SupabaseService.transactionsRevision.value++;
    if (id == trackedTransfertId) return;
    if (_homeReady) {
      _open(id);
    } else {
      _pendingId = id;
    }
  }

  static Future<void> _open(String id) async {
    final SenoTransaction? tx;
    try {
      tx = await SupabaseService.findSentTransaction(id);
    } catch (_) {
      return;
    }
    final nav = _navigatorKey?.currentState;
    if (tx == null || nav == null) return;
    nav.push(MaterialPageRoute(
      builder: (_) => TransactionDetailsScreen(transaction: tx!),
    ));
  }
}
