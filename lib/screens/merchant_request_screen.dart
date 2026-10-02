import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hugeicons/hugeicons.dart';
import '../l10n/app_strings.dart';
import '../models/merchant_category.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import '../utils/toast_service.dart';

enum _PseudoStatus { idle, checking, available, taken, invalid }

enum _Step { category, business, location, contact, review }

/// Demande pour devenir marchand : catégorie → activité → localisation → contact
/// → récapitulatif. Renvoie true quand la demande est envoyée.
class MerchantRequestScreen extends StatefulWidget {
  const MerchantRequestScreen({super.key});

  @override
  State<MerchantRequestScreen> createState() => _MerchantRequestScreenState();
}

class _MerchantRequestScreenState extends State<MerchantRequestScreen> {
  final _formKeys = {
    for (final step in _Step.values) step: GlobalKey<FormState>(),
  };
  static final _pseudoFormat = RegExp(r'^[a-z0-9]{3,20}$');

  final _nameController = TextEditingController();
  final _pseudoController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _cityController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  _Step _step = _Step.category;
  String? _category;
  bool _isLoading = false;

  /// Pseudo de la boutique : unique (boutiques et utilisateurs)
  _PseudoStatus _pseudoStatus = _PseudoStatus.idle;
  Timer? _pseudoDebounce;

  /// Logo du commerce (facultatif), envoyé avec la demande
  Uint8List? _logo;

  @override
  void initState() {
    super.initState();
    // Numéro du compte proposé par défaut
    final phone = SupabaseService.client?.auth.currentUser?.phone ?? '';
    if (phone.isNotEmpty) {
      _phoneController.text = phone.startsWith('+') ? phone : '+$phone';
    }
  }

  @override
  void dispose() {
    _pseudoDebounce?.cancel();
    _nameController.dispose();
    _pseudoController.dispose();
    _descriptionController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  String? _required(String? value) => (value == null || value.trim().isEmpty)
      ? context.tr('merchant_required')
      : null;

  void _onPseudoChanged(String value) {
    _pseudoDebounce?.cancel();
    final status = value.isEmpty
        ? _PseudoStatus.idle
        : _pseudoFormat.hasMatch(value)
            ? _PseudoStatus.checking
            : _PseudoStatus.invalid;
    setState(() => _pseudoStatus = status);
    if (status == _PseudoStatus.checking) {
      _pseudoDebounce =
          Timer(const Duration(milliseconds: 400), () => _checkPseudo(value));
    }
  }

  Future<void> _checkPseudo(String value) async {
    try {
      final available = await SupabaseService.isPseudoAvailable(value);
      // Ignore une réponse obsolète si l'utilisateur a continué à taper
      if (!mounted || _pseudoController.text != value) return;
      setState(() => _pseudoStatus =
          available ? _PseudoStatus.available : _PseudoStatus.taken);
    } catch (_) {
      if (mounted && _pseudoController.text == value) {
        setState(() => _pseudoStatus = _PseudoStatus.idle);
      }
    }
  }

  String? _validatePseudo(String? value) {
    if (value == null || value.isEmpty) return context.tr('merchant_required');
    return switch (_pseudoStatus) {
      _PseudoStatus.available => null,
      _PseudoStatus.taken => context.tr('pseudo_taken'),
      _PseudoStatus.checking => context.tr('merchant_pseudo_checking'),
      _ => context.tr('pseudo_rules'),
    };
  }

  Widget _buildPseudoField() {
    final (message, color) = switch (_pseudoStatus) {
      _PseudoStatus.available => (
          context.tr('pseudo_available'),
          AppColors.success
        ),
      _PseudoStatus.taken => (context.tr('pseudo_taken'), AppColors.error),
      _PseudoStatus.invalid => (context.tr('pseudo_rules'), AppColors.error),
      _ => (context.tr('pseudo_rules'), AppColors.textSecondary),
    };
    final Widget? icon = switch (_pseudoStatus) {
      _PseudoStatus.checking => const Padding(
          padding: EdgeInsets.all(16),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      _PseudoStatus.available => const Padding(
          padding: EdgeInsets.only(right: 16),
          child: Icon(Icons.check_circle, color: AppColors.success),
        ),
      _PseudoStatus.taken || _PseudoStatus.invalid => const Padding(
          padding: EdgeInsets.only(right: 16),
          child: Icon(Icons.cancel, color: AppColors.error),
        ),
      _PseudoStatus.idle => null,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _pseudoController,
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [
              // Lettres et chiffres uniquement, en minuscules
              FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
              TextInputFormatter.withFunction(
                  (_, v) => v.copyWith(text: v.text.toLowerCase())),
            ],
            onChanged: _onPseudoChanged,
            validator: _validatePseudo,
            decoration: _decoration(context.tr('merchant_pseudo')).copyWith(
              prefixText: '@',
              suffixIcon: icon,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  String? _maxLength(String? value, int max, {int min = 0}) {
    final length = value?.trim().length ?? 0;
    if (length < min) {
      return context.tr('merchant_too_short', {'min': '$min'});
    }
    if (length > max) {
      return context.tr('merchant_too_long', {'max': '$max'});
    }
    return null;
  }

  String? _optionalEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)
        ? null
        : context.tr('merchant_invalid_email');
  }

  String? _trimOrNull(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  void _onBack() {
    if (_isLoading) return;
    if (_step == _Step.category) {
      Navigator.of(context).pop(false);
    } else {
      setState(() => _step = _Step.values[_step.index - 1]);
    }
  }

  void _next() {
    FocusScope.of(context).unfocus();
    if (_step == _Step.review) {
      _submit();
      return;
    }
    if (!(_formKeys[_step]!.currentState?.validate() ?? false)) return;
    setState(() => _step = _Step.values[_step.index + 1]);
  }

  Future<void> _pickLogo() async {
    try {
      // Redimensionné et compressé : envoi léger
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _logo = bytes);
    } catch (_) {
      // Permission refusée
      if (mounted) {
        ToastService.showError(context, context.tr('merchant_logo_error'));
      }
    }
  }

  Future<void> _submit() async {
    setState(() => _isLoading = true);
    try {
      final logo = _logo;
      final logoUrl =
          logo == null ? null : await SupabaseService.uploadMerchantLogo(logo);
      await SupabaseService.submitMerchantRequest(
        pseudo: _pseudoController.text,
        logoUrl: logoUrl,
        businessName: _nameController.text.trim(),
        category: _category!,
        description: _trimOrNull(_descriptionController),
        city: _cityController.text.trim(),
        address: _addressController.text.trim(),
        businessPhone: _phoneController.text.trim(),
        email: _trimOrNull(_emailController),
      );
      if (!mounted) return;
      ToastService.showSuccess(context, context.tr('merchant_submitted'));
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      // Pseudo pris entre la vérification et l'envoi : retour à l'étape 2
      if (e.code == '23505') {
        setState(() {
          _isLoading = false;
          _pseudoStatus = _PseudoStatus.taken;
          _step = _Step.business;
        });
        ToastService.showError(context, context.tr('merchant_pseudo_taken'));
        return;
      }
      setState(() => _isLoading = false);
      ToastService.showError(context, context.tr('merchant_submit_error'));
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ToastService.showError(context, context.tr('merchant_submit_error'));
    }
  }

  InputDecoration _decoration(String label) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: BorderSide(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15),
      ),
    );
    return InputDecoration(
      hintText: label,
      filled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: AppColors.secondary, width: 2),
      ),
      errorBorder: border.copyWith(
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: border.copyWith(
        borderSide: const BorderSide(color: AppColors.error, width: 2),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String labelKey, {
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    TextCapitalization capitalization = TextCapitalization.sentences,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        textCapitalization: capitalization,
        maxLines: maxLines,
        decoration: _decoration(context.tr(labelKey)),
        validator: validator,
      ),
    );
  }

  Widget _buildCategory() {
    final theme = Theme.of(context);
    return Form(
      key: _formKeys[_Step.category],
      child: FormField<String>(
        validator: (_) =>
            _category == null ? context.tr('merchant_required') : null,
        builder: (state) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final c in MerchantCategory.all)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: theme.colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: _category == c.id
                          ? AppColors.secondary
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      setState(() => _category = c.id);
                      state.didChange(c.id);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: c.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: HugeIcon(
                                icon: c.icon,
                                size: 22,
                                color: c.color,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              context.tr(c.labelKey),
                              style: theme.textTheme.bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (_category == c.id)
                            const HugeIcon(
                              icon: HugeIcons.strokeRoundedCheckmarkCircle02,
                              size: 22,
                              color: AppColors.secondary,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (state.hasError)
              Text(
                state.errorText!,
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoPicker() {
    final logo = _logo;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        children: [
          GestureDetector(
            onTap: _pickLogo,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(24),
                    image: logo == null
                        ? null
                        : DecorationImage(
                            image: MemoryImage(logo), fit: BoxFit.cover),
                  ),
                  child: logo != null
                      ? null
                      : const Center(
                          child: HugeIcon(
                            icon: HugeIcons.strokeRoundedStore01,
                            size: 36,
                            color: AppColors.secondary,
                          ),
                        ),
                ),
                Positioned(
                  right: -6,
                  bottom: -6,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: AppColors.secondary,
                      shape: BoxShape.circle,
                    ),
                    child: HugeIcon(
                      icon: logo == null
                          ? HugeIcons.strokeRoundedAdd01
                          : HugeIcons.strokeRoundedEdit02,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (logo == null)
            Text(
              context.tr('merchant_logo'),
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            )
          else
            TextButton(
              onPressed: () => setState(() => _logo = null),
              child: Text(context.tr('merchant_logo_remove')),
            ),
        ],
      ),
    );
  }

  Widget _buildBusiness() {
    return Form(
      key: _formKeys[_Step.business],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLogoPicker(),
          _field(
            _nameController,
            'merchant_business_name',
            // Pas de maxLength : il bloque l'effacement sur certains claviers
            validator: (v) => _required(v) ?? _maxLength(v, 80, min: 2),
            capitalization: TextCapitalization.words,
          ),
          _buildPseudoField(),
          _field(
            _descriptionController,
            'merchant_description',
            validator: (v) => _maxLength(v, 300),
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildLocation() {
    return Form(
      key: _formKeys[_Step.location],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(
            _cityController,
            'merchant_city',
            validator: _required,
            capitalization: TextCapitalization.words,
          ),
          _field(_addressController, 'merchant_address', validator: _required),
        ],
      ),
    );
  }

  Widget _buildContact() {
    return Form(
      key: _formKeys[_Step.contact],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(
            _phoneController,
            'merchant_phone',
            validator: _required,
            keyboardType: TextInputType.phone,
            capitalization: TextCapitalization.none,
          ),
          _field(
            _emailController,
            'merchant_email',
            validator: _optionalEmail,
            keyboardType: TextInputType.emailAddress,
            capitalization: TextCapitalization.none,
          ),
        ],
      ),
    );
  }

  Widget _reviewRow(String labelKey, String? value, _Step editStep) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      title: Text(
        context.tr(labelKey),
        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),
      subtitle: Text(
        value == null || value.isEmpty ? '—' : value,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      trailing: HugeIcon(
        icon: HugeIcons.strokeRoundedEdit02,
        size: 18,
        color: AppColors.textSecondary,
      ),
      onTap: () => setState(() => _step = editStep),
    );
  }

  Widget _buildReview() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            _reviewRow(
                'merchant_category',
                _category == null
                    ? null
                    : context.tr(MerchantCategory.byId(_category).labelKey),
                _Step.category),
            _reviewRow('merchant_business_name', _nameController.text.trim(),
                _Step.business),
            _reviewRow('merchant_pseudo', '@${_pseudoController.text}',
                _Step.business),
            _reviewRow('merchant_description',
                _descriptionController.text.trim(), _Step.business),
            _reviewRow(
                'merchant_city', _cityController.text.trim(), _Step.location),
            _reviewRow('merchant_address', _addressController.text.trim(),
                _Step.location),
            _reviewRow(
                'merchant_phone', _phoneController.text.trim(), _Step.contact),
            _reviewRow(
                'merchant_email', _emailController.text.trim(), _Step.contact),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final viewPadding = MediaQuery.of(context).viewPadding;
    final total = _Step.values.length;
    final isLast = _step == _Step.review;

    final (title, subtitle, content) = switch (_step) {
      _Step.category => (
          'merchant_step_category',
          'merchant_step_category_sub',
          _buildCategory(),
        ),
      _Step.business => (
          'merchant_step_business',
          'merchant_step_business_sub',
          _buildBusiness(),
        ),
      _Step.location => (
          'merchant_step_location',
          'merchant_step_location_sub',
          _buildLocation(),
        ),
      _Step.contact => (
          'merchant_step_contact',
          'merchant_step_contact_sub',
          _buildContact(),
        ),
      _Step.review => (
          'merchant_step_review',
          'merchant_step_review_sub',
          _buildReview(),
        ),
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Padding(
          padding: EdgeInsets.only(top: viewPadding.top + 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Retour + progression
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedArrowLeft01,
                        color: textTheme.bodyLarge?.color ?? Colors.black,
                      ),
                      onPressed: _isLoading ? null : _onBack,
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: (_step.index + 1) / total),
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                          builder: (_, value, __) => LinearProgressIndicator(
                            value: value,
                            minHeight: 6,
                            color: AppColors.secondary,
                            backgroundColor:
                                AppColors.textSecondary.withValues(alpha: 0.2),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Column(
                      key: ValueKey(_step),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          context.tr('merchant_step_count', {
                            'current': '${_step.index + 1}',
                            'total': '$total',
                          }),
                          style: textTheme.bodyMedium
                              ?.copyWith(color: AppColors.secondary),
                        ),
                        const SizedBox(height: 8),
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
                        const SizedBox(height: 32),
                        content,
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding:
                    EdgeInsets.fromLTRB(24, 8, 24, viewPadding.bottom + 24),
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _next,
                  style: ElevatedButton.styleFrom(
                    overlayColor: Colors.transparent,
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.black54,
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
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          context.tr(isLast ? 'merchant_submit' : 'next'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
