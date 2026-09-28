import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import '../l10n/app_strings.dart';
import '../models/compte.dart';
import '../models/reseau.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import '../utils/pair_digits_formatter.dart';
import '../utils/toast_service.dart';
import '../widgets/pin_pad.dart';
import '../widgets/user_avatar.dart';
import 'qr_code_viewer_screen.dart';

enum _Step { recipient, amount }

/// Envoi d'argent : destinataire (pseudo ou numéro) → montant
class SendMoneyScreen extends StatefulWidget {
  const SendMoneyScreen({super.key});

  @override
  State<SendMoneyScreen> createState() => _SendMoneyScreenState();
}

class _SendMoneyScreenState extends State<SendMoneyScreen> {
  static const int _minAmount = 200;
  static const int _maxAmount = 1000000;
  static final _phonePattern = RegExp(r'^[\d ]+$');

  // Contacts récents (données de démonstration, comme sur l'accueil)
  static const _recents = [
    (pseudo: 'devon', color: Colors.blue),
    (pseudo: 'sara_k', color: Colors.green),
    (pseudo: 'moussa225', color: Colors.purple),
  ];

  final _recipientController = TextEditingController();
  _Step _step = _Step.recipient;
  String _recipient = '';
  String _amount = '';

  Compte? _compte;
  Reseau? _reseau;

  /// Pourcentage des frais (backend) ; null tant qu'il n'est pas connu
  double? _feePercent;

  /// Coché : l'expéditeur paie les frais ; sinon ils sont retirés du montant reçu
  bool _senderPaysFees = true;

  @override
  void initState() {
    super.initState();
    _recipientController.addListener(() => setState(() {}));
    _loadCompte();
    _loadFeePercent();
  }

  Future<void> _loadFeePercent() async {
    try {
      final percent = await SupabaseService.getFeePercent();
      if (mounted) setState(() => _feePercent = percent);
    } catch (_) {
      // Hors ligne sans cache : frais et total restent masqués
    }
  }

  @override
  void dispose() {
    _recipientController.dispose();
    super.dispose();
  }

  Future<void> _loadCompte() async {
    try {
      final compte = await SupabaseService.getDefaultCompte() ??
          (await SupabaseService.getComptes()).firstOrNull;
      final reseaux = await SupabaseService.getReseaux();
      if (!mounted) return;
      setState(() {
        _compte = compte;
        _reseau = reseaux.where((r) => r.id == compte?.idReseau).firstOrNull;
      });
    } catch (_) {
      // Hors ligne : la ligne du compte débité reste masquée
    }
  }

  bool get _recipientValid {
    final text = _recipientController.text.trim();
    if (text.isEmpty) return false;
    return _phonePattern.hasMatch(text)
        ? text.replaceAll(' ', '').length == 10
        : text.length >= 3;
  }

  void _selectRecipient(String value) {
    FocusScope.of(context).unfocus();
    setState(() {
      _recipient = value;
      _amount = '';
      _step = _Step.amount;
    });
  }

  void _onDigit(String digit) {
    if (_amount.isEmpty && digit == '0') return;
    // Au-delà du maximum : la touche est ignorée
    if (int.parse(_amount + digit) > _maxAmount) {
      HapticFeedback.heavyImpact();
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _amount += digit);
  }

  void _onDelete() {
    if (_amount.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() => _amount = _amount.substring(0, _amount.length - 1));
  }

  void _submit() {
    // Transfert à brancher sur le backend de paiement
    ToastService.showError(context, context.tr('send_coming_soon'));
  }

  void _onBack() {
    if (_step == _Step.amount) {
      setState(() => _step = _Step.recipient);
      return;
    }
    Navigator.of(context).pop();
  }

  int get _amountValue => int.tryParse(_amount) ?? 0;
  bool get _amountValid =>
      _amountValue >= _minAmount && _amountValue <= _maxAmount;
  int get _fee => (_amountValue * (_feePercent ?? 0) / 100).ceil();
  int get _total => _senderPaysFees ? _amountValue + _fee : _amountValue;
  int get _received => _senderPaysFees ? _amountValue : _amountValue - _fee;

  /// 25000 → « 25 000 »
  String _formatAmount(String digits) {
    if (digits.isEmpty) return '0';
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final viewPadding = MediaQuery.of(context).viewPadding;

    return PopScope(
      canPop: _step == _Step.recipient,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Stack(
          children: [
            Positioned(
              top: viewPadding.top + 8,
              left: 8,
              child: IconButton(
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowLeft01,
                  color: textTheme.bodyLarge?.color ?? Colors.black,
                ),
                onPressed: _onBack,
              ),
            ),
            // Scanner : ouvre l'écran QR sur l'onglet « Envoyer » (caméra)
            if (_step == _Step.recipient)
              Positioned(
                top: viewPadding.top + 8,
                right: 8,
                child: IconButton(
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedQrCode01,
                    color: textTheme.bodyLarge?.color ?? Colors.black,
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const QRCodeViewerScreen(scanOnly: true),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                viewPadding.top + 72,
                24,
                viewPadding.bottom + 32,
              ),
              child: _step == _Step.recipient
                  ? _buildRecipientStep(textTheme)
                  : _buildAmountStep(textTheme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecipientStep(TextTheme textTheme) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final pill = OutlineInputBorder(
      borderRadius: BorderRadius.circular(50),
      borderSide: BorderSide.none,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('send_money'),
          style: textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          context.tr('send_recipient_subtitle'),
          style: textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _recipientController,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            // Numéro : chiffres groupés 2 par 2 ; pseudo : texte libre
            TextInputFormatter.withFunction((oldValue, newValue) =>
                _phonePattern.hasMatch(newValue.text)
                    ? PairDigitsFormatter(maxDigits: 10)
                        .formatEditUpdate(oldValue, newValue)
                    : newValue),
          ],
          onSubmitted: (_) {
            if (_recipientValid) {
              _selectRecipient(_recipientController.text.trim());
            }
          },
          decoration: InputDecoration(
            hintText: context.tr('send_recipient_hint'),
            filled: true,
            fillColor: onSurface.withValues(alpha: 0.05),
            prefixIcon: Padding(
              padding: const EdgeInsets.all(14),
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedSearch01,
                size: 20,
                color: onSurface.withValues(alpha: 0.5),
              ),
            ),
            // Pilule : tous les états (le thème peut surcharger enabled/focused)
            border: pill,
            enabledBorder: pill,
            focusedBorder: pill,
          ),
        ),
        const SizedBox(height: 32),
        Text(
          context.tr('send_recents'),
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (final c in _recents)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: UserAvatar(
                    pseudo: c.pseudo,
                    radius: 22,
                    backgroundColor: c.color,
                    foregroundColor: Colors.white,
                  ),
                  title: Text('@${c.pseudo}'),
                  trailing: HugeIcon(
                    icon: HugeIcons.strokeRoundedArrowRight01,
                    size: 18,
                    color: onSurface.withValues(alpha: 0.4),
                  ),
                  onTap: () => _selectRecipient(c.pseudo),
                ),
            ],
          ),
        ),
        _buildPrimaryButton(
          label: context.tr('continue'),
          onPressed: _recipientValid
              ? () => _selectRecipient(_recipientController.text.trim())
              : null,
        ),
      ],
    );
  }

  Widget _buildAmountStep(TextTheme textTheme) {
    final isPhone = _phonePattern.hasMatch(_recipient);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Destinataire
        Row(
          children: [
            UserAvatar(
              pseudo: isPhone ? null : _recipient,
              radius: 22,
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('qr_pay_to'),
                    style: textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  Text(
                    isPhone ? _recipient : '@$_recipient',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Spacer(),
        // Montant
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: _formatAmount(_amount)),
                TextSpan(
                  text: ' FCFA',
                  style: textTheme.titleLarge
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
            style: textTheme.displayMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: _amount.isEmpty ? AppColors.textSecondary : null,
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_compte != null)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(50),
              ),
              child: Text(
                context.tr('send_from', {
                  'account': [
                    if (_reseau != null) _reseau!.nom,
                    PairDigitsFormatter.group(_compte!.numero),
                  ].join(' · '),
                }),
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.textOnPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        const Spacer(),
        if (_feePercent != null) ...[
          _buildFeesToggle(textTheme),
          const SizedBox(height: 8),
          _buildSummaryRow(textTheme, context.tr('send_receives'), _received),
          const SizedBox(height: 4),
          _buildSummaryRow(textTheme, context.tr('send_total'), _total,
              bold: true),
          const SizedBox(height: 24),
        ],
        PinKeypad(onDigit: _onDigit, onDelete: _onDelete),
        const SizedBox(height: 24),
        _buildPrimaryButton(
          label: context.tr('send'),
          onPressed: !_amountValid || _feePercent == null || _received <= 0
              ? null
              : _submit,
        ),
      ],
    );
  }

  Widget _buildFeesToggle(TextTheme textTheme) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr('send_pay_fees'), style: textTheme.bodyMedium),
              Text(
                '${_formatAmount(_fee.toString())} FCFA',
                style: textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        Transform.scale(
          scale: 0.8,
          alignment: Alignment.centerRight,
          child: Switch(
            value: _senderPaysFees,
            activeTrackColor: AppColors.secondary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (value) {
              HapticFeedback.selectionClick();
              setState(() => _senderPaysFees = value);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(TextTheme textTheme, String label, int value,
      {bool bold = false}) {
    final style = textTheme.bodyMedium?.copyWith(
      fontWeight: bold ? FontWeight.bold : FontWeight.w500,
      color: bold ? null : AppColors.textSecondary,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text('${_formatAmount(value.toString())} FCFA', style: style),
      ],
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required VoidCallback? onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        overlayColor: Colors.transparent,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.black.withValues(alpha: 0.2),
        disabledForegroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }
}
