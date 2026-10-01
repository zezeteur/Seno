import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import '../l10n/app_strings.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import '../utils/auth_errors.dart';
import '../utils/toast_service.dart';
import '../widgets/pin_pad.dart';

enum _Step { birthDate, currentCode, otp, newCode, confirmCode }

/// Changement du code d'accès : date de naissance → code actuel → code SMS
/// → nouveau code → confirmation. Renvoie true quand le code est enregistré.
class ChangeAccessCodeScreen extends StatefulWidget {
  const ChangeAccessCodeScreen({super.key});

  @override
  State<ChangeAccessCodeScreen> createState() => _ChangeAccessCodeScreenState();
}

class _ChangeAccessCodeScreenState extends State<ChangeAccessCodeScreen> {
  static const int _otpLength = 4;
  static const int _codeLength = 5;
  static const int _resendDelay = 30;

  _Step _step = _Step.birthDate;
  bool _isLoading = false;
  bool _hasError = false;

  late DateTime _birthDate = DateTime(DateTime.now().year - 25, 1, 1);
  late final DateTime _maxDate = () {
    final now = DateTime.now();
    return DateTime(now.year - 13, now.month, now.day);
  }();

  String? _token;
  String _phone = '';
  String _digits = '';
  String? _firstCode;
  String? _currentCode;

  int _secondsLeft = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _secondsLeft = _resendDelay);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) t.cancel();
    });
  }

  void _showError(Object e) {
    if (!mounted) return;
    ToastService.showError(context, authErrorMessage(context, e));
  }

  /// Erreurs qui rendent le changement impossible : on quitte l'écran
  bool _isFatal(Object e) =>
      e is AuthOtpException &&
      (e.code == 'locked' ||
          e.code == 'blocked' ||
          e.code == 'unauthorized' ||
          e.code == 'ticket_expired');

  /// Date de naissance vérifiée par le serveur avant de passer au code actuel
  Future<void> _submitBirthDate() async {
    setState(() => _isLoading = true);
    try {
      await SupabaseService.checkBirthDate(_birthDate);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _step = _Step.currentCode;
        _digits = '';
        _hasError = false;
      });
    } catch (e) {
      _showError(e);
      if (!mounted) return;
      if (_isFatal(e)) {
        Navigator.of(context).pop(false);
        return;
      }
      setState(() => _isLoading = false);
    }
  }

  /// Code actuel vérifié (même blocage que le déverrouillage),
  /// puis date de naissance vérifiée et envoi du SMS
  Future<void> _submitCurrentCode(String code) async {
    setState(() => _isLoading = true);
    try {
      await SupabaseService.unlockApp(code);
      final res = await SupabaseService.startAccessCodeReset(_birthDate);
      if (!mounted) return;
      _currentCode = code;
      _token = res.token;
      _phone = res.phone;
      setState(() {
        _isLoading = false;
        _step = _Step.otp;
        _digits = '';
      });
      _startResendTimer();
    } catch (e) {
      _showError(e);
      if (!mounted) return;
      if (_isFatal(e)) {
        Navigator.of(context).pop(false);
        return;
      }
      // Date de naissance refusée : on la redemande
      if (e is AuthOtpException && e.code == 'birth_date_invalid') {
        setState(() {
          _isLoading = false;
          _step = _Step.birthDate;
          _digits = '';
        });
        return;
      }
      _clear(error: true);
    }
  }

  Future<void> _resendOtp() async {
    if (_token == null) return;
    setState(() => _isLoading = true);
    try {
      await SupabaseService.resendAccessCodeResetOtp(_token!);
      if (!mounted) return;
      setState(() => _isLoading = false);
      _startResendTimer();
    } catch (e) {
      _showError(e);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onDigit(String digit) {
    final max = _step == _Step.otp ? _otpLength : _codeLength;
    if (_isLoading || _digits.length >= max) return;
    HapticFeedback.lightImpact();
    setState(() {
      _hasError = false;
      _digits += digit;
    });
    if (_digits.length == max) _onComplete(_digits);
  }

  void _onDelete() {
    if (_isLoading || _digits.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _hasError = false;
      _digits = _digits.substring(0, _digits.length - 1);
    });
  }

  void _clear({bool error = false}) {
    setState(() {
      _isLoading = false;
      _hasError = error;
      _digits = '';
    });
  }

  Future<void> _onComplete(String value) async {
    switch (_step) {
      case _Step.birthDate:
        return;
      case _Step.currentCode:
        await _submitCurrentCode(value);
      case _Step.otp:
        setState(() => _isLoading = true);
        try {
          await SupabaseService.verifyAccessCodeResetOtp(_token!, value);
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _step = _Step.newCode;
            _digits = '';
          });
        } catch (e) {
          _showError(e);
          if (!mounted) return;
          if (_isFatal(e)) {
            Navigator.of(context).pop(false);
            return;
          }
          _clear(error: true);
        }
      case _Step.newCode:
        if (value == _currentCode) {
          ToastService.showError(context, context.tr('change_code_same'));
          _clear(error: true);
          return;
        }
        setState(() {
          _firstCode = value;
          _step = _Step.confirmCode;
          _digits = '';
        });
      case _Step.confirmCode:
        if (value != _firstCode) {
          ToastService.showError(context, context.tr('reset_codes_mismatch'));
          setState(() {
            _step = _Step.newCode;
            _firstCode = null;
          });
          _clear(error: true);
          return;
        }
        setState(() => _isLoading = true);
        try {
          await SupabaseService.setNewAccessCode(_token!, value);
          if (!mounted) return;
          ToastService.showSuccess(context, context.tr('reset_code_success'));
          Navigator.of(context).pop(true);
        } catch (e) {
          _showError(e);
          if (!mounted) return;
          if (_isFatal(e)) {
            Navigator.of(context).pop(false);
            return;
          }
          _clear(error: true);
        }
    }
  }

  void _onBack() {
    if (_isLoading) return;
    // Code actuel → retour à la date ; confirmation → retour au choix du code
    if (_step == _Step.currentCode) {
      setState(() {
        _step = _Step.birthDate;
        _digits = '';
        _hasError = false;
      });
      return;
    }
    if (_step == _Step.confirmCode) {
      setState(() {
        _step = _Step.newCode;
        _firstCode = null;
        _digits = '';
        _hasError = false;
      });
      return;
    }
    Navigator.of(context).pop(false);
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final viewPadding = MediaQuery.of(context).viewPadding;

    final (title, subtitle) = switch (_step) {
      _Step.birthDate => (
          context.tr('reset_birth_title'),
          context.tr('reset_birth_subtitle'),
        ),
      _Step.currentCode => (
          context.tr('change_code_current_title'),
          context.tr('change_code_current_subtitle'),
        ),
      _Step.otp => (
          context.tr('reset_otp_title'),
          context.tr('reset_otp_subtitle', {'phone': _phone}),
        ),
      _Step.newCode => (
          context.tr('reset_new_code_title'),
          context.tr('reset_new_code_subtitle'),
        ),
      _Step.confirmCode => (
          context.tr('reset_confirm_code_title'),
          context.tr('reset_confirm_code_subtitle'),
        ),
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Stack(
          children: [
            Positioned(
              top: viewPadding.top + 8,
              left: 8,
              child: IconButton(
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowLeft01,
                  color: textTheme.bodyLarge?.color ?? Colors.black,
                ),
                onPressed: _isLoading ? null : _onBack,
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                viewPadding.top + 72,
                24,
                viewPadding.bottom + 32,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: textTheme.headlineLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: textTheme.bodyLarge
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 40),
                  Expanded(
                    child: _step == _Step.birthDate
                        ? _buildBirthDateStep(textTheme)
                        : _buildPinStep(textTheme),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBirthDateStep(TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(
            _formatDate(_birthDate),
            style:
                textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 216,
          child: CupertinoTheme(
            data: CupertinoThemeData(brightness: Theme.of(context).brightness),
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.date,
              dateOrder: DatePickerDateOrder.dmy,
              initialDateTime: _birthDate,
              minimumDate: DateTime(1900),
              maximumDate: _maxDate,
              onDateTimeChanged: (d) => setState(() => _birthDate = d),
            ),
          ),
        ),
        const Spacer(),
        ElevatedButton(
          onPressed: _isLoading ? null : _submitBirthDate,
          style: ElevatedButton.styleFrom(
            overlayColor: Colors.transparent,
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(50),
            ),
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  context.tr('continue'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildPinStep(TextTheme textTheme) {
    final isOtp = _step == _Step.otp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PinDots(
          length: isOtp ? _otpLength : _codeLength,
          filled: _digits.length,
          hasError: _hasError,
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 48,
          child: _isLoading
              ? const Center(
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : isOtp
                  ? Center(
                      child: TextButton(
                        onPressed: _secondsLeft > 0 ? null : _resendOtp,
                        child: Text(
                          _secondsLeft > 0
                              ? context
                                  .tr('resend_in', {'seconds': '$_secondsLeft'})
                              : context.tr('resend_code'),
                        ),
                      ),
                    )
                  : null,
        ),
        const Spacer(),
        PinKeypad(onDigit: _onDigit, onDelete: _onDelete),
      ],
    );
  }
}
