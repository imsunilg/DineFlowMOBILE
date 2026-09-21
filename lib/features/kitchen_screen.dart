import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/auth_controller.dart';
import '../core/models.dart';
import '../ui/common.dart';

/// Kitchen display: live tickets per station. Advancing an item moves it along New -> Preparing -> Ready -> Served;
/// the API decides what is allowed and rolls the order status up.
class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key});

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

const _next = {'New': 'Preparing', 'Accepted': 'Preparing', 'Preparing': 'Ready', 'Ready': 'Served'};

class _KitchenScreenState extends State<KitchenScreen> {
  List<String> _stations = [];
  String? _station;
  List<KitchenTicket> _tickets = [];
  bool _loading = true;
  String? _error;
  bool _busy = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _init();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final s = await context.api.get('kitchen/stations') as List;
      if (mounted) setState(() => _stations = s.map((e) => '$e').toList());
    } catch (_) {}
    await _refresh();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final t = await context.api.get('kitchen/tickets', query: {'station': _station}) as List;
      if (!mounted) return;
      setState(() { _tickets = t.whereType<Map<String, dynamic>>().map(KitchenTicket.fromJson).toList(); _loading = false; _error = null; });
    } catch (e) {
      if (!mounted) return;
      if (!silent) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _advance(KitchenItem item) async {
    final next = _next[item.status];
    if (next == null || _busy) return;
    setState(() => _busy = true);
    try {
      await context.api.patch('kitchen/items/${item.id}/status', {'status': next});
      await _refresh(silent: true);
    } catch (e) {
      if (mounted) context.toastError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canUpdate = context.watch<AuthController>().can('Kitchen.Update');
    return Column(children: [
      if (_stations.isNotEmpty)
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
            Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: const Text('All stations'), selected: _station == null, onSelected: (_) { _station = null; _refresh(); })),
            for (final s in _stations) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(s), selected: _station == s, onSelected: (_) { _station = s; _refresh(); })),
          ]),
        ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ErrorView(message: _error!, onRetry: _refresh)
                : _tickets.isEmpty
                    ? const EmptyView(icon: Icons.soup_kitchen_outlined, title: 'No active tickets', hint: 'New orders appear here automatically.')
                    : RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                          itemCount: _tickets.length,
                          itemBuilder: (context, i) => _TicketCard(ticket: _tickets[i], canUpdate: canUpdate && !_busy, onAdvance: _advance),
                        ),
                      ),
      ),
    ]);
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket, required this.canUpdate, required this.onAdvance});
  final KitchenTicket ticket;
  final bool canUpdate;
  final ValueChanged<KitchenItem> onAdvance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(ticket.orderNo, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Text(ticket.tableCode != null ? 'Table ${ticket.tableCode}' : ticket.orderType, style: theme.textTheme.bodyMedium),
            const Spacer(),
            Text(timeAgo(ticket.sentAt), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
          ]),
          const Divider(height: 20),
          for (final item in ticket.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${item.quantity} × ${item.name}${item.variantName != null ? ' (${item.variantName})' : ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (item.addons.isNotEmpty) Text(item.addons.map((a) => '+ $a').join(', '), style: theme.textTheme.bodySmall),
                    if (item.notes != null && item.notes!.isNotEmpty) Text('“${item.notes}”', style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic, color: theme.colorScheme.tertiary)),
                  ]),
                ),
                const SizedBox(width: 8),
                if (canUpdate && _next.containsKey(item.status))
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 12)),
                    onPressed: () => onAdvance(item),
                    child: Text(_next[item.status] == 'Served' ? 'Serve' : _next[item.status]!),
                  )
                else
                  StatusChip(item.status),
              ]),
            ),
        ]),
      ),
    );
  }
}
