import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:local_auth/local_auth.dart';
import '../l10n/app_strings.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/auth_errors.dart';
import '../utils/toast_service.dart';
import '../widgets/app_bottom_sheet.dart';
import '../widgets/contact_support_sheet.dart';
import '../widgets/pin_pad.dart';
import '../widgets/user_avatar.dart';
import 'help_support_screen.dart';
import 'reset_access_code_screen.dart';

/// Écran de verrouillage : code d'accès pour revenir dans l'app
class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  final Future<void> Function() onSignedOut;

  const LockScreen({
    super.key,
    required this.onUnlocked,
    required this.onSignedOut,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with WidgetsBindingObserver {
  static const int _codeLength = 5;

  String _code = '';
  bool _isLoading = false;
  bool _hasError = false;

  // Blocage progressif (15 min, 1 h, 24 h) puis définitif
  DateTime? _lockedUntil;
  bool _blocked = false;
  Timer? _ticker;

  // Déverrouillage biométrique : visage ou empreinte selon l'appareil
  final _localAuth = LocalAuthentication();
  bool _biometricAvailable = false;
  bool _hasFace = false;
  bool _hasFingerprint = false;
  bool _authenticating = false;
  bool _wasInBackground = false;

  String? _pseudo;
  String? _avatarUrl;

  bool get _isTempLocked =>
      _lockedUntil != null && _lockedUntil!.isAfter(DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // État de blocage d'abord : pas de demande biométrique pendant un blocage
    _loadLockStatus().then((_) => _initBiometrics());
    _loadProfile();
    SupabaseService.profileRevision.addListener(_loadProfile);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour dans l'app alors qu'elle est verrouillée : nouvelle demande biométrique
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _wasInBackground = true;
    } else if (state == AppLifecycleState.resumed && _wasInBackground) {
      _wasInBackground = false;
      _authenticateBiometric();
    }
  }

  Future<void> _initBiometrics() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final types = supported
          ? await _localAuth.getAvailableBiometrics()
          : const <BiometricType>[];
      if (!mounted || types.isEmpty) return;
      setState(() {
        _biometricAvailable = true;
        _hasFace = types.contains(BiometricType.face);
        // Android ne précise souvent que strong/weak : empreinte par défaut
        _hasFingerprint =
            types.contains(BiometricType.fingerprint) || !_hasFace;
      });
      _authenticateBiometric();
    } catch (_) {
      // Pas de biométrie : le code d'accès reste disponible
    }
  }

  Future<void> _authenticateBiometric() async {
    // Blocage serveur : la biométrie ne le contourne pas
    if (!_biometricAvailable ||
        _authenticating ||
        _isLoading ||
        _blocked ||
        _isTempLocked) {
      return;
    }
    _authenticating = true;
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: context.tr('biometric_reason'),
        biometricOnly: true,
      );
      if (ok && mounted) widget.onUnlocked();
    } catch (_) {
      // Annulé, trop d'essais ou capteur verrouillé : saisie du code
    } finally {
      _authenticating = false;
    }
  }

  /// Visage et/ou empreinte selon ce que l'appareil propose
  Widget _buildBiometricIcon() {
    final both = _hasFace && _hasFingerprint;
    final size = both ? 24.0 : 30.0;
    Widget icon(dynamic data) =>
        HugeIcon(icon: data, size: size, color: AppColors.textOnPrimary);
    if (!both) {
      return icon(_hasFace
          ? HugeIcons.strokeRoundedFaceId
          : HugeIcons.strokeRoundedFingerPrint);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon(HugeIcons.strokeRoundedFaceId),
        const SizedBox(width: 6),
        icon(HugeIcons.strokeRoundedFingerPrint),
      ],
    );
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await SupabaseService.getLockProfile();
      if (!mounted) return;
      setState(() {
        _pseudo = profile.pseudo;
        _avatarUrl = profile.avatarUrl;
      });
    } catch (_) {
      // Hors ligne : l'écran reste utilisable sans photo ni pseudo
    }
  }

  Widget _buildProfileHeader(TextTheme textTheme) {
    return Column(
      children: [
        UserAvatar(pseudo: _pseudo, avatarUrl: _avatarUrl),
        const SizedBox(height: 12),
        // Hauteur réservée : pas de saut de mise en page au chargement
        SizedBox(
          height: 28,
          child: _pseudo == null
              ? null
              : Text(
                  '@$_pseudo',
                  textAlign: TextAlign.center,
                  style: textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SupabaseService.profileRevision.removeListener(_loadProfile);
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _loadLockStatus() async {
    try {
      final status = await SupabaseService.getAccessLockStatus();
      if (!mounted) return;
      if (status.permanentlyLocked) {
        setState(() => _blocked = true);
      } else if (status.lockedUntil != null) {
        _startLock(status.lockedUntil!);
      }
    } catch (_) {
      // Hors ligne : le serveur refusera de toute façon pendant le blocage
    }
  }

  void _startLock(DateTime until) {
    _ticker?.cancel();
    setState(() {
      _lockedUntil = until;
      _code = '';
      _hasError = false;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!_isTempLocked) {
        _ticker?.cancel();
        setState(() => _lockedUntil = null);
      } else {
        setState(() {});
      }
    });
  }

  void _onDigit(String digit) {
    if (_isLoading || _isTempLocked || _blocked) return;
    if (_code.length >= _codeLength) return;
    HapticFeedback.lightImpact();
    setState(() {
      _hasError = false;
      _code += digit;
    });
    if (_code.length == _codeLength) _unlock(_code);
  }

  void _onDelete() {
    if (_isLoading || _code.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _hasError = false;
      _code = _code.substring(0, _code.length - 1);
    });
  }

  Future<void> _unlock(String code) async {
    setState(() => _isLoading = true);
    try {
      await SupabaseService.unlockApp(code);
      if (!mounted) return;
      widget.onUnlocked();
    } catch (e) {
      if (!mounted) return;
      if (e is AuthOtpException && e.code == 'locked') {
        _startLock(DateTime.now().add(Duration(seconds: e.retryIn ?? 900)));
        setState(() => _isLoading = false);
        return;
      }
      if (e is AuthOtpException && e.code == 'blocked') {
        setState(() {
          _isLoading = false;
          _blocked = true;
          _code = '';
        });
        return;
      }
      ToastService.showError(context, authErrorMessage(context, e));
      // Session invalide : déconnexion
      if (e is AuthOtpException && e.code == 'unauthorized') {
        await _signOut();
        return;
      }
      setState(() {
        _isLoading = false;
        _hasError = true;
        _code = '';
      });
    }
  }

  Future<void> _signOut() async {
    try {
      await SupabaseService.client?.auth.signOut();
    } catch (_) {
      // Session déjà invalide côté serveur : la déconnexion locale suffit
    }
    await widget.onSignedOut();
  }

  void _openSupport() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HelpSupportScreen(
          contactOnly: true,
          onSignOut: _signOut,
        ),
      ),
    );
  }

  Future<void> _forgotPassword() async {
    Widget option({
      required BuildContext sheetContext,
      required dynamic icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
    }) {
      final colorScheme = Theme.of(sheetContext).colorScheme;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            leading: HugeIcon(icon: icon, color: colorScheme.onSurface),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(sheetContext).pop();
              onTap();
            },
          ),
        ),
      );
    }

    await showAppBottomSheet<void>(
      context: context,
      title: context.tr('forgot_password'),
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          option(
            sheetContext: sheetContext,
            icon: HugeIcons.strokeRoundedSquareLock02,
            title: context.tr('reset_code_option'),
            subtitle: context.tr('reset_code_option_sub'),
            onTap: _resetAccessCode,
          ),
          option(
            sheetContext: sheetContext,
            icon: HugeIcons.strokeRoundedCustomerSupport,
            title: context.tr('contact_us'),
            subtitle: context.tr('contact_us_option_sub'),
            onTap: () => showContactSupportSheet(context),
          ),
        ],
      ),
    );
  }

  /// Date de naissance + SMS → nouveau code ; l'identité étant prouvée, on déverrouille
  Future<void> _resetAccessCode() async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ResetAccessCodeScreen()),
    );
    if (done == true && mounted) widget.onUnlocked();
  }

  Widget _buildLockedState(TextTheme textTheme, Color secondaryText) {
    final remaining = _isTempLocked
        ? _lockedUntil!.difference(DateTime.now())
        : Duration.zero;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        const Center(
          child: HugeIcon(
            icon: HugeIcons.strokeRoundedSquareLock02,
            size: 56,
            color: AppColors.textOnPrimary,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          context.tr(_blocked ? 'lock_blocked_title' : 'lock_temp_title'),
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (_blocked)
          Text(
            context.tr('access_code_blocked'),
            textAlign: TextAlign.center,
            style: textTheme.bodyLarge?.copyWith(color: secondaryText),
          )
        else ...[
          Text(
            context.tr('lock_temp_message'),
            textAlign: TextAlign.center,
            style: textTheme.bodyLarge?.copyWith(color: secondaryText),
          ),
          const SizedBox(height: 16),
          Text(
            formatLockDuration(remaining + const Duration(seconds: 1)),
            textAlign: TextAlign.center,
            style: textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
        const Spacer(),
        if (_blocked) ...[
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.textOnPrimary,
              foregroundColor: AppColors.primary,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: _openSupport,
            child: Text(context.tr('contact_us')),
          ),
          // Espace sous le bouton : il ne colle pas au bas de l'écran
          const SizedBox(height: 32),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Fond jaune (couleur principale) : thème clair forcé pour garder
    // un texte foncé lisible, même en mode sombre
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Theme(
        data: AppTheme.lightTheme,
        child: Builder(builder: _buildContent),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final viewPadding = MediaQuery.of(context).viewPadding;
    // Gris par défaut peu lisible sur le jaune
    final secondaryText = AppColors.textOnPrimary.withValues(alpha: 0.65);

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              viewPadding.top + 80,
              24,
              viewPadding.bottom + 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_blocked || _isTempLocked)
                  Expanded(child: _buildLockedState(textTheme, secondaryText))
                else ...[
                  _buildProfileHeader(textTheme),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('access_code_subtitle'),
                    textAlign: TextAlign.center,
                    style: textTheme.bodyLarge?.copyWith(color: secondaryText),
                  ),
                  const SizedBox(height: 40),
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
                                color: AppColors.textOnPrimary,
                              ),
                            ),
                          )
                        : null,
                  ),
                  const Spacer(),
                  PinKeypad(
                    onDigit: _onDigit,
                    onDelete: _onDelete,
                    onLeading: _authenticateBiometric,
                    leading: _biometricAvailable ? _buildBiometricIcon() : null,
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: _isLoading ? null : _forgotPassword,
                      style: TextButton.styleFrom(
                          overlayColor: Colors.transparent),
                      child: Text(
                        context.tr('forgot_password'),
                        style: TextStyle(color: secondaryText),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Barre du haut : logo à gauche, support à droite
          Positioned(
            top: viewPadding.top + 12,
            left: 24,
            right: 8,
            child: Row(
              children: [
                Image.asset(
                  'assets/images/seno-logo.png',
                  height: 36,
                  fit: BoxFit.contain,
                ),
                const Spacer(),
                IconButton(
                  style: IconButton.styleFrom(
                    overlayColor: Colors.transparent,
                  ),
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedCustomerSupport,
                    color: textTheme.bodyLarge?.color ?? Colors.black,
                  ),
                  onPressed: _openSupport,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
