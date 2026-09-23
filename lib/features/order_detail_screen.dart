import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/auth_controller.dart';
import '../core/models.dart';
import '../ui/common.dart';

const _orderEvents = ['OrderCreated', 'OrderUpdated', 'OrderItemAdded', 'OrderItemUpdated', 'OrderItemRemoved', 'OrderCancelled'];

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId});
  final String orderId;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  int _version = 0;
  bool _busy = false;
  final _unsubscribes = <void Function()>[];

  @override
  void initState() {
    super.initState();
    // Kitchen/bar marking this order Preparing/Ready shows up here immediately, with no pull-to-refresh needed.
    for (final type in _orderEvents) {
      _unsubscribes.add(context.signalr.on(type, (e) { if (e.entityId == widget.orderId && mounted) _refresh(); }));
    }
  }

  @override
  void dispose() {
    for (final off in _unsubscribes) {
      off();
    }
    super.dispose();
  }

  void _refresh() => setState(() => _version++);

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) context.toastError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askReason(String title, {bool required = false}) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, decoration: InputDecoration(labelText: required ? 'Reason' : 'Reason (optional)')),
        actions: [
          TextButton(onPressed: () => ctx.pop(), child: const Text('Back')),
          FilledButton(onPressed: () => required && c.text.trim().isEmpty ? null : ctx.pop(c.text.trim()), child: const Text('Confirm')),
        ],
      ),
    );
  }

  Future<void> _post(String path, String message, [Object? body]) => _run(() async {
        await context.api.post(path, body ?? const {});
        if (mounted) context.toast(message);
        _refresh();
      });

  Future<void> _cancelLine(Order o, OrderLine l) async {
    final reason = await _askReason('Cancel ${l.itemName}?');
    if (reason == null) return;
    await _post('orders/${o.id}/items/${l.id}/cancel', 'Item cancelled', {'reason': reason.isEmpty ? null : reason});
  }

  Future<void> _changeQty(Order o, OrderLine l, int qty) async {
    if (qty < 1) return;
    await _run(() async {
      await context.api.put('orders/${o.id}/items/${l.id}', {'quantity': qty, 'notes': l.notes});
      _refresh();
    });
  }

  Future<void> _cancelOrder(Order o) async {
    final reason = await _askReason('Cancel order ${o.orderNo}?', required: true);
    if (reason == null || reason.isEmpty) return;
    await _post('orders/${o.id}/cancel', 'Order cancelled', {'reason': reason});
  }

  Future<void> _billAndPay(Order o) => _run(() async {
        final api = context.api;
        final billJson = o.billId != null ? await api.get('billing/${o.billId}') : await api.post('billing/orders/${o.id}/generate');
        final bill = Bill.fromJson(billJson as Map<String, dynamic>);
        final methods = (await api.get('payments/methods') as List).whereType<Map<String, dynamic>>().map(PaymentMethod.fromJson).toList();
        if (!mounted) return;
        final paid = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => PaymentSheet(bill: bill, methods: methods),
        );
        if (paid == true && mounted) context.toast('Payment received');
        _refresh();
      });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Order')),
      body: AsyncBody<Order>(
        key: ValueKey(_version),
        load: () async => Order.fromJson((await context.api.get('orders/${widget.orderId}')) as Map<String, dynamic>),
        builder: (context, o, reload) {
          final theme = Theme.of(context);
          final editable = o.isOpen;
          return Column(children: [
            Expanded(
              child: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
                ListTile(
                  title: Text(o.orderNo, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  subtitle: Text([if (o.tableCode != null) 'Table ${o.tableCode}' else o.orderType, if (o.customerName != null) o.customerName!].join(' · ')),
                  trailing: StatusChip(o.status),
                ),
                const Divider(height: 1),
                if (o.liveLines.isEmpty) const Padding(padding: EdgeInsets.all(32), child: EmptyView(icon: Icons.shopping_cart_outlined, title: 'No items yet')),
                for (final l in o.lines.where((l) => !l.isCancelled))
                  _LineTile(
                    line: l,
                    canEdit: editable && auth.can('Order.Update'),
                    onQty: (q) => _changeQty(o, l, q),
                    onCancel: () => _cancelLine(o, l),
                  ),
                const Divider(height: 24),
                _Totals(order: o),
              ]),
            ),
            if (editable) _Actions(order: o, busy: _busy, onSend: () => _post('orders/${o.id}/send', 'Sent to kitchen'), onServe: () => _post('orders/${o.id}/serve', 'Marked served'), onPay: () => _billAndPay(o), onCancel: () => _cancelOrder(o), onAdd: () {
              final allBar = o.liveLines.isNotEmpty && o.liveLines.every((l) => l.serviceArea == 'Bar');
              if (o.tableId != null) {
                context.push('/table/${o.tableId}?code=${Uri.encodeComponent(o.tableCode ?? '')}').then((_) => _refresh());
              } else {
                context.go(allBar ? '/bar?order=${o.id}' : '/pos?order=${o.id}');
              }
            }),
          ]);
        },
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line, required this.canEdit, required this.onQty, required this.onCancel});
  final OrderLine line;
  final bool canEdit;
  final ValueChanged<int> onQty;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final detail = [if (line.variantName != null) line.variantName!, ...line.addons.map((a) => '+ $a'), if (line.notes != null && line.notes!.isNotEmpty) '“${line.notes}”'].join(' · ');
    return ListTile(
      title: Row(children: [Expanded(child: Text('${line.itemName} × ${line.quantity}', style: const TextStyle(fontWeight: FontWeight.w600))), StatusChip(line.status)]),
      subtitle: detail.isEmpty ? null : Text(detail),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text(context.money(line.lineSubtotal), style: const TextStyle(fontWeight: FontWeight.w600))]),
      onTap: canEdit
          ? () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (ctx) => SafeArea(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(line.itemName, style: Theme.of(ctx).textTheme.titleMedium),
                    if (line.isDraft) Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        IconButton.filledTonal(tooltip: 'Fewer', onPressed: line.quantity > 1 ? () { ctx.pop(); onQty(line.quantity - 1); } : null, icon: const Icon(Icons.remove)),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text('${line.quantity}', style: Theme.of(ctx).textTheme.headlineSmall)),
                        IconButton.filledTonal(tooltip: 'More', onPressed: () { ctx.pop(); onQty(line.quantity + 1); }, icon: const Icon(Icons.add)),
                      ]),
                    ),
                    ListTile(leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error), title: const Text('Cancel this item'), onTap: () { ctx.pop(); onCancel(); }),
                  ]),
                ),
              )
          : null,
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, double v, {bool bold = false, bool show = true}) => !show
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(label, style: bold ? const TextStyle(fontWeight: FontWeight.w800, fontSize: 18) : null),
              Text(context.money(v), style: bold ? const TextStyle(fontWeight: FontWeight.w800, fontSize: 18) : null),
            ]),
          );
    return Column(children: [
      row('Subtotal', order.subtotal),
      row('Discount', -order.discountAmount, show: order.discountAmount > 0),
      row('Service charge', order.serviceChargeAmount, show: order.serviceChargeAmount > 0),
      row('Tax', order.taxAmount, show: order.taxAmount > 0),
      row('Round off', order.roundOff, show: order.roundOff != 0),
      const SizedBox(height: 4),
      row('Total', order.grandTotal, bold: true),
    ]);
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.order, required this.busy, required this.onSend, required this.onServe, required this.onPay, required this.onCancel, required this.onAdd});
  final Order order;
  final bool busy;
  final VoidCallback onSend, onServe, onPay, onCancel, onAdd;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final live = order.liveLines;
    final children = <Widget>[
      if (auth.can('Order.Create')) OutlinedButton.icon(onPressed: busy ? null : onAdd, icon: const Icon(Icons.add), label: const Text('Add items')),
      if (order.hasDraft && auth.can('Order.Create')) FilledButton.icon(onPressed: busy ? null : onSend, icon: const Icon(Icons.send_outlined), label: const Text('Send to kitchen')),
      if (order.status == 'Ready' && auth.can('Order.Update')) FilledButton.tonalIcon(onPressed: busy ? null : onServe, icon: const Icon(Icons.room_service_outlined), label: const Text('Mark served')),
      if (live.isNotEmpty && !order.hasDraft && auth.can('Payment.Create')) FilledButton.icon(onPressed: busy ? null : onPay, icon: const Icon(Icons.payments_outlined), label: const Text('Bill & pay')),
      if (auth.can('Order.Cancel')) TextButton.icon(onPressed: busy ? null : onCancel, style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error), icon: const Icon(Icons.close), label: const Text('Cancel order')),
    ];
    if (children.isEmpty) return const SizedBox.shrink();
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: children)),
      ),
    );
  }
}

/// Collects tender lines (single or split). Amounts are validated by the server, which owns all totals.
class PaymentSheet extends StatefulWidget {
  const PaymentSheet({super.key, required this.bill, required this.methods});
  final Bill bill;
  final List<PaymentMethod> methods;

  @override
  State<PaymentSheet> createState() => _PaymentSheetState();
}

class _Tender {
  _Tender(this.methodId, String amount) : amount = TextEditingController(text: amount);
  String methodId;
  final TextEditingController amount;
  final TextEditingController reference = TextEditingController();
}

class _PaymentSheetState extends State<PaymentSheet> {
  late final List<_Tender> _rows = [_Tender(widget.methods.first.id, widget.bill.dueAmount.toStringAsFixed(2))];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final r in _rows) {
      r.amount.dispose();
      r.reference.dispose();
    }
    super.dispose();
  }

  double get _entered => _rows.fold(0, (s, r) => s + (double.tryParse(r.amount.text) ?? 0));

  Future<void> _pay() async {
    final lines = [
      for (final r in _rows)
        if ((double.tryParse(r.amount.text) ?? 0) > 0) {'paymentMethodId': r.methodId, 'amount': double.parse(r.amount.text), 'reference': r.reference.text.trim().isEmpty ? null : r.reference.text.trim()},
    ];
    if (lines.isEmpty) {
      setState(() => _error = 'Enter an amount to collect.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await context.api.post('payments/bills/${widget.bill.id}', {'payments': lines});
      if (mounted) context.pop(true);
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bill;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Bill ${b.billNo}', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Amount due'), Text(context.money(b.dueAmount), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))]),
          for (final t in b.taxBreakdown) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('${t.name} (${t.ratePercent}%)', style: theme.textTheme.bodySmall), Text(context.money(t.amount), style: theme.textTheme.bodySmall)]),
          const Divider(height: 24),
          for (var i = 0; i < _rows.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  flex: 5,
                  child: DropdownButtonFormField<String>(
                    initialValue: _rows[i].methodId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Method'),
                    items: [for (final m in widget.methods) DropdownMenuItem(value: m.id, child: Text(m.name))],
                    onChanged: (v) => setState(() => _rows[i].methodId = v ?? _rows[i].methodId),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(flex: 4, child: TextField(controller: _rows[i].amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount'), onChanged: (_) => setState(() {}))),
                if (_rows.length > 1) IconButton(tooltip: 'Remove', onPressed: () => setState(() => _rows.removeAt(i)), icon: const Icon(Icons.close)),
              ]),
            ),
          if (widget.methods.length > 1) Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => setState(() => _rows.add(_Tender(widget.methods[(_rows.length) % widget.methods.length].id, ''))), icon: const Icon(Icons.call_split), label: const Text('Split payment'))),
          Text('Collecting ${context.money(_entered)} of ${context.money(b.dueAmount)}', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
          const SizedBox(height: 12),
          FilledButton(onPressed: _busy ? null : _pay, child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Collect payment')),
        ]),
      ),
    );
  }
}
