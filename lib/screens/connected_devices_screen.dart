import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../l10n/app_strings.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import '../utils/toast_service.dart';
import '../widgets/app_bottom_sheet.dart';

/// Sessions actives : cet appareil en premier, les autres révocables
class ConnectedDevicesScreen extends StatefulWidget {
  const ConnectedDevicesScreen({super.key});

  @override
  State<ConnectedDevicesScreen> createState() => _ConnectedDevicesScreenState();
}

class _ConnectedDevicesScreenState extends State<ConnectedDevicesScreen> {
  List<Map<String, dynamic>>? _sessions;
  bool _error = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sessions = await SupabaseService.listMySessions();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _error = false;
      });
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  /// Nom lisible à partir du user-agent
  String _deviceName(String? ua) {
    final l = (ua ?? '').toLowerCase();
    if (l.contains('iphone')) return 'iPhone';
    if (l.contains('ipad')) return 'iPad';
    if (l.contains('android')) return 'Android';
    if (l.contains('mac os') || l.contains('macintosh')) return 'Mac';
    if (l.contains('windows')) return 'Windows';
    if (l.contains('linux')) return 'Linux';
    if (l.startsWith('dart/')) return 'Seno';
    return context.tr('unknown_device');
  }

  dynamic _deviceIcon(String? ua) {
    final l = (ua ?? '').toLowerCase();
    if (l.contains('mac os') || l.contains('windows') || l.contains('linux')) {
      return HugeIcons.strokeRoundedComputer;
    }
    return HugeIcons.strokeRoundedSmartPhone01;
  }

  String _formatDate(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '-';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  /// Confirme puis exécute une déconnexion, et recharge la liste
  Future<void> _disconnect(
      String title, String message, Future<void> Function() action) async {
    final confirm = await showConfirmSheet(
      context: context,
      title: title,
      message: message,
      confirmLabel: context.tr('disconnect_device'),
      destructive: true,
    );
    if (!confirm || !mounted) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        ToastService.showSuccess(context, context.tr('device_disconnected'));
      }
      await _load();
    } catch (_) {
      if (mounted) ToastService.showError(context, context.tr('logout_error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _iconBox(dynamic icon, Color color) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(child: HugeIcon(icon: icon, size: 20, color: color)),
      );

  Widget _buildSession(Map<String, dynamic> s) {
    final ua = s['user_agent'] as String?;
    final current = s['is_current'] == true;
    final details = [
      if (s['ip'] != null) s['ip'] as String,
      current
          ? context.tr('this_device')
          : context.tr('last_active',
              {'date': _formatDate(s['last_active_at'] as String?)}),
    ].join(' · ');

    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        leading: _iconBox(_deviceIcon(ua), AppColors.secondary),
        title: Text(
          _deviceName(ua),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: current ? FontWeight.w600 : null,
              ),
        ),
        subtitle: Text(
          details,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: current ? AppColors.success : AppColors.textSecondary,
                fontSize: 12,
              ),
        ),
        trailing: current
            ? null
            : IconButton(
                icon: const Icon(Icons.logout, color: AppColors.error),
                tooltip: context.tr('disconnect_device'),
                onPressed: _busy
                    ? null
                    : () => _disconnect(
                          context.tr('disconnect_device'),
                          context.tr('disconnect_device_confirm'),
                          () => SupabaseService.revokeSession(
                              s['id'] as String),
                        ),
              ),
      ),
    );
  }

  Widget _card(Widget child) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: child,
      );

  Widget _buildBody() {
    final sessions = _sessions;
    if (sessions == null) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: _error
              ? Column(
                  children: [
                    Text(context.tr('devices_load_error'),
                        style: TextStyle(color: AppColors.textSecondary)),
                    TextButton(
                      onPressed: () {
                        setState(() => _error = false);
                        _load();
                      },
                      child: Text(context.tr('retry')),
                    ),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      );
    }

    final divider = Divider(
        height: 1, color: AppColors.textSecondary.withValues(alpha: 0.2));
    final hasOthers = sessions.any((s) => s['is_current'] != true);

    return Column(
      children: [
        _card(Column(
          children: [
            for (var i = 0; i < sessions.length; i++) ...[
              if (i > 0) divider,
              _buildSession(sessions[i]),
            ],
          ],
        )),
        if (!hasOthers)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              context.tr('no_other_devices'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          )
        else
          _card(Material(
            type: MaterialType.transparency,
            child: ListTile(
              leading:
                  _iconBox(HugeIcons.strokeRoundedLogout01, AppColors.error),
              title: Text(
                context.tr('disconnect_others'),
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: AppColors.error),
              ),
              onTap: _busy
                  ? null
                  : () => _disconnect(
                        context.tr('disconnect_others'),
                        context.tr('disconnect_others_confirm'),
                        SupabaseService.signOutOtherDevices,
                      ),
            ),
          )),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SizedBox(height: mediaQuery.viewPadding.top),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
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
                          Expanded(
                            child: Text(
                              context.tr('connected_devices'),
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 28,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildBody(),
                    SizedBox(height: mediaQuery.viewPadding.bottom + 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
