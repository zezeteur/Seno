import 'package:flutter/widgets.dart';
import '../l10n/app_strings.dart';
import '../services/supabase_service.dart';

/// Message lisible pour une erreur d'authentification par téléphone
String authErrorMessage(BuildContext context, Object e) {
  if (e is AuthOtpException) {
    switch (e.code) {
      case 'code_invalid':
        return context.tr('code_wrong');
      case 'code_expired':
        return context.tr('code_invalid');
      case 'too_many_attempts':
      case 'rate_limited':
        return context.tr('too_many_attempts');
      case 'access_code_invalid':
        return e.remaining == null
            ? context.tr('access_code_wrong')
            : context
                .tr('access_code_wrong_remaining', {'count': '${e.remaining}'});
      case 'locked':
        return context.tr('access_code_locked_for', {
          'duration': formatLockDuration(Duration(seconds: e.retryIn ?? 900)),
        });
      case 'birth_date_invalid':
        return context.tr('birth_date_wrong', {'count': '${e.remaining ?? 0}'});
      case 'qr_invalid':
        return context.tr('qr_invalid');
      case 'qr_expired':
        return context.tr('qr_expired');
      case 'compte_exists':
        return context.tr('compte_exists');
      case 'blocked':
        return context.tr('access_code_blocked');
      case 'unauthorized':
      case 'ticket_expired':
        return context.tr('session_expired_retry');
      case 'sms_failed':
        return context.tr('sms_failed');
      case 'invalid_phone':
        return context.tr('invalid_phone');
      case 'service_unavailable':
        return context.tr('service_unavailable');
    }
  }
  final msg = e.toString();
  if (msg.contains('network') || msg.contains('SocketException')) {
    return context.tr('network_problem');
  }
  return context.tr('login_error');
}

/// Durée de blocage lisible : « 23 h 59 min », « 14 min », « 42 s »
String formatLockDuration(Duration d) {
  if (d.inHours > 0) {
    final minutes = d.inMinutes.remainder(60);
    return minutes == 0 ? '${d.inHours} h' : '${d.inHours} h $minutes min';
  }
  if (d.inMinutes > 0) {
    final seconds = d.inSeconds.remainder(60);
    return seconds == 0
        ? '${d.inMinutes} min'
        : '${d.inMinutes} min ${seconds.toString().padLeft(2, '0')} s';
  }
  return '${d.inSeconds} s';
}
