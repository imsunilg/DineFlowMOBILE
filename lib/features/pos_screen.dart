import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../ui/common.dart';

const _menuEvents = ['MenuUpdated', 'MenuPriceChanged', 'MenuAvailabilityChanged'];

/// Take an order: by table (dine-in), or at the counter (takeaway / delivery). [area] limits the menu to
/// one service area (the Bar screen passes 'Bar'). Pricing, tax and stock are all handled by the API.
class PosScreen extends StatefulWidget {
  const PosScreen({super.key, this.tableId, this.tableCode, this.area, this.orderId});
  final String? tableId;
  final String? tableCode;
  final String? area;
  final String? orderId;

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  List<MenuCategory> _categories = [];
  Order? _order;
  String? _categoryId;
  String _query = '';
  String _orderType = 'Takeaway';
  bool _loading = true;
  bool _busy = false;
  Object? _error;

  bool get _isTable => widget.tableId != null;

  Timer? _menuDebounce;
  final List<VoidCallback> _menuUnsubscribes = [];

  @override
  void initState() {
    super.initState();
    _load();
    final signalr = context.signalr;
    void bump() {
      _menuDebounce?.cancel();
      _menuDebounce = Timer(const Duration(milliseconds: 400), () { if (mounted) _load(); });
    }
    for (final type in _menuEvents) {
      _menuUnsubscribes.add(signalr.on(type, (_) => bump()));
    }
    _menuUnsubscribes.add(signalr.onReconnected(bump));
  }

  @override
  void dispose() {
    _menuDebounce?.cancel();
    for (final u in _menuUnsubscribes) {
      u();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api = context.api;
      final tree = await api.get('menu', query: {'onlyAvailable': true}) as List;
      final cats = <MenuCategory>[
        for (final menu in tree.whereType<Map<String, dynamic>>())
          for (final c in (menu['categories'] as List? ?? const []).whereType<Map<String, dynamic>>()) MenuCategory.fromJson(c),
      ].where((c) => c.items.isNotEmpty && (widget.area == null || c.serviceArea == widget.area)).toList();

      Order? order;
      if (widget.orderId != null) {
        order = Order.fromJson(await api.get('orders/${widget.orderId}') as Map<String, dynamic>);
      } else if (_isTable) {
        final existing = await api.get('orders/by-table/${widget.tableId}');
        if (existing is Map<String, dynamic>) order = Order.fromJson(existing);
      }
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _order = order != null && order.isOpen ? order : null;
        _categoryId = cats.isEmpty ? null : cats.first.id;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  Future<void> _add(MenuItem item, {String? variantId, List<String> addonIds = const [], int quantity = 1, String? notes}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final api = context.api;
      var order = _order;
      if (order == null) {
        order = Order.fromJson(await api.post('orders', {'orderType': _isTable ? 'DineIn' : _orderType, 'tableId': widget.tableId, 'customerId': null, 'notes': null}) as Map<String, dynamic>);
        // Remember the new order at once so a failed first add does not leave a second empty order behind on retry.
        if (mounted) setState(() => _order = order);
      }
      final updated = await api.post('orders/${order.id}/items', {'menuItemId': item.id, 'variantId': variantId, 'addonIds': addonIds, 'quantity': quantity, 'notes': notes});
      if (!mounted) return;
      setState(() => _order = Order.fromJson(updated as Map<String, dynamic>));
      context.toast('Added ${item.name}');
    } catch (e) {
      if (mounted) context.toastError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(MenuItem item) async {
    if (item.variants.isEmpty && item.addons.isEmpty) return _add(item);
    final choice = await showModalBottomSheet<_Choice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ItemSheet(item: item),
    );
    if (choice != null) await _add(item, variantId: choice.variantId, addonIds: choice.addonIds, quantity: choice.quantity, notes: choice.notes);
  }

  @override
  Widget build(BuildContext context) {
    final title = _isTable ? 'Table ${widget.tableCode ?? ''}' : (widget.area == 'Bar' ? 'Bar order' : 'New order');
    final body = _body(context);
    // Table orders open full-screen (no shell); the counter screens live inside the shell and already have an app bar.
    return _isTable ? Scaffold(appBar: AppBar(title: Text(title)), body: body) : body;
  }

  Widget _body(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorView(message: _error is ApiException ? (_error as ApiException).message : 'Could not load the menu.', onRetry: _load);
    if (_categories.isEmpty) return const EmptyView(icon: Icons.restaurant_menu, title: 'No menu items available', hint: 'Add items to the menu from the web app.');

    final q = _query.trim().toLowerCase();
    final items = q.isNotEmpty
        ? [for (final c in _categories) ...c.items.where((i) => i.name.toLowerCase().contains(q))]
        : (_categories.firstWhere((c) => c.id == _categoryId, orElse: () => _categories.first)).items;

    return Column(children: [
      if (!_isTable && _order == null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'Takeaway', label: Text('Takeaway'), icon: Icon(Icons.takeout_dining)), ButtonSegment(value: 'Delivery', label: Text('Delivery'), icon: Icon(Icons.delivery_dining))],
            selected: {_orderType},
            onSelectionChanged: (s) => setState(() => _orderType = s.first),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: SearchBar(hintText: 'Search menu', leading: const Icon(Icons.search), elevation: const WidgetStatePropertyAll(0), onChanged: (v) => setState(() => _query = v)),
      ),
      if (q.isEmpty)
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
            for (final c in _categories)
              Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(c.name), selected: (_categoryId ?? _categories.first.id) == c.id, onSelected: (_) => setState(() => _categoryId = c.id))),
          ]),
        ),
      Expanded(
        child: items.isEmpty
            ? const EmptyView(icon: Icons.search_off, title: 'No matching items')
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 90),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => _ItemTile(item: items[i], busy: _busy, onTap: () => _pick(items[i])),
              ),
      ),
      if (_order != null && _order!.liveLines.isNotEmpty) _CartBar(order: _order!, onReview: () async {
        await context.push('/order/${_order!.id}');
        if (mounted) _load();
      }),
    ]);
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.busy, required this.onTap});
  final MenuItem item;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final from = item.variants.isEmpty ? item.basePrice : item.variants.map((v) => v.price).reduce((a, b) => a < b ? a : b);
    final needsChoice = item.variants.isNotEmpty || item.addons.isNotEmpty;
    return ListTile(
      enabled: !busy,
      leading: Icon(Icons.circle, size: 14, color: item.isVeg ? Colors.green : Colors.red.shade700, semanticLabel: item.isVeg ? 'Vegetarian' : 'Non-vegetarian'),
      title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(item.variants.isEmpty ? context.money(item.basePrice) : 'from ${context.money(from)}'),
      trailing: needsChoice ? const Icon(Icons.tune) : const Icon(Icons.add_circle_outline),
      onTap: onTap,
    );
  }
}

class _CartBar extends StatelessWidget {
  const _CartBar({required this.order, required this.onReview});
  final Order order;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final count = order.liveLines.fold<int>(0, (s, l) => s + l.quantity);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: onReview,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Icon(Icons.shopping_bag_outlined, color: scheme.onPrimaryContainer),
              const SizedBox(width: 10),
              Expanded(child: Text('$count item${count == 1 ? '' : 's'} · ${order.orderNo}', style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600))),
              Text(context.money(order.grandTotal), style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: scheme.onPrimaryContainer),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Choice {
  _Choice(this.variantId, this.addonIds, this.quantity, this.notes);
  final String? variantId;
  final List<String> addonIds;
  final int quantity;
  final String? notes;
}

class _ItemSheet extends StatefulWidget {
  const _ItemSheet({required this.item});
  final MenuItem item;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  String? _variant;
  final _addons = <String>{};
  int _qty = 1;
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.item.variants.isNotEmpty) _variant = widget.item.variants.first.id;
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(item.name, style: theme.textTheme.titleLarge),
          if (item.variants.isNotEmpty) ...[
            const SectionTitle('Size / variant'),
            RadioGroup<String>(
              groupValue: _variant,
              onChanged: (v) => setState(() => _variant = v),
              child: Column(children: [for (final v in item.variants) RadioListTile<String>(dense: true, value: v.id, title: Text(v.name), secondary: Text(context.money(v.price)))]),
            ),
          ],
          if (item.addons.isNotEmpty) ...[
            const SectionTitle('Add-ons'),
            for (final a in item.addons)
              CheckboxListTile(dense: true, value: _addons.contains(a.id), title: Text(a.name), secondary: Text('+${context.money(a.price)}'), onChanged: (on) => setState(() => on == true ? _addons.add(a.id) : _addons.remove(a.id))),
          ],
          const SizedBox(height: 8),
          TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Note for the kitchen (optional)')),
          const SizedBox(height: 12),
          Row(children: [
            IconButton.filledTonal(tooltip: 'Fewer', onPressed: _qty > 1 ? () => setState(() => _qty--) : null, icon: const Icon(Icons.remove)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('$_qty', style: theme.textTheme.titleLarge)),
            IconButton.filledTonal(tooltip: 'More', onPressed: () => setState(() => _qty++), icon: const Icon(Icons.add)),
            const SizedBox(width: 16),
            Expanded(
              child: FilledButton(
                onPressed: () => context.pop(_Choice(_variant, _addons.toList(), _qty, _notes.text.trim().isEmpty ? null : _notes.text.trim())),
                child: const Text('Add to order'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
