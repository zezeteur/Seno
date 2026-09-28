import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/supabase_service.dart';

/// QR de paiement de l'utilisateur : dynamique (renouvelé avant expiration),
/// ou QR fixe en secours hors ligne.
class DynamicQrCode extends StatefulWidget {
  final double size;

  const DynamicQrCode({super.key, required this.size});

  @override
  State<DynamicQrCode> createState() => _DynamicQrCodeState();
}

class _DynamicQrCodeState extends State<DynamicQrCode>
    with WidgetsBindingObserver {
  // Dernier QR dynamique, partagé par tous les affichages (accueil, écran QR) :
  // réutilisé tant qu'il est valide → pas de changement à chaque ouverture
  static String? _lastPayload;
  static DateTime? _lastRefreshAt;

  // Renouvellement avant l'expiration serveur (90 s)
  static const _refreshMargin = Duration(seconds: 30);
  static const _retryDelay = Duration(seconds: 15);

  String? _payload;
  DateTime? _refreshAt;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final last = _lastPayload;
    final refreshAt = _lastRefreshAt;
    if (last != null &&
        refreshAt != null &&
        DateTime.now().isBefore(refreshAt)) {
      // QR dynamique encore valide : affiché tel quel, renouvelé à l'échéance
      _payload = last;
      _refreshAt = refreshAt;
      _startTicker();
      return;
    }
    // Sinon : QR fixe en cache immédiatement, remplacé par le dynamique
    _payload = SupabaseService.peekStaticQr();
    _load();
    // Premier lancement : met le QR fixe en cache pour les prochaines ouvertures
    if (_payload == null) SupabaseService.getStaticQr().ignore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour dans l'app : le QR a pu expirer entre-temps
    if (state == AppLifecycleState.resumed &&
        _refreshAt != null &&
        DateTime.now().isAfter(_refreshAt!)) {
      _load();
    }
  }

  Future<void> _load() async {
    _timer?.cancel();
    try {
      final qr = await SupabaseService.getDynamicQr();
      if (!mounted) return;
      _lastPayload = qr.payload;
      _lastRefreshAt = qr.expiresAt.subtract(_refreshMargin);
      setState(() {
        _payload = qr.payload;
        _refreshAt = _lastRefreshAt;
      });
    } catch (_) {
      // Pas de réseau : QR fixe (en cache), nouvel essai plus tard
      try {
        final fixed = await SupabaseService.getStaticQr();
        if (mounted) {
          setState(() {
            _payload = fixed;
            _refreshAt = DateTime.now().add(_retryDelay);
          });
        }
      } catch (_) {
        if (mounted)
          setState(() => _refreshAt = DateTime.now().add(_retryDelay));
      }
    }
    if (mounted) _startTicker();
  }

  /// Vérifie chaque seconde si le QR doit être renouvelé
  void _startTicker() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_refreshAt == null || DateTime.now().isBefore(_refreshAt!)) return;
      // Déjà renouvelé par un autre affichage : on reprend le même QR
      final shared = _lastRefreshAt;
      if (shared != null && DateTime.now().isBefore(shared)) {
        setState(() {
          _payload = _lastPayload;
          _refreshAt = shared;
        });
      } else {
        _load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final payload = _payload;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      // Aucun QR encore disponible : zone blanche, sans indicateur de chargement
      child: payload == null
          ? const ColoredBox(color: Colors.white)
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: QrImageView(
                key: ValueKey(payload),
                data: payload,
                version: QrVersions.auto,
                size: widget.size,
                padding: EdgeInsets.zero,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.circle,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.circle,
                  color: Colors.black,
                ),
              ),
            ),
    );
  }
}
