import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/app_strings.dart';
import '../models/merchant_category.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import '../utils/toast_service.dart';
import '../widgets/app_bottom_sheet.dart';
import '../widgets/photo_viewer.dart';

enum _LogoAction { view, camera, gallery, delete }

/// Page « Ma boutique » : logo, nom, pseudo et infos du compte marchand
class MerchantProfileScreen extends StatefulWidget {
  const MerchantProfileScreen({super.key});

  @override
  State<MerchantProfileScreen> createState() => _MerchantProfileScreenState();
}

class _MerchantProfileScreenState extends State<MerchantProfileScreen> {
  MerchantInfo? _merchant;
  // Préchargé pour ouvrir la modale du pseudo sans loader (null = pas encore connu)
  ({DateTime? value})? _nextPseudoChange;
  bool _uploadingLogo = false;
  // Valeur affichée pendant l'enregistrement (null = celle de la boutique)
  bool? _activePending;

  @override
  void initState() {
    super.initState();
    // Boutique en cache affichée tout de suite, puis version fraîche
    _merchant = SupabaseService.peekMyMerchant();
    _load();
    SupabaseService.merchantRevision.addListener(_load);
  }

  @override
  void dispose() {
    SupabaseService.merchantRevision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final merchant = await SupabaseService.getMyMerchant();
      if (mounted) setState(() => _merchant = merchant);
    } catch (_) {
      // Hors ligne : dernières infos affichées
    }
    try {
      final next = await SupabaseService.getNextShopPseudoChange();
      if (mounted) setState(() => _nextPseudoChange = (value: next));
    } catch (_) {
      // Hors ligne : dernières infos affichées
    }
  }

  bool get _hasLogo => _merchant?.logoUrl?.isNotEmpty ?? false;

  /// Ouvre une modale d'édition ; toast si elle a enregistré
  Future<void> _openEditor(String title, Widget editor) async {
    final saved = await showAppBottomSheet<bool>(
      context: context,
      title: title,
      builder: (_) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: editor,
      ),
    );
    if (saved == true && mounted) {
      ToastService.showSuccess(context, context.tr('profile_updated'));
    }
  }

  Future<void> _openLogoSheet() async {
    final action = await showAppBottomSheet<_LogoAction>(
      context: context,
      title: context.tr('merchant_logo_title'),
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_hasLogo)
            _buildMenuItem(
              icon: HugeIcons.strokeRoundedView,
              title: context.tr('view_photo'),
              onTap: () => Navigator.of(sheetContext).pop(_LogoAction.view),
            ),
          _buildMenuItem(
            icon: HugeIcons.strokeRoundedCamera01,
            title: context.tr('take_photo'),
            onTap: () => Navigator.of(sheetContext).pop(_LogoAction.camera),
          ),
          _buildMenuItem(
            icon: HugeIcons.strokeRoundedImage01,
            title: context.tr('import_photo'),
            onTap: () => Navigator.of(sheetContext).pop(_LogoAction.gallery),
          ),
          if (_hasLogo)
            _buildMenuItem(
              icon: HugeIcons.strokeRoundedDelete02,
              title: context.tr('merchant_logo_remove'),
              color: AppColors.error,
              onTap: () => Navigator.of(sheetContext).pop(_LogoAction.delete),
            ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _LogoAction.view:
        showPhotoViewer(context, _merchant!.logoUrl!, heroTag: 'merchant-logo');
      case _LogoAction.camera:
        await _pickLogo(ImageSource.camera);
      case _LogoAction.gallery:
        await _pickLogo(ImageSource.gallery);
      case _LogoAction.delete:
        await _deleteLogo();
    }
  }

  Future<void> _pickLogo(ImageSource source) async {
    final XFile? file;
    try {
      // Redimensionné et compressé : envoi léger
      file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
    } catch (_) {
      // Permission refusée ou caméra indisponible
      if (mounted) {
        ToastService.showError(context, context.tr('profile_update_error'));
      }
      return;
    }
    if (file == null || !mounted) return;
    final picked = file;
    await _runLogoUpdate(() async {
      final url =
          await SupabaseService.uploadMerchantLogo(await picked.readAsBytes());
      await SupabaseService.updateMerchant({'logo_url': url});
    });
  }

  Future<void> _deleteLogo() async {
    final confirmed = await showConfirmSheet(
      context: context,
      title: context.tr('merchant_logo_remove'),
      message: context.tr('merchant_logo_remove_confirm'),
      confirmLabel: context.tr('delete'),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _runLogoUpdate(SupabaseService.removeMerchantLogo);
  }

  Future<void> _runLogoUpdate(Future<void> Function() update) async {
    setState(() => _uploadingLogo = true);
    try {
      await update();
      if (mounted) {
        ToastService.showSuccess(context, context.tr('profile_updated'));
      }
    } catch (_) {
      if (mounted) {
        ToastService.showError(context, context.tr('profile_update_error'));
      }
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  /// Active ou désactive la boutique ; le switch revient en arrière si échec
  Future<void> _setActive(bool value) async {
    HapticFeedback.selectionClick();
    setState(() => _activePending = value);
    try {
      await SupabaseService.updateMerchant({'is_active': value});
      if (!mounted) return;
      ToastService.showSuccess(context,
          context.tr(value ? 'merchant_activated' : 'merchant_deactivated'));
    } catch (_) {
      if (mounted) {
        ToastService.showError(context, context.tr('profile_update_error'));
      }
    } finally {
      if (mounted) setState(() => _activePending = null);
    }
  }

  Widget _buildActiveSwitch(MerchantInfo m) {
    final active = _activePending ?? m.isActive;
    final accent = active ? AppColors.success : AppColors.textSecondary;
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: HugeIcon(
              icon: HugeIcons.strokeRoundedStore01,
              size: 20,
              color: accent,
            ),
          ),
        ),
        title: Text(
          context.tr('merchant_active'),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
        ),
        subtitle: Text(
          context.tr(active ? 'merchant_active_on' : 'merchant_active_off'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
        ),
        trailing: Transform.scale(
          scale: 0.8,
          alignment: Alignment.centerRight,
          child: Switch(
            value: active,
            activeTrackColor: AppColors.secondary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: _activePending != null ? null : _setActive,
          ),
        ),
        onTap: _activePending != null ? null : () => _setActive(!active),
      ),
    );
  }

  Widget _buildMenuItem({
    required dynamic icon,
    required String title,
    String? subtitle,
    Color? color,
    required VoidCallback onTap,
  }) {
    final accent = color ?? AppColors.secondary;
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: HugeIcon(icon: icon, size: 20, color: accent),
          ),
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: color ?? Theme.of(context).colorScheme.onSurface,
              ),
        ),
        subtitle: subtitle != null && subtitle.isNotEmpty
            ? Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
              )
            : null,
        trailing: Icon(Icons.chevron_right, color: AppColors.textSecondary),
        onTap: onTap,
      ),
    );
  }

  Widget _buildLogo(MerchantInfo m) {
    return GestureDetector(
      onTap: _uploadingLogo ? null : _openLogoSheet,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Hero(
            tag: 'merchant-logo',
            child: Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(28),
                image: _hasLogo
                    ? DecorationImage(
                        image: NetworkImage(m.logoUrl!), fit: BoxFit.cover)
                    : null,
              ),
              child: _hasLogo
                  ? null
                  : const Center(
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedStore01,
                        size: 44,
                        color: AppColors.secondary,
                      ),
                    ),
            ),
          ),
          if (_uploadingLogo)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),
          // Pas de logo : badge caméra en bas à droite
          if (!_hasLogo)
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 3,
                  ),
                ),
                child: const Center(
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedCamera01,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _section(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(children: children),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final textTheme = Theme.of(context).textTheme;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final divider = Divider(
        height: 1, color: AppColors.textSecondary.withValues(alpha: 0.2));
    final m = _merchant;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SizedBox(height: mediaQuery.viewPadding.top),
          // Header avec bouton retour
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: onSurface),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                Text(
                  context.tr('my_shop'),
                  style: textTheme.headlineSmall?.copyWith(
                    color: onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 28,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: m == null
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildLogo(m),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            m.businessName,
                            textAlign: TextAlign.center,
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: onSurface,
                            ),
                          ),
                        ),
                        if (m.pseudo != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '@${m.pseudo}',
                            style: textTheme.bodyMedium
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                        const SizedBox(height: 16),
                        _section([_buildActiveSwitch(m)]),
                        _section([
                          _buildMenuItem(
                            icon: HugeIcons.strokeRoundedStore01,
                            title: context.tr('merchant_business_name'),
                            subtitle: m.businessName,
                            onTap: () => _openEditor(
                              context.tr('merchant_business_name'),
                              _FieldsEditor(fields: [
                                _Field('business_name',
                                    'merchant_business_name', m.businessName,
                                    min: 2,
                                    max: 80,
                                    capitalization: TextCapitalization.words),
                              ]),
                            ),
                          ),
                          divider,
                          _buildMenuItem(
                            icon: HugeIcons.strokeRoundedAt,
                            title: context.tr('merchant_pseudo'),
                            subtitle: m.pseudo == null ? null : '@${m.pseudo}',
                            onTap: () => _openEditor(
                              context.tr('merchant_pseudo'),
                              _ShopPseudoEditor(
                                pseudo: m.pseudo,
                                nextChange: _nextPseudoChange,
                              ),
                            ),
                          ),
                          divider,
                          _buildMenuItem(
                            icon: MerchantCategory.byId(m.category).icon,
                            title: context.tr('merchant_category'),
                            subtitle: context
                                .tr(MerchantCategory.byId(m.category).labelKey),
                            onTap: () => _openEditor(
                              context.tr('merchant_category'),
                              _CategoryEditor(selected: m.category),
                            ),
                          ),
                          divider,
                          _buildMenuItem(
                            icon: HugeIcons.strokeRoundedNote,
                            title: context.tr('merchant_description'),
                            subtitle: m.description,
                            onTap: () => _openEditor(
                              context.tr('merchant_description'),
                              _FieldsEditor(fields: [
                                _Field('description', 'merchant_description',
                                    m.description,
                                    required: false, max: 300, maxLines: 3),
                              ]),
                            ),
                          ),
                        ]),
                        _section([
                          _buildMenuItem(
                            icon: HugeIcons.strokeRoundedLocation01,
                            title: context.tr('merchant_step_location'),
                            subtitle: '${m.address}, ${m.city}',
                            onTap: () => _openEditor(
                              context.tr('merchant_step_location'),
                              _FieldsEditor(fields: [
                                _Field('city', 'merchant_city', m.city,
                                    capitalization: TextCapitalization.words),
                                _Field(
                                    'address', 'merchant_address', m.address),
                              ]),
                            ),
                          ),
                          divider,
                          _buildMenuItem(
                            icon: HugeIcons.strokeRoundedCall,
                            title: context.tr('merchant_phone'),
                            subtitle: m.businessPhone,
                            onTap: () => _openEditor(
                              context.tr('merchant_phone'),
                              _FieldsEditor(fields: [
                                _Field('business_phone', 'merchant_phone',
                                    m.businessPhone,
                                    keyboardType: TextInputType.phone,
                                    capitalization: TextCapitalization.none),
                              ]),
                            ),
                          ),
                          divider,
                          _buildMenuItem(
                            icon: HugeIcons.strokeRoundedMail01,
                            title: context.tr('merchant_email'),
                            subtitle: m.email,
                            onTap: () => _openEditor(
                              context.tr('merchant_email'),
                              _FieldsEditor(fields: [
                                _Field('email', 'merchant_email', m.email,
                                    required: false,
                                    email: true,
                                    keyboardType: TextInputType.emailAddress,
                                    capitalization: TextCapitalization.none),
                              ]),
                            ),
                          ),
                        ]),
                        SizedBox(height: mediaQuery.viewPadding.bottom + 16),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _fieldDecoration(BuildContext context, String hint,
    {String? prefixText}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(24),
    borderSide: BorderSide(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15)),
  );
  return InputDecoration(
    hintText: hint,
    prefixText: prefixText,
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

Widget _saveButton(BuildContext context,
    {required bool loading, required VoidCallback? onPressed}) {
  return ElevatedButton(
    onPressed: loading ? null : onPressed,
    style: ElevatedButton.styleFrom(
      overlayColor: Colors.transparent,
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      elevation: 0,
      padding: const EdgeInsets.symmetric(vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
    ),
    child: loading
        ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          )
        : Text(
            context.tr('save'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
  );
}

/// Champ texte d'une modale d'édition (colonne de merchant_requests)
class _Field {
  final String column;
  final String labelKey;
  final String? initial;
  final bool required;
  final bool email;
  final int min;
  final int? max;
  final int maxLines;
  final TextInputType? keyboardType;
  final TextCapitalization capitalization;

  const _Field(
    this.column,
    this.labelKey,
    this.initial, {
    this.required = true,
    this.email = false,
    this.min = 0,
    this.max,
    this.maxLines = 1,
    this.keyboardType,
    this.capitalization = TextCapitalization.sentences,
  });
}

/// Modale générique : un ou plusieurs champs texte puis Enregistrer
class _FieldsEditor extends StatefulWidget {
  final List<_Field> fields;
  const _FieldsEditor({required this.fields});

  @override
  State<_FieldsEditor> createState() => _FieldsEditorState();
}

class _FieldsEditorState extends State<_FieldsEditor> {
  final _formKey = GlobalKey<FormState>();
  late final _controllers = [
    for (final f in widget.fields) TextEditingController(text: f.initial),
  ];
  bool _loading = false;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validate(_Field f, String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return f.required ? context.tr('merchant_required') : null;
    if (v.length < f.min) {
      return context.tr('merchant_too_short', {'min': '${f.min}'});
    }
    if (f.max != null && v.length > f.max!) {
      return context.tr('merchant_too_long', {'max': '${f.max}'});
    }
    if (f.email && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
      return context.tr('merchant_invalid_email');
    }
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      await SupabaseService.updateMerchant({
        for (var i = 0; i < widget.fields.length; i++)
          widget.fields[i].column: _controllers[i].text.trim().isEmpty
              ? null
              : _controllers[i].text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ToastService.showError(context, context.tr('profile_update_error'));
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < widget.fields.length; i++) ...[
            TextFormField(
              controller: _controllers[i],
              autofocus: i == 0,
              keyboardType: widget.fields[i].keyboardType,
              textCapitalization: widget.fields[i].capitalization,
              maxLines: widget.fields[i].maxLines,
              decoration: _fieldDecoration(
                  context, context.tr(widget.fields[i].labelKey)),
              validator: (v) => _validate(widget.fields[i], v),
            ),
            const SizedBox(height: 16),
          ],
          const SizedBox(height: 8),
          _saveButton(context, loading: _loading, onPressed: _save),
        ],
      ),
    );
  }
}

/// Catégorie : liste défilante, enregistrée dès le choix
class _CategoryEditor extends StatefulWidget {
  final String selected;
  const _CategoryEditor({required this.selected});

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  String? _saving;

  Future<void> _select(String id) async {
    if (_saving != null) return;
    if (id == widget.selected) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _saving = id);
    try {
      await SupabaseService.updateMerchant({'category': id});
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ToastService.showError(context, context.tr('profile_update_error'));
      setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final c in MerchantCategory.all)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: HugeIcon(icon: c.icon, size: 20, color: c.color),
                ),
              ),
              title: Text(context.tr(c.labelKey)),
              trailing: _saving == c.id
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : c.id == widget.selected
                      ? const Icon(Icons.check, color: AppColors.secondary)
                      : null,
              onTap: () => _select(c.id),
            ),
        ],
      ),
    );
  }
}

enum _PseudoStatus { idle, invalid, checking, available, taken }

/// Pseudo de la boutique : disponibilité vérifiée pendant la saisie
class _ShopPseudoEditor extends StatefulWidget {
  final String? pseudo;
  final ({DateTime? value})? nextChange;
  const _ShopPseudoEditor({this.pseudo, this.nextChange});

  @override
  State<_ShopPseudoEditor> createState() => _ShopPseudoEditorState();
}

class _ShopPseudoEditorState extends State<_ShopPseudoEditor> {
  static final _format = RegExp(r'^[a-z0-9]{3,20}$');
  late final _controller = TextEditingController(text: widget.pseudo);
  Timer? _debounce;
  _PseudoStatus _status = _PseudoStatus.idle;
  bool _loading = false;
  // _nextChange non null = changement bloqué jusqu'à cette date (7 jours)
  late bool _cooldownLoaded = widget.nextChange != null;
  late DateTime? _nextChange = widget.nextChange?.value;

  @override
  void initState() {
    super.initState();
    if (!_cooldownLoaded) _loadCooldown();
  }

  Future<void> _loadCooldown() async {
    DateTime? next;
    try {
      next = await SupabaseService.getNextShopPseudoChange();
    } catch (_) {
      // Inconnu : le serveur refusera si besoin
    }
    if (!mounted) return;
    setState(() {
      _nextChange = next;
      _cooldownLoaded = true;
    });
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    // Vide ou identique au pseudo actuel : rien à vérifier
    if (value.isEmpty || value == widget.pseudo) {
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

  Future<void> _save() async {
    if (_status != _PseudoStatus.available) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      await SupabaseService.updateMerchant({'pseudo': _controller.text});
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final taken = e.code == '23505';
      final cooldown = e.message.contains('pseudo_cooldown');
      setState(() {
        _loading = false;
        // Pseudo pris entre-temps par une autre boutique
        if (taken) _status = _PseudoStatus.taken;
        // Changé il y a moins de 7 jours : date exacte rechargée
        if (cooldown) {
          _nextChange = DateTime.now().add(SupabaseService.pseudoCooldown);
          _loadCooldown();
        }
      });
      if (!taken && !cooldown) {
        ToastService.showError(context, context.tr('profile_update_error'));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ToastService.showError(context, context.tr('profile_update_error'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final (String message, Color color) = switch (_status) {
      _PseudoStatus.available => (
          context.tr('pseudo_available'),
          AppColors.success
        ),
      _PseudoStatus.taken => (context.tr('pseudo_taken'), AppColors.error),
      _PseudoStatus.invalid => (context.tr('pseudo_rules'), AppColors.error),
      _ => (context.tr('pseudo_rules'), AppColors.textSecondary),
    };
    final Widget? icon = switch (_status) {
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

    if (!_cooldownLoaded) {
      return const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final next = _nextChange;
    if (next != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HugeIcon(
            icon: HugeIcons.strokeRoundedClock01,
            size: 48,
            color: AppColors.secondary,
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('pseudo_cooldown', {'date': _formatDate(next)}),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('pseudo_cooldown_rule'),
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            // Lettres et chiffres uniquement, en minuscules
            FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
            TextInputFormatter.withFunction(
                (_, v) => v.copyWith(text: v.text.toLowerCase())),
          ],
          onChanged: _onChanged,
          onSubmitted: (_) => _save(),
          decoration: _fieldDecoration(context, context.tr('pseudo_hint'),
                  prefixText: '@')
              .copyWith(suffixIcon: icon),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            message,
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
        const SizedBox(height: 24),
        _saveButton(
          context,
          loading: _loading,
          onPressed: _status == _PseudoStatus.available ? _save : null,
        ),
        const SizedBox(height: 12),
        Text(
          context.tr('pseudo_cooldown_rule'),
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
