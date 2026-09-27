import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import '../l10n/app_strings.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import 'birth_date_screen.dart';

enum _PseudoStatus { idle, invalid, checking, available, taken }

/// Inscription (étape 2) : choix d'un pseudo unique
class PseudoScreen extends StatefulWidget {
  final String nom;
  final String prenoms;

  const PseudoScreen({
    super.key,
    required this.nom,
    required this.prenoms,
  });

  @override
  State<PseudoScreen> createState() => _PseudoScreenState();
}

class _PseudoScreenState extends State<PseudoScreen> {
  static final _format = RegExp(r'^[a-z0-9]{3,20}$');

  final _controller = TextEditingController();
  Timer? _debounce;
  _PseudoStatus _status = _PseudoStatus.idle;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.isEmpty) {
      setState(() => _status = _PseudoStatus.idle);
      return;
    }
    if (!_format.hasMatch(value)) {
      setState(() => _status = _PseudoStatus.invalid);
      return;
    }
    setState(() => _status = _PseudoStatus.checking);
    _debounce = Timer(const Duration(milliseconds: 400), () => _check(value));
  }

  Future<void> _check(String value) async {
    try {
      final available = await SupabaseService.isPseudoAvailable(value);
      // Ignore une réponse obsolète si l'utilisateur a continué à taper
      if (!mounted || _controller.text != value) return;
      setState(() =>
          _status = available ? _PseudoStatus.available : _PseudoStatus.taken);
    } catch (_) {
      if (mounted && _controller.text == value) {
        setState(() => _status = _PseudoStatus.idle);
      }
    }
  }

  void _next() {
    if (_status != _PseudoStatus.available) return;
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BirthDateScreen(
          nom: widget.nom,
          prenoms: widget.prenoms,
          pseudo: _controller.text,
        ),
      ),
    );
  }

  Widget? _statusIcon() {
    switch (_status) {
      case _PseudoStatus.checking:
        return const Padding(
          padding: EdgeInsets.all(16),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case _PseudoStatus.available:
        return const Padding(
          padding: EdgeInsets.only(right: 16),
          child: Icon(Icons.check_circle, color: AppColors.success),
        );
      case _PseudoStatus.taken:
      case _PseudoStatus.invalid:
        return const Padding(
          padding: EdgeInsets.only(right: 16),
          child: Icon(Icons.cancel, color: AppColors.error),
        );
      case _PseudoStatus.idle:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final (String message, Color color) = switch (_status) {
      _PseudoStatus.available => (
          context.tr('pseudo_available'),
          AppColors.success
        ),
      _PseudoStatus.taken => (context.tr('pseudo_taken'), AppColors.error),
      _PseudoStatus.invalid => (context.tr('pseudo_rules'), AppColors.error),
      _ => (context.tr('pseudo_rules'), AppColors.textSecondary),
    };

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(50),
      borderSide: BorderSide(color: onSurface.withValues(alpha: 0.15)),
    );

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
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.tr('pseudo_title'),
                    style: textTheme.headlineLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('pseudo_subtitle'),
                    style: textTheme.bodyLarge
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 40),
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.newUsername],
                    inputFormatters: [
                      // Lettres et chiffres uniquement, en minuscules
                      FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
                      TextInputFormatter.withFunction(
                          (_, v) => v.copyWith(text: v.text.toLowerCase())),
                      LengthLimitingTextInputFormatter(20),
                    ],
                    onChanged: _onChanged,
                    onSubmitted: (_) => _next(),
                    decoration: InputDecoration(
                      hintText: context.tr('pseudo_hint'),
                      prefixText: '@',
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 18),
                      border: border,
                      enabledBorder: border,
                      focusedBorder: border.copyWith(
                        borderSide: const BorderSide(
                            color: AppColors.secondary, width: 2),
                      ),
                      suffixIcon: _statusIcon(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      message,
                      style: textTheme.bodySmall?.copyWith(color: color),
                    ),
                  ),
                  const SizedBox(height: 40),
                  ElevatedButton(
                    onPressed:
                        _status == _PseudoStatus.available ? _next : null,
                    style: ElevatedButton.styleFrom(
                      overlayColor: Colors.transparent,
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          onSurface.withValues(alpha: 0.12),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                    ),
                    child: Text(
                      context.tr('continue_btn'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
