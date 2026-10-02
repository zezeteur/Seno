import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../l10n/app_strings.dart';
import '../screens/transaction_details_screen.dart';
import '../services/recents_store.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import 'user_avatar.dart';

/// Transactions regroupées par jour (liste triée du plus récent au plus ancien).
/// Partagé entre l'accueil et l'historique.
class TransactionList extends StatelessWidget {
  final List<SenoTransaction> transactions;

  const TransactionList({super.key, required this.transactions});

  /// « Aujourd'hui », « Hier », sinon « 28/09/2026 »
  static String dayLabel(BuildContext context, DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return context.tr('today');
    if (diff == 1) return context.tr('yesterday');
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(day.day)}/${two(day.month)}/${day.year}';
  }

  @override
  Widget build(BuildContext context) {
    // Noms du répertoire dès qu'ils sont chargés
    return ListenableBuilder(
      listenable: Listenable.merge([
        RecentsStore.phoneContacts,
        RecentsStore.senoAccounts,
      ]),
      builder: (context, _) {
        final children = <Widget>[];
        String? currentDay;
        for (final tx in transactions) {
          final day = dayLabel(context, tx.createdAt);
          if (day != currentDay) {
            if (currentDay != null) children.add(const SizedBox(height: 12));
            children.add(TransactionsHeader(label: day));
            children.add(const SizedBox(height: 16));
            currentDay = day;
          }
          children.add(TransactionTile(transaction: tx));
          children.add(const SizedBox(height: 20));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        );
      },
    );
  }
}

/// Même liste en slivers : la date du jour reste épinglée en haut tant que
/// ses transactions défilent, puis la suivante la pousse.
class TransactionSliverList extends StatelessWidget {
  final List<SenoTransaction> transactions;
  final EdgeInsetsGeometry padding;

  const TransactionSliverList({
    super.key,
    required this.transactions,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        RecentsStore.phoneContacts,
        RecentsStore.senoAccounts,
      ]),
      builder: (context, _) {
        final groups = <(String, List<SenoTransaction>)>[];
        for (final tx in transactions) {
          final day = TransactionList.dayLabel(context, tx.createdAt);
          if (groups.isEmpty || groups.last.$1 != day) groups.add((day, []));
          groups.last.$2.add(tx);
        }
        final background = Theme.of(context).scaffoldBackgroundColor;
        return SliverPadding(
          padding: padding,
          sliver: SliverMainAxisGroup(
            slivers: [
              for (final (day, txs) in groups)
                SliverMainAxisGroup(
                  slivers: [
                    // Fond opaque : les transactions passent dessous
                    PinnedHeaderSliver(
                      child: ColoredBox(
                        color: background,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 16),
                          child: TransactionsHeader(label: day),
                        ),
                      ),
                    ),
                    SliverList.list(
                      children: [
                        for (final tx in txs) ...[
                          TransactionTile(transaction: tx),
                          const SizedBox(height: 20),
                        ],
                        const SizedBox(height: 12),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

/// En-tête de groupe (jour) ou de section
class TransactionsHeader extends StatelessWidget {
  final String label;

  const TransactionsHeader({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Transform.scale(
          scale: 0.95,
          child: HugeIcon(
            icon: HugeIcons.strokeRoundedWallet01,
            size: 16,
            color: onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
        ),
      ],
    );
  }
}

/// Ligne d'une transaction ; ouvre son détail au tap
class TransactionTile extends StatelessWidget {
  final SenoTransaction transaction;

  const TransactionTile({super.key, required this.transaction});

  /// Envoi vers un de ses propres comptes (libellé = son pseudo)
  static bool isSelf(SenoTransaction tx) {
    final mine = SupabaseService.peekLockProfile()?.pseudo?.toLowerCase();
    return !tx.isReceived && mine != null && tx.label.toLowerCase() == mine;
  }

  /// Nom de la boutique, sinon nom du répertoire si l'autre partie est un
  /// contact (par numéro ou pseudo Seno), sinon « Nom Prénoms » Seno
  static String? contactName(SenoTransaction tx) {
    if (tx.merchantName case final shop?) return shop;
    final isPhone = RegExp(r'^[\d ]+$').hasMatch(tx.label);
    return _phoneContactName(tx, isPhone) ?? tx.personName;
  }

  static String? _phoneContactName(SenoTransaction tx, bool isPhone) {
    return RecentsStore.contactName(
      (
        value: tx.label,
        avatarUrl: null,
        // Numéro complet seulement (un numéro masqué ne peut pas correspondre)
        phone: isPhone && RegExp(r'^\d{10}$').hasMatch(tx.numero)
            ? tx.numero
            : null,
      ),
      RecentsStore.phoneContacts.value,
      RecentsStore.senoAccounts.value,
    );
  }

  /// 25000 → « 25 000 »
  static String formatAmount(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final tx = transaction;
    // Envoi à soi-même : « Moi-même » à la place du nom
    final name = isSelf(tx) ? context.tr('send_myself') : contactName(tx);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final String subtitle;
    if (tx.isRefunded) {
      subtitle = context.tr('tx_refunded');
    } else if (tx.isFailed) {
      subtitle = context.tr('tx_failed');
    } else if (tx.isPending) {
      subtitle = context.tr('tx_pending');
    } else {
      subtitle = context.tr(tx.isReceived ? 'tx_received_from' : 'tx_sent_to');
    }
    final amount =
        '${tx.isReceived ? '+' : '-'} ${formatAmount(tx.montant)} FCFA';
    String two(int n) => n.toString().padLeft(2, '0');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TransactionDetailsScreen(
            transaction: tx,
            contactName: name,
          ),
        ),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              UserAvatar(
                pseudo: name ?? tx.label,
                avatarUrl: tx.avatarUrl,
                merchantCategory: tx.merchantCategory,
                radius: 24,
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.white,
              ),
              // Sens de la transaction : flèche sortante / entrante
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: tx.isReceived ? AppColors.success : Colors.black,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      width: 2,
                    ),
                  ),
                  child: HugeIcon(
                    icon: tx.isReceived
                        ? HugeIcons.strokeRoundedArrowDownLeft01
                        : HugeIcons.strokeRoundedArrowUpRight01,
                    size: 10,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name ?? tx.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$subtitle · ${two(tx.createdAt.hour)}:${two(tx.createdAt.minute)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tx.isFailed
                            ? Colors.redAccent
                            : onSurface.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                ),
              ],
            ),
          ),
          Text(
            amount,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: tx.isFailed || tx.isRefunded
                      ? onSurface.withValues(alpha: 0.35)
                      : tx.isReceived
                          ? AppColors.success
                          : onSurface,
                  decoration: tx.isFailed || tx.isRefunded
                      ? TextDecoration.lineThrough
                      : null,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
          ),
        ],
      ),
    );
  }
}
