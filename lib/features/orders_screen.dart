import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../ui/common.dart';

const _filters = <(String, String?)>[('All', null), ('Draft', 'Draft'), ('Confirmed', 'Confirmed'), ('Preparing', 'Preparing'), ('Ready', 'Ready'), ('Served', 'Served'), ('Completed', 'Completed'), ('Cancelled', 'Cancelled')];

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _items = <OrderSummary>[];
  String? _status;
  int _page = 1;
  int _totalPages = 1;
  bool _loading = true;
  bool _more = false;
  Object? _error;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200 && !_more && !_loading && _page < _totalPages) _load(page: _page + 1);
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({int page = 1}) async {
    setState(() {
      if (page == 1) {
        _loading = true;
        _error = null;
      } else {
        _more = true;
      }
    });
    try {
      final data = Paged.from(await context.api.get('orders', query: {'page': page, 'pageSize': 20, 'status': _status}), OrderSummary.fromJson);
      if (!mounted) return;
      setState(() {
        if (page == 1) _items.clear();
        _items.addAll(data.items);
        _page = page;
        _totalPages = data.totalPages;
      });
    } catch (e) {
      if (!mounted) return;
      if (page == 1) {
        setState(() => _error = e);
      } else {
        context.toastError(e);
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _more = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        height: 52,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
          for (final f in _filters)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(label: Text(f.$1), selected: _status == f.$2, onSelected: (_) { _status = f.$2; _load(); }),
            ),
        ]),
      ),
      Expanded(child: _body(context)),
    ]);
  }

  Widget _body(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorView(message: _error is ApiException ? (_error as ApiException).message : 'Could not load orders.', onRetry: _load);
    if (_items.isEmpty) return const EmptyView(icon: Icons.receipt_long_outlined, title: 'No orders found');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _items.length + (_more ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i >= _items.length) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
          final o = _items[i];
          return ListTile(
            title: Row(children: [Text(o.orderNo, style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(width: 8), StatusChip(o.status)]),
            subtitle: Text([if (o.tableCode != null) 'Table ${o.tableCode}' else o.orderType, if (o.customerName != null) o.customerName!, '${o.itemCount} item(s)', if (o.createdAt != null) DateFormat('d MMM, h:mm a').format(o.createdAt!)].join(' · ')),
            trailing: Text(context.money(o.grandTotal), style: const TextStyle(fontWeight: FontWeight.w700)),
            onTap: () async {
              await context.push('/order/${o.id}');
              if (mounted) _load();
            },
          );
        },
      ),
    );
  }
}
