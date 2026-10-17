import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'supabase_service.dart';

/// Personne ou boutique Seno détectée à proximité (jeton BLE résolu par le
/// serveur). Boutique : [name] = nom du commerce, [category] pour l'icône.
typedef NearbyPerson = ({
  String token,
  String pseudo,
  String? name,
  String? avatarUrl,
  int rssi,
  bool isShop,
  String? category,
});

/// État de l'envoi à proximité affiché par la page radar
enum NearbyStatus { idle, searching, bluetoothOff, unsupported, error }

/// Envoi à proximité en BLE, identique sur Android et iOS :
/// - chaque téléphone diffuse un jeton éphémère comme identifiant de service
///   (iOS ne permet de diffuser que des identifiants de service et un nom) ;
/// - chaque téléphone scanne les jetons au préfixe Seno et demande au serveur
///   à qui ils appartiennent. Le jeton ne révèle rien sans le serveur.
class NearbyService {
  NearbyService._();

  /// Doit correspondre à TOKEN_PREFIX de l'Edge Function `nearby`
  static const _tokenPrefix = '5e70a1b2';

  /// Jeton valable 180 s côté serveur : on le renouvelle avant
  static const _tokenRefresh = Duration(seconds: 150);

  /// Appareil qui ne diffuse plus depuis ce délai : retiré de la liste
  static const _goneAfter = Duration(seconds: 8);

  static final people = ValueNotifier<List<NearbyPerson>>([]);
  static final status = ValueNotifier<NearbyStatus>(NearbyStatus.idle);

  static final _peripheral = FlutterBlePeripheral();
  static StreamSubscription<List<ScanResult>>? _scanSub;
  static StreamSubscription<BluetoothAdapterState>? _adapterSub;
  static Timer? _refreshTimer;
  static Timer? _resolveTimer;
  static bool _running = false;

  /// Jetons vus → dernière détection et puissance du signal
  static final _seen = <String, ({DateTime at, int rssi})>{};

  /// Jetons déjà résolus (personne et éventuelle boutique ; vide si inconnu)
  static final _resolved = <String, List<NearbyPerson>>{};
  static final _resolving = <String>{};

  /// Démarre la diffusion et le scan ; appelée à l'ouverture de la page radar
  static Future<void> start() async {
    if (_running) return;
    _running = true;
    status.value = NearbyStatus.searching;

    if (!await FlutterBluePlus.isSupported) {
      status.value = NearbyStatus.unsupported;
      return;
    }

    // Bluetooth coupé puis rallumé : on relance diffusion et scan
    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      if (!_running) return;
      if (state == BluetoothAdapterState.on) {
        status.value = NearbyStatus.searching;
        _startRadio();
      } else if (state == BluetoothAdapterState.off) {
        status.value = NearbyStatus.bluetoothOff;
        _stopRadio();
      }
    });

    if (defaultTargetPlatform == TargetPlatform.android &&
        FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {
        status.value = NearbyStatus.bluetoothOff;
      }
    }
  }

  /// Arrête tout et supprime le jeton côté serveur (page radar fermée)
  static Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _adapterSub?.cancel();
    _adapterSub = null;
    await _stopRadio();
    _seen.clear();
    _resolved.clear();
    _resolving.clear();
    people.value = [];
    status.value = NearbyStatus.idle;
    try {
      await SupabaseService.client?.functions
          .invoke('nearby', body: {'action': 'stop'});
    } catch (_) {
      // Le jeton expire de toute façon au bout de 3 min
    }
  }

  static Future<void> _startRadio() async {
    await _stopRadio();
    try {
      await _advertise();
      _refreshTimer = Timer.periodic(_tokenRefresh, (_) => _advertise());
      await _scan();
    } catch (e) {
      debugPrint('nearby: $e');
      if (_running) status.value = NearbyStatus.error;
    }
  }

  static Future<void> _stopRadio() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _resolveTimer?.cancel();
    _resolveTimer = null;
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    try {
      await _peripheral.stop();
    } catch (_) {}
  }

  /// Nouveau jeton serveur, diffusé comme identifiant de service BLE
  static Future<void> _advertise() async {
    final res = await SupabaseService.client!.functions
        .invoke('nearby', body: {'action': 'advertise'});
    final token = (res.data as Map)['token'] as String;
    if (!_running) return;
    try {
      await _peripheral.stop();
    } catch (_) {}
    await _peripheral.start(
      advertiseData: AdvertiseDataCore(serviceUuids: [token]),
    );
  }

  static Future<void> _scan() async {
    _scanSub = FlutterBluePlus.onScanResults.listen(_onResults);
    await FlutterBluePlus.startScan(
      continuousUpdates: true,
      removeIfGone: _goneAfter,
      androidScanMode: AndroidScanMode.lowLatency,
    );
  }

  static void _onResults(List<ScanResult> results) {
    final now = DateTime.now();
    for (final r in results) {
      for (final uuid in r.advertisementData.serviceUuids) {
        final token = uuid.str128.toLowerCase();
        if (token.startsWith(_tokenPrefix)) {
          _seen[token] = (at: now, rssi: r.rssi);
        }
      }
    }
    _seen.removeWhere((_, v) => now.difference(v.at) > _goneAfter);
    _publish();

    // Regroupe les nouveaux jetons en un seul appel serveur
    final unknown = _seen.keys
        .where((t) => !_resolved.containsKey(t) && !_resolving.contains(t));
    if (unknown.isNotEmpty) {
      _resolveTimer ??= Timer(const Duration(milliseconds: 300), _resolve);
    }
  }

  static Future<void> _resolve() async {
    _resolveTimer = null;
    final tokens = _seen.keys
        .where((t) => !_resolved.containsKey(t) && !_resolving.contains(t))
        .take(20)
        .toList();
    if (tokens.isEmpty) return;
    _resolving.addAll(tokens);
    try {
      final res = await SupabaseService.client!.functions.invoke('nearby',
          body: {'action': 'resolve', 'tokens': tokens});
      final list = ((res.data as Map)['people'] as List).cast<Map>();
      for (final t in tokens) {
        _resolved[t] = [];
      }
      for (final p in list) {
        final token = p['token'] as String;
        final isShop = p['kind'] == 'shop';
        _resolved[token]?.add((
          token: token,
          pseudo: p['pseudo'] as String,
          name: (isShop ? p['business_name'] : p['prenoms']) as String?,
          avatarUrl: p['avatar_url'] as String?,
          rssi: _seen[token]?.rssi ?? -100,
          isShop: isShop,
          category: p['category'] as String?,
        ));
      }
    } catch (e) {
      // Hors ligne : on réessaiera à la prochaine détection
      debugPrint('nearby resolve: $e');
    } finally {
      _resolving.removeAll(tokens);
    }
    if (_running) _publish();
  }

  /// Personnes visibles, la plus proche (signal le plus fort) en premier ;
  /// une même personne (jeton renouvelé) n'apparaît qu'une fois
  static void _publish() {
    final byPseudo = <String, NearbyPerson>{};
    for (final e in _seen.entries) {
      for (final p in _resolved[e.key] ?? const <NearbyPerson>[]) {
        final key = '${p.isShop}:${p.pseudo}';
        final current = byPseudo[key];
        if (current == null || e.value.rssi > current.rssi) {
          byPseudo[key] = (
            token: p.token,
            pseudo: p.pseudo,
            name: p.name,
            avatarUrl: p.avatarUrl,
            rssi: e.value.rssi,
            isShop: p.isShop,
            category: p.category,
          );
        }
      }
    }
    final list = byPseudo.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    if (!listEquals(
        list.map((p) => '${p.isShop}:${p.pseudo}').toList(),
        people.value.map((p) => '${p.isShop}:${p.pseudo}').toList())) {
      people.value = list;
    }
  }
}
