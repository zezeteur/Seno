import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:permission_handler/permission_handler.dart';
import '../l10n/app_strings.dart';
import '../services/nearby_service.dart';
import '../widgets/user_avatar.dart';
import 'send_money_screen.dart';

/// Envoi aux appareils à proximité : radar animé + personnes détectées
class NearbySendScreen extends StatefulWidget {
  const NearbySendScreen({super.key});

  /// Ouverture / fermeture en cercle qui s'agrandit depuis [center] (le radar)
  static Route<void> route(Offset center) => PageRouteBuilder(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 550),
        reverseTransitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, __, ___) => const NearbySendScreen(),
        transitionsBuilder: (context, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOutCubic,
            reverseCurve: Curves.easeInOutCubic.flipped,
          );
          return AnimatedBuilder(
            animation: curved,
            child: child,
            builder: (context, child) => ClipPath(
              clipper: _CircleRevealClipper(center, curved.value),
              child: child,
            ),
          );
        },
      );

  @override
  State<NearbySendScreen> createState() => _NearbySendScreenState();
}

class _NearbySendScreenState extends State<NearbySendScreen>
    with TickerProviderStateMixin {
  static const _blue = Color(0xFF0050E6);

  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  late final _float = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  /// Son joué à chaque nouvelle personne détectée
  final _foundPlayer = AudioPlayer();
  int _lastCount = 0;

  /// Bluetooth refusé : message + accès aux réglages à la place des personnes
  bool _bluetoothDenied = false;

  @override
  void initState() {
    super.initState();
    NearbyService.people.addListener(_onPeopleChanged);
    // Après la transition en cercle, pour ne pas la saccader
    Future.delayed(const Duration(milliseconds: 600), _requestBluetooth);
  }

  /// Android 12+ : scan / annonce / connexion ; iOS : Bluetooth
  Future<void> _requestBluetooth() async {
    if (!mounted) return;
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    // Android 11 et moins : le scan BLE exige la localisation
    final legacyAndroid =
        !isIOS && (await DeviceInfoPlugin().androidInfo).version.sdkInt < 31;
    if (!mounted) return;
    final permissions = isIOS
        ? [Permission.bluetooth]
        : legacyAndroid
            ? [Permission.locationWhenInUse]
            : [
                Permission.bluetoothScan,
                Permission.bluetoothAdvertise,
                Permission.bluetoothConnect,
              ];
    final statuses = await permissions.request();
    if (!mounted) return;
    final denied = statuses.values.any((s) => !s.isGranted && !s.isLimited);
    setState(() => _bluetoothDenied = denied);
    if (!denied) await NearbyService.start();
  }

  void _onPeopleChanged() {
    final count = NearbyService.people.value.length;
    if (count > _lastCount) {
      _foundPlayer.play(AssetSource('sounds/scan.wav'));
      HapticFeedback.lightImpact();
    }
    _lastCount = count;
  }

  Future<void> _onDeniedTap() async {
    final permanently = await (Theme.of(context).platform == TargetPlatform.iOS
            ? Permission.bluetooth
            : Permission.bluetoothScan)
        .isPermanentlyDenied;
    if (permanently) {
      await openAppSettings();
    } else {
      await _requestBluetooth();
    }
  }

  @override
  void dispose() {
    NearbyService.people.removeListener(_onPeopleChanged);
    NearbyService.stop();
    _foundPlayer.dispose();
    _pulse.dispose();
    _float.dispose();
    super.dispose();
  }

  /// Personne choisie : écran d'envoi ouvert directement sur le montant
  void _send(NearbyPerson p) => Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SendMoneyScreen(
            initialRecipient: (
              value: p.pseudo,
              avatarUrl: p.avatarUrl,
              phone: null,
            ),
          ),
        ),
      );

  /// « Anny A. » : premier prénom + initiale, sinon le pseudo
  static String _displayName(NearbyPerson p) {
    final parts = (p.prenoms ?? '').trim().split(RegExp(r'\s+'));
    if (parts.first.isEmpty) return p.pseudo;
    return parts.length > 1 ? '${parts[0]} ${parts[1][0]}.' : parts[0];
  }

  String _statusText(NearbyStatus status) {
    if (_bluetoothDenied) return context.tr('nearby_bluetooth_denied');
    return context.tr(switch (status) {
      NearbyStatus.bluetoothOff => 'nearby_bluetooth_off',
      NearbyStatus.unsupported => 'nearby_unsupported',
      NearbyStatus.error => 'nearby_error',
      _ => 'nearby_searching',
    });
  }

  @override
  Widget build(BuildContext context) {
    // viewPadding comme les autres écrans (padding peut être remis à zéro)
    final viewPadding = MediaQuery.viewPaddingOf(context);
    // Barre d'état en blanc sur le fond bleu
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _blue,
        body: Padding(
          padding:
              EdgeInsets.only(top: viewPadding.top, bottom: viewPadding.bottom),
          child: Column(
            children: [
              // Retour : pastille translucide, détachée de la barre d'état
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.18),
                      fixedSize: const Size(44, 44),
                    ),
                    onPressed: () => Navigator.pop(context),
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowLeft02,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ),
              Expanded(child: _buildRadar()),
              Text(
                context.tr('nearby_title'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder(
                valueListenable: NearbyService.status,
                builder: (context, status, _) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    _statusText(status),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                height: 90,
                child: _bluetoothDenied
                    ? Center(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: _blue,
                          ),
                          onPressed: _onDeniedTap,
                          child: Text(context.tr('nearby_enable_bluetooth')),
                        ),
                      )
                    : ValueListenableBuilder(
                        valueListenable: NearbyService.people,
                        builder: (context, people, _) => _buildPeople(people),
                      ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  /// Cercles concentriques qui s'élargissent + deux téléphones qui flottent
  Widget _buildRadar() {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulse, _float]),
      builder: (context, _) {
        final dy = (_float.value - 0.5) * 10;
        return Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size.square(320),
              painter: _RadarPainter(_pulse.value),
            ),
            Transform.translate(
              offset: Offset(-50, -40 + dy),
              child: Transform.rotate(
                angle: -0.18,
                child: const _Phone(
                  frame: Color(0xFFF5E400),
                  screen: Color(0xFFFFFDF0),
                  coin: Color(0xFFF0936B),
                  coinEdge: Color(0xFFA0522D),
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(55, 70 - dy),
              child: Transform.rotate(
                angle: -0.14,
                child: const _Phone(
                  frame: Color(0xFF0038B8),
                  screen: Color(0xFFF4F6FF),
                  coin: Color(0xFFF5E400),
                  coinEdge: Color(0xFF8A7F00),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPeople(List<NearbyPerson> people) {
    if (people.isEmpty) return const SizedBox.shrink();
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: people.length,
      separatorBuilder: (_, __) => const SizedBox(width: 24),
      itemBuilder: (context, i) {
        final p = people[i];
        return GestureDetector(
          onTap: () => _send(p),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: UserAvatar(
                  pseudo: p.pseudo,
                  avatarUrl: p.avatarUrl,
                  radius: 20,
                  backgroundColor: const Color(0xFFF5E400),
                  foregroundColor: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 84,
                child: Text(
                  _displayName(p),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.width / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    // 4 ondes décalées : rayon croissant, opacité décroissante
    for (var i = 0; i < 4; i++) {
      final p = (t + i / 4) % 1;
      paint.color = Colors.white.withValues(alpha: 0.25 * (1 - p));
      canvas.drawCircle(center, maxR * (0.25 + 0.75 * p), paint);
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.t != t;
}

/// Téléphone stylisé avec une pièce au centre et des ondes au coin
class _Phone extends StatelessWidget {
  const _Phone({
    required this.frame,
    required this.screen,
    required this.coin,
    required this.coinEdge,
  });

  final Color frame;
  final Color screen;
  final Color coin;
  final Color coinEdge;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      height: 160,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 80,
            height: 140,
            margin: const EdgeInsets.only(top: 20),
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: frame,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black, width: 1.5),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: screen,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.black, width: 1.2),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 44,
                height: 52,
                decoration: BoxDecoration(
                  color: coin,
                  shape: BoxShape.circle,
                  border: Border.all(color: coinEdge, width: 3),
                ),
                child: Container(
                  margin: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: coinEdge, width: 1),
                  ),
                ),
              ),
            ),
          ),
          // Ondes « vibration » au coin du téléphone
          Positioned(
            top: 0,
            left: -14,
            child: Transform.rotate(
              angle: -math.pi / 4,
              child: CustomPaint(
                size: const Size(28, 28),
                painter: _WavesPainter(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WavesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final c = Offset(size.width / 2, size.height);
    for (final r in [9.0, 16.0]) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi * 0.8,
          math.pi * 0.6, false, paint);
    }
  }

  @override
  bool shouldRepaint(_WavesPainter old) => false;
}

/// Cercle centré sur [center] ; à 1, il couvre tout l'écran (coin le plus loin)
class _CircleRevealClipper extends CustomClipper<Path> {
  _CircleRevealClipper(this.center, this.progress);

  final Offset center;
  final double progress;

  @override
  Path getClip(Size size) {
    final maxRadius = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((c) => (c - center).distance).reduce(math.max);
    return Path()
      ..addOval(Rect.fromCircle(center: center, radius: maxRadius * progress));
  }

  @override
  bool shouldReclip(_CircleRevealClipper old) =>
      old.progress != progress || old.center != center;
}
