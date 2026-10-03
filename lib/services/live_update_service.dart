import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../l10n/app_strings.dart';
import 'supabase_service.dart';

/// Live Updates Android (notification promue Android 16+, ongoing avant).
/// No-op sur les autres plateformes.
class LiveUpdateService {
  LiveUpdateService._();

  static const _channel = MethodChannel('seno/live_updates');

  static bool get _enabled => Platform.isAndroid;

  /// Demande POST_NOTIFICATIONS (Android 13+).
  static Future<void> requestPermission() async {
    if (!_enabled) return;
    await _channel.invokeMethod('requestPermission');
  }

  /// true si l'appareil peut afficher des Live Updates promues.
  static Future<bool> isSupported() async {
    if (!_enabled) return false;
    return await _channel.invokeMethod<bool>('isSupported') ?? false;
  }

  /// Affiche ou met à jour un Live Update.
  /// [shortText] : texte du chip dans la barre d'état (ex. "2 500 F").
  /// [steps] : nombre d'étapes en segments (ex. 3 : envoyé / traité / reçu).
  static Future<bool> show({
    required int id,
    required String title,
    String? text,
    String? shortText,
    int progress = 0,
    int steps = 0,
    bool indeterminate = false,
    bool finished = false,
  }) async {
    if (!_enabled) return false;
    return await _channel.invokeMethod<bool>('show', {
          'id': id,
          'title': title,
          'text': text,
          'shortText': shortText,
          'progress': progress,
          'steps': steps,
          'indeterminate': indeterminate,
          'finished': finished,
        }) ??
        false;
  }

  static Future<void> end(int id) async {
    if (!_enabled) return;
    await _channel.invokeMethod('end', {'id': id});
  }
}

/// Suivi d'un envoi en Live Update : continue pendant que l'utilisateur valide
/// le paiement dans l'app de l'opérateur (Wave, MTN…) et après fermeture de
/// la page de suivi. Polling + événements Realtime, jusqu'à un statut final.
class LiveTransferTracker {
  LiveTransferTracker._(this.transfertId, this.amount, this.locale);

  static const _pollEvery = Duration(seconds: 8);
  static const _waitLimit = Duration(minutes: 10);
  static const _final = {
    'reussi',
    'collecte_echec',
    'transfert_echec',
    'rembourse_en_cours',
    'rembourse',
    'remboursement_echec',
  };

  static final _active = <String, LiveTransferTracker>{};

  final String transfertId;
  final String amount;
  final Locale locale;
  String _statut = 'collecte_en_attente';
  Timer? _timer;
  Timer? _expiry;
  StreamSubscription<({String id, String statut})>? _events;
  bool _polling = false;

  int get _notifId => transfertId.hashCode & 0x7fffffff;

  /// [amount] : montant déjà formaté (ex. « 5 000 FCFA »).
  static Future<void> start({
    required String transfertId,
    required String amount,
    required Locale locale,
  }) async {
    if (!Platform.isAndroid || _active.containsKey(transfertId)) return;
    await LiveUpdateService.requestPermission();
    final t = LiveTransferTracker._(transfertId, amount, locale);
    _active[transfertId] = t;
    t._render();
    t._events = SupabaseService.transfertEvents
        .where((e) => e.id == transfertId)
        .listen((e) => t._apply(e.statut));
    t._timer = Timer.periodic(_pollEvery, (_) => t._poll());
    t._expiry = Timer(_waitLimit, t._expire);
  }

  /// Statut connu par ailleurs (page de suivi) : mise à jour immédiate.
  static void update(String transfertId, String statut) =>
      _active[transfertId]?._apply(statut);

  String _tr(String key) => AppStrings.of(locale, key);

  void _apply(String statut) {
    if (statut == _statut) return;
    _statut = statut;
    _render();
    if (_final.contains(statut)) _stop();
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    try {
      _apply(await SupabaseService.getTransfertStatus(transfertId));
    } catch (_) {
      // Réseau instable : prochain tick
    } finally {
      _polling = false;
    }
  }

  Future<void> _expire() async {
    await _poll();
    if (_statut != 'collecte_en_attente') return;
    _stop();
    await LiveUpdateService.end(_notifId);
  }

  void _render() {
    final (title, progress, finished) = switch (_statut) {
      'reussi' => (_tr('send_success'), 100, true),
      'collecte_echec' => (_tr('send_payment_failed'), 0, true),
      'transfert_echec' ||
      'remboursement_echec' =>
        (_tr('send_payout_failed'), 66, true),
      'rembourse_en_cours' || 'rembourse' => (_tr('send_refunded'), 66, true),
      'transfert_en_cours' ||
      'reversement_relance' =>
        (_tr('send_processing'), 50, false),
      _ => (_tr('send_waiting_title'), 16, false),
    };
    LiveUpdateService.show(
      id: _notifId,
      title: title,
      text: amount,
      shortText: amount,
      progress: progress,
      steps: 3,
      finished: finished,
    );
  }

  void _stop() {
    _timer?.cancel();
    _expiry?.cancel();
    _events?.cancel();
    _active.remove(transfertId);
  }
}
