import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/foundation.dart';
import 'package:smart_auth/smart_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/app_strings.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import '../utils/auth_errors.dart';
import '../utils/toast_service.dart';
import '../utils/post_login.dart';
import 'register_screen.dart';

/// Page de validation du code OTP reçu par SMS
class OtpScreen extends StatefulWidget {
  /// Numéro complet envoyé à Supabase (ex : +2250700000000)
  final String phone;

  /// Numéro affiché à l'utilisateur (ex : +225 07 00 00 00 00)
  final String displayPhone;

  /// Compte existant : preuve que le code d'accès a été validé
  final String? ticket;

  const OtpScreen({
    super.key,
    required this.phone,
    required this.displayPhone,
    this.ticket,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  static const int _codeLength = 4;
  static const int _resendDelay = 30;

  final _codeController = TextEditingController();
  final _focusNode = FocusNode();

  bool _isLoading = false;
  bool _hasError = false;
  int _secondsLeft = _resendDelay;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() {}));
    _startTimer();
    _listenForSms();
  }

  @override
  void dispose() {
    if (_isAndroid) SmartAuth.instance.removeUserConsentApiListener();
    _timer?.cancel();
    _codeController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _secondsLeft = _resendDelay;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) timer.cancel();
      if (mounted) setState(() => _secondsLeft--);
    });
  }

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Android : détecte le SMS reçu (SMS User Consent API), remplit et valide.
  /// iOS : géré par le clavier via AutofillHints.oneTimeCode.
  Future<void> _listenForSms() async {
    if (!_isAndroid) return;
    await SmartAuth.instance.removeUserConsentApiListener();
    final res = await SmartAuth.instance.getSmsWithUserConsentApi(
      matcher: r'\b\d{4}\b',
    );
    final code = res.data?.code;
    if (!mounted || code == null || code.length != _codeLength) return;
    setState(() {
      _codeController.text = code;
      _hasError = false;
    });
    _verifyCode();
  }

  SupabaseClient? _getClient() {
    final supabase =
        SupabaseService.isInitialized ? SupabaseService.client : null;
    if (supabase == null) {
      ToastService.showError(context, context.tr('service_unavailable'));
    }
    return supabase;
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text;
    if (_isLoading || code.length != _codeLength) return;

    if (_getClient() == null) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final isNewUser = await SupabaseService.verifyOtp(widget.phone, code,
          ticket: widget.ticket);
      if (!mounted) return;
      if (isNewUser) {
        // Inscription : compléter le profil
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const RegisterScreen()),
          (_) => false,
        );
        return;
      }
      ToastService.showSuccess(context, context.tr('login_success'));
      await navigateAfterLogin(context);
    } catch (e) {
      if (!mounted) return;
      ToastService.showError(context, authErrorMessage(context, e));
      // Ticket du code d'accès expiré : retour à la connexion
      if (e is AuthOtpException && e.code == 'ticket_expired') {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
      _codeController.clear();
      _focusNode.requestFocus();
    }
  }

  Future<void> _resendCode() async {
    if (_getClient() == null) return;

    setState(() => _isLoading = true);
    try {
      final result =
          await SupabaseService.sendOtp(widget.phone, ticket: widget.ticket);
      if (!mounted) return;
      // Ticket expiré : repasser par le code d'accès
      if (result.requiresAccessCode) {
        ToastService.showError(context, context.tr('session_expired_retry'));
        Navigator.of(context).pop();
        return;
      }
      ToastService.showSuccess(context, context.tr('code_sent'));
      if (result.debugCode != null && kDebugMode) {
        ToastService.showInfo(context, 'Code (dev) : ${result.debugCode}');
      }
      _codeController.clear();
      _hasError = false;
      _startTimer();
      _listenForSms();
    } catch (e) {
      if (mounted) {
        ToastService.showError(context, authErrorMessage(context, e));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildCodeBoxes() {
    final code = _codeController.text;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return GestureDetector(
      onTap: () => _focusNode.requestFocus(),
      child: Stack(
        children: [
          // Champ invisible qui reçoit la saisie (et l'autoremplissage SMS)
          Opacity(
            opacity: 0,
            child: TextField(
              controller: _codeController,
              focusNode: _focusNode,
              autofocus: true,
              enabled: !_isLoading,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              showCursor: false,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(_codeLength),
              ],
              onChanged: (value) {
                setState(() => _hasError = false);
                if (value.length == _codeLength) _verifyCode();
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(_codeLength, (i) {
              final filled = i < code.length;
              final isCurrent = i == code.length && _focusNode.hasFocus;
              final borderColor = _hasError
                  ? AppColors.error
                  : isCurrent
                      ? AppColors.secondary
                      : filled
                          ? onSurface.withValues(alpha: 0.4)
                          : onSurface.withValues(alpha: 0.12);

              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: borderColor,
                    width: isCurrent || _hasError ? 2 : 1.5,
                  ),
                ),
                child: Text(
                  filled ? code[i] : '',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final canResend = _secondsLeft <= 0 && !_isLoading;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowLeft01,
                  color: textTheme.bodyLarge?.color ?? Colors.black,
                ),
                onPressed:
                    _isLoading ? null : () => Navigator.of(context).pop(),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      context.tr('verification'),
                      style: textTheme.headlineLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text.rich(
                      TextSpan(
                        style: textTheme.bodyLarge
                            ?.copyWith(color: AppColors.textSecondary),
                        children: [
                          TextSpan(text: context.tr('code_sent_to_prefix')),
                          TextSpan(
                            text: widget.displayPhone,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: textTheme.bodyLarge?.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 48),
                    _buildCodeBoxes(),
                    const SizedBox(height: 40),
                    // Validation automatique dès le 4e chiffre
                    SizedBox(
                      height: 24,
                      child: _isLoading
                          ? const Center(
                              child: SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.secondary,
                                ),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: canResend
                          ? TextButton(
                              onPressed: _resendCode,
                              style: TextButton.styleFrom(
                                overlayColor: Colors.transparent,
                              ),
                              child: Text(context.tr('resend_code')),
                            )
                          : Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                context.tr('resend_in', {
                                  'seconds': '$_secondsLeft',
                                }),
                                style: textTheme.bodyMedium
                                    ?.copyWith(color: AppColors.textSecondary),
                              ),
                            ),
                    ),
                    Center(
                      child: TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          overlayColor: Colors.transparent,
                        ),
                        child: Text(
                          context.tr('change_number'),
                          style:
                              const TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
