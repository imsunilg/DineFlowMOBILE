import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/auth_controller.dart';
import '../core/models.dart';
import '../ui/common.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.api;
    final user = context.watch<AuthController>().user;

    return AsyncBody<Dashboard>(
      load: () async => Dashboard.fromJson((await api.get('reports/dashboard')) as Map<String, dynamic>),
      builder: (context, d, reload) {
        final theme = Theme.of(context);
        return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Hello, ${user?.firstName ?? 'there'}', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.7,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: [
                _Kpi('Sales today', context.money(d.salesToday), Icons.payments_outlined),
                _Kpi('Orders today', '${d.ordersToday}', Icons.receipt_long_outlined, hint: '${d.pendingOrders} in progress'),
                _Kpi('Customers', '${d.customersToday}', Icons.groups_outlined),
                _Kpi('Stock alerts', '${d.inventoryAlerts}', Icons.warning_amber_outlined, warn: d.inventoryAlerts > 0),
              ],
            ),
          ),
          const SectionTitle('Sales, last 7 days'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(child: Padding(padding: const EdgeInsets.all(12), child: SizedBox(height: 160, child: BarChart(points: d.dailySales.length > 7 ? d.dailySales.sublist(d.dailySales.length - 7) : d.dailySales, color: theme.colorScheme.primary, labelColor: theme.colorScheme.outline)))),
          ),
          const SectionTitle('Top items'),
          if (d.topItems.isEmpty) const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('No sales yet'))
          else for (final t in d.topItems.take(5)) ListTile(dense: true, title: Text(t.$1), subtitle: Text('${t.$3} sold'), trailing: Text(context.money(t.$2), style: const TextStyle(fontWeight: FontWeight.w600))),
          if (d.lowStock.isNotEmpty) ...[
            const SectionTitle('Low stock'),
            for (final l in d.lowStock.take(5)) ListTile(dense: true, leading: Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700), title: Text(l.$1), trailing: Text('${_num(l.$2)} ${l.$3}')),
          ],
        ]);
      },
    );
  }
}

String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.icon, {this.hint, this.warn = false});
  final String label;
  final String value;
  final IconData icon;
  final String? hint;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(children: [Icon(icon, size: 18, color: warn ? Colors.orange.shade800 : t.colorScheme.primary), const SizedBox(width: 6), Expanded(child: Text(label, style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.outline), overflow: TextOverflow.ellipsis))]),
          const SizedBox(height: 4),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
          if (hint != null) Text(hint!, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
        ]),
      ),
    );
  }
}

/// Minimal column chart drawn with a CustomPainter so the app needs no charting dependency.
class BarChart extends StatelessWidget {
  const BarChart({super.key, required this.points, required this.color, required this.labelColor});
  final List<ChartPoint> points;
  final Color color;
  final Color labelColor;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Sales chart: ${points.map((p) => '${p.label} ${p.value.round()}').join(', ')}',
        child: CustomPaint(painter: _BarPainter(points, color, labelColor), size: Size.infinite),
      );
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.points, this.color, this.labelColor);
  final List<ChartPoint> points;
  final Color color;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final maxV = math.max(1.0, points.map((p) => p.value).reduce(math.max));
    const bottom = 18.0;
    final slot = size.width / points.length;
    final barW = math.min(slot * 0.6, 32.0);
    final paint = Paint()..color = color;
    for (var i = 0; i < points.length; i++) {
      final h = (points[i].value / maxV) * (size.height - bottom - 4);
      final x = i * slot + (slot - barW) / 2;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, size.height - bottom - h, barW, math.max(h, points[i].value > 0 ? 2 : 0)), const Radius.circular(4)), paint);
      final label = points[i].label.length >= 10 ? points[i].label.substring(8, 10) : points[i].label;
      final tp = TextPainter(text: TextSpan(text: label, style: TextStyle(fontSize: 10, color: labelColor)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(i * slot + (slot - tp.width) / 2, size.height - tp.height));
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => old.points != points || old.color != color;
}
