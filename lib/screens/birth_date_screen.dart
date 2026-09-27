import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/app_strings.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import '../utils/post_login.dart';
import '../utils/toast_service.dart';

/// Inscription (étape 3) : date de naissance, puis création du profil
class BirthDateScreen extends StatefulWidget {
  final String nom;
  final String prenoms;
  final String pseudo;

  const BirthDateScreen({
    super.key,
    required this.nom,
    required this.prenoms,
    required this.pseudo,
  });

  @override
  State<BirthDateScreen> createState() => _BirthDateScreenState();
}

class _BirthDateScreenState extends State<BirthDateScreen> {
  // Âge minimum : 13 ans
  late final DateTime _maxDate = () {
    final now = DateTime.now();
    return DateTime(now.year - 13, now.month, now.day);
  }();
  late DateTime _dateNaissance = DateTime(DateTime.now().year - 25, 1, 1);
  bool _isLoading = false;

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _submit() async {
    setState(() => _isLoading = true);
    try {
      await SupabaseService.createProfile(
        nom: widget.nom,
        prenoms: widget.prenoms,
        pseudo: widget.pseudo,
        dateNaissance: _dateNaissance,
      );
      if (!mounted) return;
      ToastService.showSuccess(context, context.tr('register_success'));
      await navigateAfterLogin(context);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      // Pseudo pris entre-temps par quelqu'un d'autre : retour au choix du pseudo
      if (e.code == '23505') {
        ToastService.showError(context, context.tr('pseudo_taken'));
        Navigator.of(context).pop();
        return;
      }
      ToastService.showError(context, context.tr('register_error'));
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      ToastService.showError(context, context.tr('register_error'));
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
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
            Padding(
              // Marge sous le bouton, au-dessus de la barre système
              padding: EdgeInsets.fromLTRB(
                24,
                72,
                24,
                MediaQuery.of(context).viewPadding.bottom + 32,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.tr('birth_date_title'),
                    style: textTheme.headlineLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('birth_date_subtitle'),
                    style: textTheme.bodyLarge
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 40),
                  Center(
                    child: Text(
                      _formatDate(_dateNaissance),
                      style: textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 216,
                    child: CupertinoTheme(
                      data: CupertinoThemeData(
                        brightness: Theme.of(context).brightness,
                      ),
                      child: CupertinoDatePicker(
                        mode: CupertinoDatePickerMode.date,
                        dateOrder: DatePickerDateOrder.dmy,
                        initialDateTime: _dateNaissance,
                        minimumDate: DateTime(1900),
                        maximumDate: _maxDate,
                        onDateTimeChanged: (d) =>
                            setState(() => _dateNaissance = d),
                      ),
                    ),
                  ),
                  const Spacer(),
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
          ],
        ),
      ),
    );
  }
}
