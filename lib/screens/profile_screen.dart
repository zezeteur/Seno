import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/app_strings.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import '../utils/toast_service.dart';
import '../widgets/app_bottom_sheet.dart';
import '../widgets/photo_viewer.dart';
import '../widgets/user_avatar.dart';
import 'login_screen.dart';

enum _AvatarAction { view, camera, gallery, delete }

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _pseudo;
  String? _nom;
  String? _prenoms;
  String? _avatarUrl;
  // Préchargés pour ouvrir les modales sans loader (null = pas encore connu)
  ({DateTime? value})? _nextPseudoChange;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    // Copie en cache affichée tout de suite : pas d'écran vide au premier rendu
    final cached = SupabaseService.peekLockProfile();
    if (cached != null) _applyProfile(cached);
    _loadProfile();
    _loadEditorData();
    SupabaseService.profileRevision.addListener(_onProfileChanged);
  }

  @override
  void dispose() {
    SupabaseService.profileRevision.removeListener(_onProfileChanged);
    super.dispose();
  }

  void _applyProfile(
      ({String? pseudo, String? nom, String? prenoms, String? avatarUrl}) p) {
    _pseudo = p.pseudo;
    _nom = p.nom;
    _prenoms = p.prenoms;
    _avatarUrl = p.avatarUrl;
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await SupabaseService.getLockProfile();
      if (!mounted) return;
      setState(() => _applyProfile(profile));
    } catch (_) {
      // Hors ligne sans cache : champs vides
    }
  }

  void _onProfileChanged() {
    _loadProfile();
    _loadEditorData();
  }

  /// Délai du pseudo, chargé en arrière-plan
  Future<void> _loadEditorData() async {
    await Future.wait([
      SupabaseService.getNextPseudoChange()
          .then((v) =>
              mounted ? setState(() => _nextPseudoChange = (value: v)) : null)
          .catchError((_) {}),
    ]);
  }

  String _fullName() {
    final name = [_nom, _prenoms]
        .map((v) => v?.trim() ?? '')
        .where((v) => v.isNotEmpty)
        .join(' ');
    return name.isNotEmpty ? name : context.tr('user');
  }

  /// Ouvre une modale d'édition ; recharge le profil si elle a enregistré
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

  bool get _hasAvatar => _avatarUrl?.isNotEmpty ?? false;

  /// Sheet : prendre une photo, en importer une ou supprimer l'actuelle
  Future<void> _openAvatarSheet() async {
    final action = await showAppBottomSheet<_AvatarAction>(
      context: context,
      title: context.tr('profile_photo'),
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_hasAvatar)
            _buildMenuItem(
              icon: HugeIcons.strokeRoundedView,
              title: context.tr('view_photo'),
              onTap: () => Navigator.of(sheetContext).pop(_AvatarAction.view),
            ),
          _buildMenuItem(
            icon: HugeIcons.strokeRoundedCamera01,
            title: context.tr('take_photo'),
            onTap: () => Navigator.of(sheetContext).pop(_AvatarAction.camera),
          ),
          _buildMenuItem(
            icon: HugeIcons.strokeRoundedImage01,
            title: context.tr('import_photo'),
            onTap: () => Navigator.of(sheetContext).pop(_AvatarAction.gallery),
          ),
          if (_hasAvatar)
            _buildMenuItem(
              icon: HugeIcons.strokeRoundedDelete02,
              title: context.tr('delete_photo'),
              color: AppColors.error,
              onTap: () => Navigator.of(sheetContext).pop(_AvatarAction.delete),
            ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _AvatarAction.view:
        showPhotoViewer(context, _avatarUrl!, heroTag: 'profile-photo');
      case _AvatarAction.camera:
        await _pickAvatar(ImageSource.camera);
      case _AvatarAction.gallery:
        await _pickAvatar(ImageSource.gallery);
      case _AvatarAction.delete:
        await _confirmDeleteAvatar();
    }
  }

  /// Sheet de confirmation avant suppression
  Future<void> _confirmDeleteAvatar() async {
    final confirmed = await showAppBottomSheet<bool>(
      context: context,
      title: context.tr('delete_photo'),
      message: context.tr('delete_photo_confirm'),
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton(
            onPressed: () => Navigator.of(sheetContext).pop(true),
            style: ElevatedButton.styleFrom(
              overlayColor: Colors.transparent,
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 20),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50)),
            ),
            child: Text(
              context.tr('delete'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(sheetContext).pop(false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(
              context.tr('cancel'),
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _uploadingAvatar = true);
    try {
      await SupabaseService.removeAvatar();
      if (mounted) {
        ToastService.showSuccess(context, context.tr('profile_updated'));
      }
    } catch (_) {
      if (mounted) {
        ToastService.showError(context, context.tr('profile_update_error'));
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _pickAvatar(ImageSource source) async {
    final XFile? file;
    try {
      // Redimensionnée et compressée : envoi léger
      file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.front,
      );
    } catch (_) {
      // Permission refusée ou caméra indisponible
      if (mounted) {
        ToastService.showError(context, context.tr('profile_update_error'));
      }
      return;
    }
    if (file == null || !mounted) return;
    setState(() => _uploadingAvatar = true);
    try {
      await SupabaseService.uploadAvatar(await file.readAsBytes());
      if (mounted) {
        ToastService.showSuccess(context, context.tr('profile_updated'));
      }
    } catch (_) {
      if (mounted) {
        ToastService.showError(context, context.tr('profile_update_error'));
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _handleSignOut() async {
    final confirm = await showConfirmSheet(
      context: context,
      title: context.tr('logout'),
      message: context.tr('logout_confirm'),
      confirmLabel: context.tr('logout'),
      destructive: true,
    );
    if (!confirm || !mounted) return;
    try {
      await SupabaseService.unsubscribeTransactions();
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
      ToastService.showSuccess(context, context.tr('logout_success'));
    } catch (_) {
      if (mounted) ToastService.showError(context, context.tr('logout_error'));
    }
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
        subtitle: subtitle != null
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

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final divider = Divider(
        height: 1, color: AppColors.textSecondary.withValues(alpha: 0.2));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SizedBox(height: mediaQuery.viewPadding.top),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Header avec bouton retour
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.arrow_back,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          context.tr('my_profile'),
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                                fontSize: 28,
                              ),
                        ),
                      ],
                    ),
                  ),
                  // Photo, nom et pseudo
                  GestureDetector(
                    onTap: _uploadingAvatar ? null : _openAvatarSheet,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Hero(
                          tag: 'profile-photo',
                          child: UserAvatar(
                            pseudo: _pseudo ?? _prenoms,
                            avatarUrl: _avatarUrl,
                            radius: 52,
                          ),
                        ),
                        if (_uploadingAvatar)
                          const Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        // Pas de photo : badge caméra en bas à droite
                        if (!_hasAvatar)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: AppColors.secondary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  width: 3,
                                ),
                              ),
                              child: Center(
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
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      _fullName(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                  ),
                  if (_pseudo?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 4),
                    Text(
                      '@$_pseudo',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // Options
                  Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      children: [
                        _buildMenuItem(
                          icon: HugeIcons.strokeRoundedUserEdit01,
                          title: context.tr('edit_names'),
                          subtitle: _fullName(),
                          onTap: () => _openEditor(
                            context.tr('edit_names'),
                            _NamesEditor(nom: _nom, prenoms: _prenoms),
                          ),
                        ),
                        divider,
                        _buildMenuItem(
                          icon: HugeIcons.strokeRoundedAt,
                          title: context.tr('change_pseudo'),
                          subtitle: (_pseudo?.isNotEmpty ?? false)
                              ? '@$_pseudo'
                              : null,
                          onTap: () => _openEditor(
                            context.tr('change_pseudo'),
                            _PseudoEditor(
                              pseudo: _pseudo,
                              nextChange: _nextPseudoChange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Déconnexion
                  Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: _buildMenuItem(
                      icon: HugeIcons.strokeRoundedLogout01,
                      title: context.tr('logout'),
                      color: AppColors.error,
                      onTap: _handleSignOut,
                    ),
                  ),
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
    borderRadius: BorderRadius.circular(50),
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

/// Modifier nom et prénoms
class _NamesEditor extends StatefulWidget {
  final String? nom;
  final String? prenoms;
  const _NamesEditor({this.nom, this.prenoms});

  @override
  State<_NamesEditor> createState() => _NamesEditorState();
}

class _NamesEditorState extends State<_NamesEditor> {
  late final _nom = TextEditingController(text: widget.nom);
  late final _prenoms = TextEditingController(text: widget.prenoms);
  bool _loading = false;

  @override
  void dispose() {
    _nom.dispose();
    _prenoms.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nom = _nom.text.trim();
    final prenoms = _prenoms.text.trim();
    if (nom.isEmpty || prenoms.isEmpty) {
      ToastService.showError(context, context.tr('field_required'));
      return;
    }
    setState(() => _loading = true);
    try {
      await SupabaseService.updateProfile(nom: nom, prenoms: prenoms);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ToastService.showError(context, context.tr('profile_update_error'));
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _nom,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: _fieldDecoration(context, context.tr('last_name')),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _prenoms,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          decoration: _fieldDecoration(context, context.tr('first_names')),
        ),
        const SizedBox(height: 24),
        _saveButton(context, loading: _loading, onPressed: _save),
      ],
    );
  }
}

enum _PseudoStatus { idle, invalid, checking, available, taken }

/// Changer de pseudo : disponibilité vérifiée pendant la saisie
class _PseudoEditor extends StatefulWidget {
  final String? pseudo;
  final ({DateTime? value})? nextChange;
  const _PseudoEditor({this.pseudo, this.nextChange});

  @override
  State<_PseudoEditor> createState() => _PseudoEditorState();
}

class _PseudoEditorState extends State<_PseudoEditor> {
  static final _format = RegExp(r'^[a-z0-9]{3,20}$');
  late final _controller = TextEditingController(text: widget.pseudo);
  Timer? _debounce;
  _PseudoStatus _status = _PseudoStatus.idle;
  bool _loading = false;
  String? _saveError;
  // _nextChange non null = changement bloqué jusqu'à cette date
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
      next = await SupabaseService.getNextPseudoChange();
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
    _saveError = null;
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
      await SupabaseService.updateProfile(pseudo: _controller.text);
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      // Pseudo pris entre-temps par quelqu'un d'autre
      setState(() {
        _loading = false;
        if (e.code == '23505') {
          _status = _PseudoStatus.taken;
        } else if (e.message.contains('pseudo_cooldown')) {
          _nextChange = DateTime.now().add(SupabaseService.pseudoCooldown);
          _loadCooldown();
        } else {
          _saveError = context.tr('profile_update_error');
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _saveError = context.tr('profile_update_error');
      });
    }
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
    final (String message, Color color) = _saveError != null
        ? (_saveError!, AppColors.error)
        : switch (_status) {
            _PseudoStatus.available => (
                context.tr('pseudo_available'),
                AppColors.success
              ),
            _PseudoStatus.taken => (
                context.tr('pseudo_taken'),
                AppColors.error
              ),
            _PseudoStatus.invalid => (
                context.tr('pseudo_rules'),
                AppColors.error
              ),
            _ => (context.tr('pseudo_rules'), AppColors.textSecondary),
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
          HugeIcon(
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
            FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
            TextInputFormatter.withFunction(
                (_, v) => v.copyWith(text: v.text.toLowerCase())),
            LengthLimitingTextInputFormatter(20),
          ],
          onChanged: _onChanged,
          onSubmitted: (_) => _save(),
          decoration: _fieldDecoration(context, context.tr('pseudo_hint'),
                  prefixText: '@')
              .copyWith(suffixIcon: _statusIcon()),
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
