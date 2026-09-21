import 'package:flutter/material.dart';

import '../core/models.dart';
import '../ui/common.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  int _version = 0;

  static IconData _icon(String type) => switch (type) {
        'LowStock' => Icons.warning_amber_rounded,
        'OrderReady' => Icons.room_service_outlined,
        'PaymentReceived' => Icons.payments_outlined,
        'NewReservation' => Icons.event_available_outlined,
        'NewCustomer' => Icons.person_add_alt,
        'TierUpgrade' => Icons.workspace_premium_outlined,
        _ => Icons.notifications_outlined,
      };

  Future<void> _markAll() async {
    try {
      await context.api.post('notifications/read-all', {});
      if (mounted) setState(() => _version++);
    } catch (e) {
      if (mounted) context.toastError(e);
    }
  }

  Future<void> _open(AppNotification n) async {
    if (n.isRead) return;
    try {
      await context.api.post('notifications/${n.id}/read', {});
      if (mounted) setState(() => _version++);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final api = context.api;
    return Column(children: [
      Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: _markAll, icon: const Icon(Icons.done_all), label: const Text('Mark all read'))),
      Expanded(
        child: AsyncBody<List<AppNotification>>(
          key: ValueKey(_version),
          load: () async => Paged.from(await api.get('notifications', query: {'pageSize': 50}), AppNotification.fromJson).items,
          isEmpty: (d) => d.isEmpty,
          emptyIcon: Icons.notifications_none,
          emptyTitle: 'You are all caught up',
          emptyHint: 'Low stock, ready orders and new bookings show up here.',
          builder: (context, items, reload) => ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final n = items[i];
              return ListTile(
                tileColor: n.isRead ? null : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
                leading: Icon(_icon(n.type)),
                title: Text(n.title, style: TextStyle(fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700)),
                subtitle: Text('${n.message}\n${timeAgo(n.createdAt)}'),
                isThreeLine: true,
                onTap: () => _open(n),
              );
            },
          ),
        ),
      ),
    ]);
  }
}
