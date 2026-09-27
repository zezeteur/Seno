import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import '../utils/post_login.dart';
import '../utils/toast_service.dart';

/// Inscription : le nouvel utilisateur complète son profil
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomController = TextEditingController();
  final _prenomsController = TextEditingController();

  DateTime? _dateNaissance;
  bool _isLoading = false;

  @override
  void dispose() {
    _nomController.dispose();
    _prenomsController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateNaissance ?? DateTime(now.year - 25),
      firstDate: DateTime(1900),
      // Âge minimum : 13 ans
      lastDate: DateTime(now.year - 13, now.month, now.day),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (picked != null) setState(() => _dateNaissance = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dateNaissance == null) {
      ToastService.showError(context, context.tr('birth_date_required'));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await SupabaseService.createProfile(
        nom: _nomController.text.trim(),
        prenoms: _prenomsController.text.trim(),
        dateNaissance: _dateNaissance!,
      );
      if (!mounted) return;
      ToastService.showSuccess(context, context.tr('register_success'));
      await navigateAfterLogin(context);
    } catch (e) {
      if (!mounted) return;
      ToastService.showError(context, context.tr('register_error'));
      setState(() => _isLoading = false);
    }
  }

  InputDecoration _decoration(String label) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(50),
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

  String? _required(String? v) =>
      (v == null || v.trim().length < 2) ? context.tr('field_required') : null;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.tr('register_title'),
                  style: textTheme.headlineLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr('register_subtitle'),
                  style: textTheme.bodyLarge
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 40),
                TextFormField(
                  controller: _nomController,
                  enabled: !_isLoading,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.familyName],
                  decoration: _decoration(context.tr('last_name')),
                  validator: _required,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _prenomsController,
                  enabled: !_isLoading,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.givenName],
                  decoration: _decoration(context.tr('first_names')),
                  validator: _required,
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _isLoading ? null : _pickDate,
                  child: InputDecorator(
                    isEmpty: _dateNaissance == null,
                    decoration: _decoration(context.tr('birth_date')).copyWith(
                      suffixIcon: Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: Icon(Icons.calendar_today_outlined,
                            size: 20, color: onSurface.withValues(alpha: 0.5)),
                      ),
                    ),
                    child: Text(
                      _dateNaissance == null
                          ? ''
                          : _formatDate(_dateNaissance!),
                      style: textTheme.bodyLarge,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
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
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          context.tr('create_account'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
