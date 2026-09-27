import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/lock_screen.dart';
import '../screens/login_screen.dart';
import '../services/supabase_service.dart';

/// Verrouille l'app (code d'accès) à l'ouverture et dès qu'elle passe
/// en arrière-plan, si un utilisateur avec code d'accès est connecté.
/// Se place dans `MaterialApp.builder` pour recouvrir toutes les pages.
class AppLockGate extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  const AppLockGate({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  /// L'utilisateur connecté a-t-il un code d'accès ? (null = inconnu)
  static final hasAccessCode = ValueNotifier<bool?>(null);

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _locked = false;
  StreamSubscription<AuthState>? _authSub;

  Session? get _session => SupabaseService.isInitialized
      ? SupabaseService.client!.auth.currentSession
      : null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Ouverture de l'app avec une session : verrouillé immédiatement
    if (_session != null) {
      _locked = true;
      _refreshHasCode();
    }

    if (SupabaseService.isInitialized) {
      _authSub = SupabaseService.client!.auth.onAuthStateChange.listen((data) {
        if (data.event == AuthChangeEvent.signedOut) {
          AppLockGate.hasAccessCode.value = null;
          if (mounted) setState(() => _locked = false);
        } else if (data.event == AuthChangeEvent.signedIn) {
          _refreshHasCode();
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    super.dispose();
  }

  /// Sans code d'accès (inscription en cours), rien à verrouiller
  Future<void> _refreshHasCode() async {
    try {
      final has = await SupabaseService.hasAccessCode();
      AppLockGate.hasAccessCode.value = has;
      if (!has && mounted && _locked) setState(() => _locked = false);
    } catch (_) {
      // Réseau indisponible : on reste verrouillé par sécurité
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final leaving =
        state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
    if (leaving &&
        !_locked &&
        _session != null &&
        AppLockGate.hasAccessCode.value != false) {
      setState(() => _locked = true);
    }
  }

  Future<void> _onSignedOut() async {
    setState(() => _locked = false);
    widget.navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Contenu masqué et inactif tant que verrouillé
        Offstage(
            offstage: _locked,
            child: TickerMode(enabled: !_locked, child: widget.child)),
        if (_locked)
          // Navigateur propre : toasts et page Support s'ouvrent au-dessus du verrou
          Navigator(
            onGenerateRoute: (_) => MaterialPageRoute(
              builder: (_) => LockScreen(
                onUnlocked: () => setState(() => _locked = false),
                onSignedOut: _onSignedOut,
              ),
            ),
          ),
      ],
    );
  }
}
