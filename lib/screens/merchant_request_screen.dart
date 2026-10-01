import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../l10n/app_strings.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import '../utils/toast_service.dart';

enum _Step { business, location, contact, review }

/// Demande pour devenir marchand : activité → localisation → contact
/// → récapitulatif. Renvoie true quand la demande est envoyée.
class MerchantRequestScreen extends StatefulWidget {
  const MerchantRequestScreen({super.key});

  @override
  State<MerchantRequestScreen> createState() => _MerchantRequestScreenState();
}

class _MerchantRequestScreenState extends State<MerchantRequestScreen> {
  static const _categories = ['shop', 'food', 'services', 'transport', 'other'];

  final _formKeys = {
    for (final step in _Step.values) step: GlobalKey<FormState>(),
  };
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _cityController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  _Step _step = _Step.business;
  String? _category;
  bool _isLoading = false;

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
    _nameController.dispose();
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
    if (_step == _Step.business) {
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

  Future<void> _submit() async {
    setState(() => _isLoading = true);
    try {
      await SupabaseService.submitMerchantRequest(
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
    int? maxLength,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        textCapitalization: capitalization,
        maxLines: maxLines,
        maxLength: maxLength,
        decoration: _decoration(context.tr(labelKey)),
        validator: validator,
      ),
    );
  }

  Widget _buildBusiness() {
    return Form(
      key: _formKeys[_Step.business],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(
            _nameController,
            'merchant_business_name',
            validator: _required,
            capitalization: TextCapitalization.words,
            maxLength: 80,
          ),
          FormField<String>(
            initialValue: _category,
            validator: (_) =>
                _category == null ? context.tr('merchant_required') : null,
            builder: (state) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('merchant_category'),
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final cat in _categories)
                      ChoiceChip(
                        label: Text(context.tr('merchant_cat_$cat')),
                        selected: _category == cat,
                        selectedColor: AppColors.secondary,
                        labelStyle: TextStyle(
                          color: _category == cat ? Colors.white : null,
                        ),
                        showCheckmark: false,
                        shape: const StadiumBorder(),
                        onSelected: (_) {
                          setState(() => _category = cat);
                          state.didChange(cat);
                        },
                      ),
                  ],
                ),
                if (state.hasError) ...[
                  const SizedBox(height: 8),
                  Text(
                    state.errorText!,
                    style:
                        const TextStyle(color: AppColors.error, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          _field(
            _descriptionController,
            'merchant_description',
            maxLines: 3,
            maxLength: 300,
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
            _reviewRow('merchant_business_name', _nameController.text.trim(),
                _Step.business),
            _reviewRow(
                'merchant_category',
                _category == null
                    ? null
                    : context.tr('merchant_cat_$_category'),
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
