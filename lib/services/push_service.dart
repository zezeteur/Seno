import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Notifications push (FCM) : enregistre le token de l'appareil dans
/// `push_tokens` pour les messages envoyés depuis le back-office.
class PushService {
  static bool _ready = false;
  static String? _token;

  /// À appeler après Supabase.initialize. Sans configuration Firebase
  /// (google-services.json / GoogleService-Info.plist), le push est ignoré.
  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
      _ready = true;
    } catch (e) {
      debugPrint('Push désactivé (Firebase non configuré) : $e');
      return;
    }

    final auth = Supabase.instance.client.auth;
    auth.onAuthStateChange.listen((data) {
      if (data.session != null &&
          (data.event == AuthChangeEvent.signedIn ||
              data.event == AuthChangeEvent.initialSession)) {
        _register();
      }
    });
    FirebaseMessaging.instance.onTokenRefresh.listen((t) => _save(t));
  }

  static Future<void> _register() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _save(token);
    } catch (e) {
      debugPrint('Enregistrement push impossible : $e');
    }
  }

  static Future<void> _save(String token) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    _token = token;
    await client.from('push_tokens').upsert({
      'token': token,
      'user_id': userId,
      'platform': Platform.isIOS ? 'ios' : 'android',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Avant la déconnexion (la RLS exige encore la session) :
  /// l'appareil ne reçoit plus les messages destinés à ce compte.
  static Future<void> unregister() async {
    if (!_ready) return;
    try {
      final token = _token ?? await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await Supabase.instance.client.from('push_tokens').delete().eq('token', token);
      }
    } catch (_) {
      // Hors ligne : le token sera remplacé à la prochaine connexion
    }
  }
}
