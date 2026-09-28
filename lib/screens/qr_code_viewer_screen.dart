import 'dart:math';
import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:hugeicons/hugeicons.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import '../utils/auth_errors.dart';
import '../utils/toast_service.dart';
import '../widgets/app_bottom_sheet.dart';
import '../widgets/dynamic_qr.dart';

class QRCodeViewerScreen extends StatefulWidget {
  /// Scanner seul : pas d'onglet « Recevoir » ni de sélecteur (depuis l'envoi)
  final bool scanOnly;

  const QRCodeViewerScreen({super.key, this.scanOnly = false});

  @override
  State<QRCodeViewerScreen> createState() => _QRCodeViewerScreenState();
}

class _QRCodeViewerScreenState extends State<QRCodeViewerScreen>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late TabController _tabController;
  final MobileScannerController _cameraController = MobileScannerController();
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;
  bool _isFlipped = false;
  bool _torchEnabled = false;
  bool _handlingScan = false;
  final Random _random = Random();
  late List<IconPosition> _iconPositions;

  // Liste des icônes financières
  static final List<IconData> _financeIcons = [
    Icons.account_balance,
    Icons.account_balance_wallet,
    Icons.credit_card,
    Icons.payment,
    Icons.attach_money,
    Icons.monetization_on,
    Icons.savings,
    Icons.account_circle,
    Icons.wallet,
    Icons.receipt,
    Icons.point_of_sale,
    Icons.money_off,
    Icons.currency_exchange,
    Icons.trending_up,
    Icons.trending_down,
    Icons.show_chart,
    Icons.bar_chart,
    Icons.pie_chart,
    Icons.account_tree,
    Icons.business,
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _tabController = TabController(length: 2, vsync: this);
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );
    _generateIconPositions();
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        _pageController.animateToPage(
          _tabController.index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  bool _hasCollision(
    IconPosition newPos,
    List<IconPosition> existingPositions,
  ) {
    const double cardWidth = 300.0;
    const double centerX = 0.5;
    const double centerY = 0.5;
    const double logoRadius = 0.15;

    final double distanceToCenter = sqrt(
      pow(newPos.left - centerX, 2) + pow(newPos.top - centerY, 2),
    );
    final double newSizePercent = newPos.size / cardWidth;
    if (distanceToCenter < logoRadius + newSizePercent / 2) {
      return true;
    }

    for (var existingPos in existingPositions) {
      final double deltaX = newPos.left - existingPos.left;
      final double deltaY = newPos.top - existingPos.top;
      final double distancePercent = sqrt(deltaX * deltaX + deltaY * deltaY);

      final double existingSizePercent = existingPos.size / cardWidth;
      final bool isSameIcon =
          newPos.icon.codePoint == existingPos.icon.codePoint;
      final double baseMargin = isSameIcon ? 0.08 : 0.02;
      final double minDistancePercent =
          (newSizePercent + existingSizePercent) / 2 + baseMargin;

      if (distancePercent < minDistancePercent) {
        return true;
      }
    }
    return false;
  }

  void _generateIconPositions() {
    _iconPositions = [];
    const int numberOfIcons = 12;
    const int gridCols = 4;
    const int gridRows = 4;

    final List<({int col, int row})> availableZones = [];
    for (int row = 0; row < gridRows; row++) {
      for (int col = 0; col < gridCols; col++) {
        availableZones.add((col: col, row: row));
      }
    }

    availableZones.shuffle(_random);

    const double centerX = 0.5;
    const double centerY = 0.5;
    const double logoRadius = 0.15;

    int iconCount = 0;
    for (final zone in availableZones) {
      if (iconCount >= numberOfIcons) break;

      final double zoneWidth = 1.0 / gridCols;
      final double zoneHeight = 1.0 / gridRows;

      final double zoneLeft = zone.col * zoneWidth;
      final double zoneTop = zone.row * zoneHeight;

      final double margin = 0.1;
      final double left = zoneLeft +
          margin * zoneWidth +
          _random.nextDouble() * zoneWidth * (1 - 2 * margin);
      final double top = zoneTop +
          margin * zoneHeight +
          _random.nextDouble() * zoneHeight * (1 - 2 * margin);

      final double distanceToCenter = sqrt(
        pow(left - centerX, 2) + pow(top - centerY, 2),
      );

      if (distanceToCenter < logoRadius) {
        continue;
      }

      final iconPosition = IconPosition(
        icon: _financeIcons[_random.nextInt(_financeIcons.length)],
        top: top,
        left: left,
        size: 15 + _random.nextDouble() * 20,
        opacity: 0.1 + _random.nextDouble() * 0.2,
        rotation: _random.nextDouble() * 360,
      );

      if (!_hasCollision(iconPosition, _iconPositions)) {
        _iconPositions.add(iconPosition);
        iconCount++;
      }
    }

    while (_iconPositions.length < numberOfIcons) {
      final candidate = IconPosition(
        icon: _financeIcons[_random.nextInt(_financeIcons.length)],
        top: _random.nextDouble() * 0.8,
        left: _random.nextDouble() * 0.8,
        size: 15 + _random.nextDouble() * 20,
        opacity: 0.1 + _random.nextDouble() * 0.2,
        rotation: _random.nextDouble() * 360,
      );

      if (!_hasCollision(candidate, _iconPositions)) {
        _iconPositions.add(candidate);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _tabController.dispose();
    _cameraController.dispose();
    _flipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.viewPadding.top;
    final bottomPadding = mediaQuery.viewPadding.bottom;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          // SafeArea en haut
          SizedBox(height: topPadding),
          // AppBar personnalisée
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.arrow_back,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) {
                _tabController.animateTo(index);
              },
              physics:
                  widget.scanOnly ? const NeverScrollableScrollPhysics() : null,
              children: [
                // Page 1 - QR Code
                _buildQRCodePage(),
                // Page 2 - Informations
                if (!widget.scanOnly) _buildInfoPage(),
              ],
            ),
          ),
          if (widget.scanOnly) SizedBox(height: 40 + bottomPadding),
          // TabBar en bas
          if (!widget.scanOnly)
            Container(
              margin: EdgeInsets.fromLTRB(20, 20, 20, 40 + bottomPadding),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(50),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(50),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: AppColors.secondary,
                    borderRadius: BorderRadius.circular(50),
                  ),
                  dividerColor: Colors.transparent,
                  labelColor: Colors.white,
                  unselectedLabelColor: Theme.of(context).colorScheme.onSurface,
                  labelStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  tabs: [
                    Tab(text: context.tr('send')),
                    Tab(text: context.tr('receive')),
                  ],
                  onTap: (index) {
                    _pageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQRCodePage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Zone de caméra pour scanner
          Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(24),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                MobileScanner(
                  controller: _cameraController,
                  onDetect: (capture) {
                    final value = capture.barcodes
                        .map((b) => b.rawValue)
                        .whereType<String>()
                        .firstOrNull;
                    if (value != null) _onScanned(value);
                  },
                ),
                // Overlay avec cadre de scan
                Positioned.fill(
                  child: CustomPaint(painter: QRScannerOverlay()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            context.tr('scan_qr'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
          ),
          const SizedBox(height: 16),
          // Bouton torche
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: HugeIcon(
                icon: _torchEnabled
                    ? HugeIcons.strokeRoundedFlash
                    : HugeIcons.strokeRoundedFlash,
                size: 24,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: () {
                setState(() {
                  _torchEnabled = !_torchEnabled;
                  _cameraController.toggleTorch();
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPage() => _buildFlipCard();

  Widget _buildFlipCard() {
    return Center(
      child: GestureDetector(
        onTap: () {
          if (_flipController.isAnimating) return;
          _isFlipped = !_isFlipped;
          if (_isFlipped) {
            _flipController.forward();
          } else {
            _flipController.reverse();
          }
        },
        child: AnimatedBuilder(
          animation: _flipAnimation,
          builder: (context, child) {
            final angle =
                _flipAnimation.value * 3.14159; // 180 degrés en radians
            final isFrontVisible = _flipAnimation.value < 0.5;

            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001) // Perspective
                ..rotateY(angle),
              child: isFrontVisible
                  ? _buildFlipCardFront()
                  : Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..rotateY(3.14159), // Retourner la face arrière
                      child: _buildFlipCardBack(),
                    ),
            );
          },
        ),
      ),
    );
  }

  /// QR scanné : résolution côté serveur puis fiche du destinataire
  Future<void> _onScanned(String value) async {
    if (_handlingScan) return;
    _handlingScan = true;
    await _cameraController.stop();
    try {
      final payee = await SupabaseService.resolveQr(value);
      if (!mounted) return;
      if (payee.isSelf) {
        ToastService.showInfo(context, context.tr('qr_self'));
      } else {
        await _showPayeeSheet(payee);
      }
    } catch (e) {
      if (mounted)
        ToastService.showError(context, authErrorMessage(context, e));
      // Évite de re-scanner le même QR invalide en boucle
      await Future.delayed(const Duration(seconds: 2));
    } finally {
      _handlingScan = false;
      if (mounted) await _cameraController.start();
    }
  }

  Future<void> _showPayeeSheet(QrPayee payee) {
    final textTheme = Theme.of(context).textTheme;
    final initial =
        payee.prenom.isNotEmpty ? payee.prenom[0].toUpperCase() : '?';
    return showAppBottomSheet<void>(
      context: context,
      title: context.tr('qr_pay_to'),
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: CircleAvatar(
              radius: 36,
              backgroundColor: Colors.black,
              foregroundImage: payee.avatarUrl != null
                  ? NetworkImage(payee.avatarUrl!)
                  : null,
              child: Text(
                initial,
                style: textTheme.headlineSmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            payee.prenom,
            textAlign: TextAlign.center,
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            '@${payee.pseudo}',
            textAlign: TextAlign.center,
            style:
                textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          Text(
            payee.numeroMasque == null
                ? context.tr('qr_no_default_account')
                : '${payee.reseau} · +225 ${payee.numeroMasque}',
            textAlign: TextAlign.center,
            style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: payee.numeroMasque == null
                ? null
                : () {
                    // L'envoi utilisera payee.payeeRef (référence chiffrée)
                    Navigator.of(sheetContext).pop();
                    ToastService.showInfo(
                        context, context.tr('send_coming_soon'));
                  },
            child: Text(context.tr('send')),
          ),
        ],
      ),
    );
  }

  Widget _buildFlipCardFront() {
    return Container(
      key: const ValueKey('front'),
      width: 300,
      height: 400,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Marge blanche autour du QR : coins arrondis sans rogner les repères
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const DynamicQrCode(size: 200),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlipCardBack() {
    return Container(
      key: const ValueKey('back'),
      width: 300,
      height: 400,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Stack(
        children: [
          // Icônes financières aléatoires en arrière-plan
          ..._iconPositions.map((iconPos) {
            return Positioned(
              top: iconPos.top * 400,
              left: iconPos.left * 300,
              child: Transform.rotate(
                angle: iconPos.rotation * pi / 180,
                child: Opacity(
                  opacity: iconPos.opacity,
                  child: Icon(
                    iconPos.icon,
                    size: iconPos.size,
                    color: Colors.black,
                  ),
                ),
              ),
            );
          }),
          // Logo centré par-dessus
          Center(
            child: Transform.rotate(
              angle: -pi / 2, // -90 degrés
              child: Image.asset(
                'assets/images/seno-logo.png',
                width: 120,
                height: 120,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Classe pour stocker les informations de position des icônes
class IconPosition {
  final IconData icon;
  final double top;
  final double left;
  final double size;
  final double opacity;
  final double rotation;

  IconPosition({
    required this.icon,
    required this.top,
    required this.left,
    required this.size,
    required this.opacity,
    required this.rotation,
  });
}

// Overlay personnalisé pour le scanner
class QRScannerOverlay extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final path = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final cutoutSize = size.width * 0.7;
    final cutoutLeft = (size.width - cutoutSize) / 2;
    final cutoutTop = (size.height - cutoutSize) / 2;

    final cutoutPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cutoutLeft, cutoutTop, cutoutSize, cutoutSize),
          const Radius.circular(24),
        ),
      );

    final finalPath = Path.combine(PathOperation.difference, path, cutoutPath);

    canvas.drawPath(finalPath, paint);

    // Cadre de scan
    final framePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cutoutLeft, cutoutTop, cutoutSize, cutoutSize),
        const Radius.circular(24),
      ),
      framePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
