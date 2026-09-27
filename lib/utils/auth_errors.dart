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
