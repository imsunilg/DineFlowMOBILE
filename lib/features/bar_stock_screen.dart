import 'package:flutter/material.dart';

import '../core/models.dart';
import '../ui/common.dart';

/// Bar stock is tracked in millilitres; the API reports bottles + loose ml per product.
class BarStockScreen extends StatelessWidget {
  const BarStockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.api;
    return AsyncBody<List<BarStockRow>>(
      load: () async => (await api.get('bar/stock') as List).whereType<Map<String, dynamic>>().map(BarStockRow.fromJson).toList(),
      isEmpty: (d) => d.isEmpty,
      emptyIcon: Icons.liquor_outlined,
      emptyTitle: 'No bar stock yet',
      emptyHint: 'Receive stock from the web app to see it here.',
      builder: (context, rows, reload) {
        final low = rows.where((r) => r.isLow).length;
        final byCategory = <String, List<BarStockRow>>{};
        for (final r in rows) {
          byCategory.putIfAbsent(r.categoryName, () => []).add(r);
        }
        return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          if (low > 0)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Card(color: Theme.of(context).colorScheme.errorContainer, child: ListTile(leading: const Icon(Icons.warning_amber_rounded), title: Text('$low product${low == 1 ? '' : 's'} below reorder level'))),
            ),
          for (final e in byCategory.entries) ...[
            SectionTitle(e.key),
            for (final r in e.value)
              ListTile(
                title: Text(r.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${r.volumeMl} ml bottle'),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${r.wholeBottles} btl${r.looseMl > 0 ? ' + ${r.looseMl.round()} ml' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (r.isLow) const StatusChip('Low'),
                ]),
              ),
          ],
        ]);
      },
    );
  }
}
