import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/auth_controller.dart';
import '../core/models.dart';
import '../ui/common.dart';

class TablesScreen extends StatelessWidget {
  const TablesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.api;
    final canOrder = context.watch<AuthController>().can('Order.Create');

    return AsyncBody<(List<FloorLayout>, TableSummary)>(
      load: () async {
        final layout = (await api.get('tables/layout') as List).whereType<Map<String, dynamic>>().map(FloorLayout.fromJson).toList();
        final summary = TableSummary.fromJson((await api.get('tables/summary')) as Map<String, dynamic>);
        return (layout, summary);
      },
      isEmpty: (d) => d.$1.every((f) => f.tables.isEmpty),
      emptyIcon: Icons.table_restaurant_outlined,
      emptyTitle: 'No tables set up',
      emptyHint: 'Add floors and tables from the web app.',
      builder: (context, data, reload) {
        final (floors, s) = data;
        return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              _Legend('Available', s.available), _Legend('Occupied', s.occupied), _Legend('Reserved', s.reserved), _Legend('Cleaning', s.cleaning),
            ]),
          ),
          for (final f in floors.where((f) => f.tables.isNotEmpty)) ...[
            SectionTitle(f.name),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 120, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1),
                itemCount: f.tables.length,
                itemBuilder: (context, i) => _TableTile(table: f.tables[i], onTap: () => _open(context, f.tables[i], canOrder, reload)),
              ),
            ),
          ],
        ]);
      },
    );
  }

  Future<void> _open(BuildContext context, DiningTable t, bool canOrder, Future<void> Function() reload) async {
    if (t.status == 'Blocked') {
      context.toast('${t.code} is blocked.');
      return;
    }
    if (!canOrder) {
      context.toast('${t.code} · ${t.status} · seats ${t.capacity}');
      return;
    }
    await context.push('/table/${t.id}?code=${Uri.encodeComponent(t.code)}');
    if (context.mounted) await reload();
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.status, this.count);
  final String status;
  final int count;

  @override
  Widget build(BuildContext context) => Chip(
        avatar: CircleAvatar(radius: 6, backgroundColor: StatusChip.colorFor(status, Theme.of(context).colorScheme)),
        label: Text('$status $count'),
        visualDensity: VisualDensity.compact,
      );
}

class _TableTile extends StatelessWidget {
  const _TableTile({required this.table, required this.onTap});
  final DiningTable table;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = StatusChip.colorFor(table.status, Theme.of(context).colorScheme);
    return Semantics(
      button: true,
      label: 'Table ${table.code}, ${table.status}, seats ${table.capacity}',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.5))),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(table.code, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.person_outline, size: 14, color: color), Text('${table.capacity}', style: TextStyle(color: color, fontSize: 12))]),
            const SizedBox(height: 2),
            Text(table.status, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}
