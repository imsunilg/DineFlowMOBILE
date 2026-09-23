import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../ui/common.dart';

const _inventoryEvents = ['InventoryUpdated', 'StockAdjusted', 'StockTransferred', 'StockReceived', 'StockWasted', 'LowStock'];

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  String _search = '';
  int _reloadTick = 0;
  Timer? _debounce;
  final List<VoidCallback> _unsubscribes = [];

  @override
  void initState() {
    super.initState();
    final signalr = context.signalr;
    void bump() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), () { if (mounted) setState(() => _reloadTick++); });
    }
    for (final type in _inventoryEvents) {
      _unsubscribes.add(signalr.on(type, (_) => bump()));
    }
    _unsubscribes.add(signalr.onReconnected(bump));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _debounce?.cancel();
    for (final u in _unsubscribes) {
      u();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = context.api;
    return Column(children: [
      TabBar(controller: _tabs, tabs: const [Tab(text: 'Stock'), Tab(text: 'Alerts')]),
      Expanded(
        child: TabBarView(controller: _tabs, children: [
          Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: SearchBar(hintText: 'Search items', leading: const Icon(Icons.search), elevation: const WidgetStatePropertyAll(0), onChanged: (v) => setState(() => _search = v)),
            ),
            Expanded(
              child: AsyncBody<List<InvStockRow>>(
                key: ValueKey('$_search:$_reloadTick'),
                load: () async => Paged.from(await api.get('inventory/stock', query: {'pageSize': 100, 'search': _search}), InvStockRow.fromJson).items,
                isEmpty: (d) => d.isEmpty,
                emptyIcon: Icons.inventory_2_outlined,
                emptyTitle: 'No stock items found',
                builder: (context, rows, reload) => ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    return ListTile(
                      title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${r.code} · ${r.warehouseName}'),
                      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('${_fmt(r.quantity)} ${r.unitCode}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        StatusChip(r.level),
                      ]),
                    );
                  },
                ),
              ),
            ),
          ]),
          AsyncBody<List<StockAlert>>(
            key: ValueKey(_reloadTick),
            load: () async => (await api.get('inventory/alerts') as List).whereType<Map<String, dynamic>>().map(StockAlert.fromJson).toList(),
            isEmpty: (d) => d.isEmpty,
            emptyIcon: Icons.check_circle_outline,
            emptyTitle: 'Everything is stocked',
            emptyHint: 'Items below their reorder level will appear here.',
            builder: (context, alerts, reload) => ListView.separated(
              itemCount: alerts.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final a = alerts[i];
                return ListTile(
                  leading: Icon(a.source == 'Bar' ? Icons.local_bar_outlined : Icons.warning_amber_rounded, color: Colors.orange.shade800),
                  title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${a.source} · reorder at ${_fmt(a.threshold)} ${a.unit}'),
                  trailing: Text('${_fmt(a.quantity)} ${a.unit}', style: const TextStyle(fontWeight: FontWeight.w700)),
                );
              },
            ),
          ),
        ]),
      ),
    ]);
  }
}

String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
