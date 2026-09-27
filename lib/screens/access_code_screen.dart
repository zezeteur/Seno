import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import '../l10n/app_strings.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import '../utils/auth_errors.dart';
import '../utils/post_login.dart';
import '../utils/toast_service.dart';
import '../widgets/pin_pad.dart';
import 'otp_screen.dart';

/// Code d'accès à 5 chiffres :
/// - [AccessCodeScreen.verify] : compte existant, avant l'OTP
/// - [AccessCodeScreen.create] : nouveau compte, saisie puis confirmation
class AccessCodeScreen extends StatefulWidget {
  /// Numéro du compte (mode vérification uniquement)
  final String? phone;
  final String? displayPhone;

  const AccessCodeScreen.verify({
    super.key,
    required String this.phone,
    required String this.displayPhone,
  });

  const AccessCodeScreen.create({super.key})
      : phone = null,
        displayPhone = null;

  bool get isCreate => phone == null;

  @override
  State<AccessCodeScreen> createState() => _AccessCodeScreenState();
}

class _AccessCodeScreenState extends State<AccessCodeScreen> {
  static const int _codeLength = 5;

  /// Chiffres saisis via le clavier intégré
  String _code = '';

  bool _isLoading = false;
  bool _hasError = false;

  /// Création : premier code saisi, en attente de confirmation
  String? _firstCode;

  void _reset({bool error = false}) {
    setState(() {
      _isLoading = false;
      _hasError = error;
      _code = '';
    });
  }

  void _onDigit(String digit) {
    if (_isLoading || _code.length >= _codeLength) return;
    HapticFeedback.lightImpact();
    setState(() {
      _hasError = false;
      _code += digit;
    });
    if (_code.length == _codeLength) _onCompleted(_code);
  }

  void _onDelete() {
    if (_isLoading || _code.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _hasError = false;
      _code = _code.substring(0, _code.length - 1);
    });
  }

  void _onCompleted(String code) {
    if (_isLoading) return;
    if (widget.isCreate) {
      _handleCreate(code);
    } else {
      _verify(code);
    }
  }

  Future<void> _verify(String code) async {
    setState(() => _isLoading = true);
    try {
      final ticket =
          await SupabaseService.verifyAccessCode(widget.phone!, code);
      if (!mounted) return;
      // Code correct : le SMS est parti, étape suivante = OTP
      ToastService.showSuccess(context, context.tr('code_sent'));
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OtpScreen(
            phone: widget.phone!,
            displayPhone: widget.displayPhone!,
            ticket: ticket,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ToastService.showError(context, authErrorMessage(context, e));
      // Bloqué : retour à la saisie du numéro
      if (e is AuthOtpException && e.code == 'locked') {
        Navigator.of(context).pop();
        return;
      }
      _reset(error: true);
    }
  }

  Future<void> _handleCreate(String code) async {
    if (_firstCode == null) {
      setState(() {
        _firstCode = code;
        _hasError = false;
        _code = '';
      });
      return;
    }
    if (code != _firstCode) {
      ToastService.showError(context, context.tr('access_code_mismatch'));
      _firstCode = null;
      _reset(error: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await SupabaseService.setAccessCode(code);
      if (!mounted) return;
      ToastService.showSuccess(context, context.tr('access_code_created'));
      await navigateAfterLogin(context);
    } catch (e) {
      if (!mounted) return;
      ToastService.showError(context, context.tr('register_error'));
      _firstCode = null;
      _reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final confirming = _firstCode != null;

    final title = !widget.isCreate
        ? 'access_code_title'
        : confirming
            ? 'access_code_confirm_title'
            : 'access_code_create_title';
    final subtitle = !widget.isCreate
        ? 'access_code_subtitle'
        : confirming
            ? 'access_code_confirm_subtitle'
            : 'access_code_create_subtitle';

    // Création : la flèche retour ramène de la confirmation à la première saisie
    final VoidCallback? onBack = _isLoading
        ? null
        : widget.isCreate
            ? (confirming
                ? () {
                    _firstCode = null;
                    _reset();
                  }
                : null)
            : () => Navigator.of(context).pop();

    // Marges calculées depuis la barre d'état / barre système du téléphone
    final viewPadding = MediaQuery.of(context).viewPadding;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SizedBox.expand(
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                viewPadding.top + 88,
                24,
                viewPadding.bottom + 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.tr(title),
                    style: textTheme.headlineLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr(subtitle),
                    style: textTheme.bodyLarge
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 56),
                  PinDots(
                    length: _codeLength,
                    filled: _code.length,
                    hasError: _hasError,
                  ),
                  const SizedBox(height: 32),
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
                  const Spacer(),
                  PinKeypad(onDigit: _onDigit, onDelete: _onDelete),
                ],
              ),
            ),
            if (onBack != null)
              Positioned(
                top: viewPadding.top + 12,
                left: 8,
                child: IconButton(
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedArrowLeft01,
                    color: textTheme.bodyLarge?.color ?? Colors.black,
                  ),
                  onPressed: onBack,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
