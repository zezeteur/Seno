import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../utils/toast_service.dart';
import '../utils/auth_errors.dart';
import '../services/supabase_service.dart';
import 'otp_screen.dart';
import 'help_support_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Positions fixes (fractions de l'écran) pour un rendu stable
  static const List<_DecoIcon> _decoIcons = [
    _DecoIcon(Icons.account_balance_wallet, 0.08, 0.58, 38, 0.12, -15),
    _DecoIcon(Icons.credit_card, 0.72, 0.55, 30, 0.10, 20),
    _DecoIcon(Icons.savings, 0.40, 0.64, 44, 0.08, 10),
    _DecoIcon(Icons.currency_exchange, 0.82, 0.68, 34, 0.12, -25),
    _DecoIcon(Icons.payment, 0.15, 0.74, 28, 0.10, 30),
    _DecoIcon(Icons.phone_android, 0.58, 0.76, 36, 0.12, -10),
    _DecoIcon(Icons.monetization_on, 0.30, 0.85, 32, 0.10, 15),
    _DecoIcon(Icons.receipt, 0.78, 0.86, 28, 0.08, -30),
    _DecoIcon(Icons.qr_code_2, 0.05, 0.90, 34, 0.10, 5),
    _DecoIcon(Icons.trending_up, 0.52, 0.92, 26, 0.12, -5),
  ];

  // Indicatif par défaut (Côte d'Ivoire)
  static const String _countryCode = '+225';
  static const String _countryIso = 'ci';

  final _phoneController = TextEditingController();

  bool _isLoading = false;

  String get _fullPhone =>
      '$_countryCode${_phoneController.text.replaceAll(' ', '')}';

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  SupabaseClient? _getClient() {
    if (!SupabaseService.isConfigured || !SupabaseService.isInitialized) {
      ToastService.showError(
        context,
        context.tr('service_unavailable_later'),
      );
      return null;
    }
    final supabase = SupabaseService.client;
    if (supabase == null) {
      ToastService.showError(context, context.tr('service_unavailable'));
    }
    return supabase;
  }

  Future<void> _sendCode() async {
    final digits = _phoneController.text.replaceAll(' ', '');
    if (digits.length != 10) {
      ToastService.showError(context, context.tr('invalid_phone'));
      return;
    }
    // Côte d'Ivoire : numéros Moov (01), MTN (05) et Orange (07)
    if (_countryCode == '+225' &&
        !const ['01', '05', '07'].contains(digits.substring(0, 2))) {
      ToastService.showError(context, context.tr('ci_phone_prefix'));
      return;
    }

    if (_getClient() == null) return;

    setState(() => _isLoading = true);
    try {
      final debugCode = await SupabaseService.sendOtp(_fullPhone);
      if (!mounted) return;
      ToastService.showSuccess(context, context.tr('code_sent'));
      // Mode développement : aucun fournisseur SMS configuré côté serveur
      if (debugCode != null && kDebugMode) {
        ToastService.showInfo(context, 'Code (dev) : $debugCode');
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpScreen(
            phone: _fullPhone,
            displayPhone: '$_countryCode ${_phoneController.text}',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ToastService.showError(context, authErrorMessage(context, e));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _inputDecoration(String hint, {Widget? prefix}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: prefix,
      filled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final legalLink = TextStyle(
      fontWeight: FontWeight.w600,
      color: textTheme.bodyLarge?.color,
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          SafeArea(
            child: Stack(
              children: [
                // Pattern en haut à droite
                Positioned(
                  top: 0,
                  right: 0,
                  child: Image.asset(
                    'assets/images/pattern.png',
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
                // Icônes de décoration en arrière-plan (moitié basse)
                ..._decoIcons.map((d) {
                  final size = MediaQuery.of(context).size;
                  return Positioned(
                    left: d.left * size.width,
                    top: d.top * size.height,
                    child: Transform.rotate(
                      angle: d.rotation * pi / 180,
                      child: Icon(
                        d.icon,
                        size: d.size,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: d.opacity),
                      ),
                    ),
                  );
                }),
                Align(
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          context.tr('login'),
                          style: textTheme.headlineLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.tr('enter_phone'),
                          style: textTheme.bodyLarge
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 48),
                        TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          autofocus: true,
                          enabled: !_isLoading,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                            _PairSpacingFormatter(),
                          ],
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w600),
                          decoration: _inputDecoration(
                            '07 00 00 00 00',
                            prefix: Padding(
                              padding:
                                  const EdgeInsets.only(left: 20, right: 8),
                              child: Align(
                                widthFactor: 1,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: Image.network(
                                        'https://flagcdn.com/w80/$_countryIso.png',
                                        width: 32,
                                        height: 22,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const SizedBox(width: 32),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Text(
                                      _countryCode,
                                      style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          onSubmitted: (_) => _sendCode(),
                        ),
                        const SizedBox(height: 40),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _sendCode,
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
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : Text(
                                  context.tr('get_code'),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const HelpSupportScreen(),
                            ),
                          ),
                          child: Text(
                            context.tr('cant_sign_in'),
                            style:
                                const TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Mention légale tout en bas
          Positioned(
            left: 24,
            right: 24,
            bottom: MediaQuery.of(context).viewPadding.bottom + 24,
            child: Text.rich(
              TextSpan(
                style: textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
                children: [
                  TextSpan(text: context.tr('terms_prefix')),
                  TextSpan(text: context.tr('terms'), style: legalLink),
                  TextSpan(text: context.tr('terms_and')),
                  TextSpan(text: context.tr('privacy'), style: legalLink),
                  const TextSpan(text: '.'),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _DecoIcon {
  final IconData icon;
  final double left;
  final double top;
  final double size;
  final double opacity;
  final double rotation;

  const _DecoIcon(
      this.icon, this.left, this.top, this.size, this.opacity, this.rotation);
}

/// Affiche le numéro par groupes de 2 chiffres : 07 00 00 00 00
class _PairSpacingFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(' ', '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i.isEven) buffer.write(' ');
      buffer.write(digits[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
