import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/auth_controller.dart';
import '../core/models.dart';
import '../ui/common.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _items = <Customer>[];
  String _search = '';
  int _page = 1;
  int _totalPages = 1;
  bool _loading = true;
  bool _more = false;
  Object? _error;
  Timer? _debounce;
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
    _debounce?.cancel();
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
      final data = Paged.from(await context.api.get('customers', query: {'page': page, 'pageSize': 20, 'search': _search}), Customer.fromJson);
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

  Future<void> _create() async {
    final created = await showDialog<bool>(context: context, builder: (_) => const _CustomerDialog());
    if (created == true && mounted) {
      context.toast('Customer added');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = context.watch<AuthController>().can('Customer.Create');
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canCreate ? FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.person_add_alt), label: const Text('Add')) : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: SearchBar(
            hintText: 'Search name or phone',
            leading: const Icon(Icons.search),
            elevation: const WidgetStatePropertyAll(0),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 350), () { _search = v.trim(); _load(); });
            },
          ),
        ),
        Expanded(child: _body(context)),
      ]),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorView(message: _error is ApiException ? (_error as ApiException).message : 'Could not load customers.', onRetry: _load);
    if (_items.isEmpty) return const EmptyView(icon: Icons.groups_outlined, title: 'No customers found');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: _items.length + (_more ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i >= _items.length) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
          final c = _items[i];
          return ListTile(
            leading: CircleAvatar(child: Text(c.fullName.isEmpty ? '?' : c.fullName[0].toUpperCase())),
            title: Text(c.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text([if (c.phone != null) c.phone!, if (c.email != null) c.email!].join(' · ')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/customer/${c.id}'),
          );
        },
      ),
    );
  }
}

class _CustomerDialog extends StatefulWidget {
  const _CustomerDialog();

  @override
  State<_CustomerDialog> createState() => _CustomerDialogState();
}

class _CustomerDialogState extends State<_CustomerDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      await context.api.post('customers', {
        'fullName': _name.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'birthday': null,
        'anniversary': null,
        'notes': null,
      });
      if (mounted) context.pop(true);
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('New customer'),
        content: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full name'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null),
            const SizedBox(height: 12),
            TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
            const SizedBox(height: 12),
            TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email'), validator: (v) => (v != null && v.trim().isNotEmpty && !v.contains('@')) ? 'Enter a valid email' : null),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          ]),
        ),
        actions: [
          TextButton(onPressed: _busy ? null : () => context.pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
        ],
      );
}

class CustomerDetailScreen extends StatelessWidget {
  const CustomerDetailScreen({super.key, required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customer')),
      body: AsyncBody<CustomerProfile>(
        load: () async => CustomerProfile.fromJson(await context.api.get('customers/$customerId/profile') as Map<String, dynamic>),
        builder: (context, p, reload) {
          final theme = Theme.of(context);
          return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            ListTile(
              leading: CircleAvatar(radius: 26, child: Text(p.customer.fullName.isEmpty ? '?' : p.customer.fullName[0].toUpperCase())),
              title: Text(p.customer.fullName, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              subtitle: Text([if (p.customer.phone != null) p.customer.phone!, if (p.customer.email != null) p.customer.email!].join('\n')),
              isThreeLine: p.customer.phone != null && p.customer.email != null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(child: _Stat('Visits', '${p.totalVisits}')),
                Expanded(child: _Stat('Total spend', context.money(p.totalSpend))),
                Expanded(child: _Stat('Avg order', context.money(p.averageOrderValue))),
              ]),
            ),
            if (p.pointsBalance != null) ...[
              const SectionTitle('Loyalty'),
              ListTile(leading: const Icon(Icons.loyalty_outlined), title: Text('${p.pointsBalance} points'), subtitle: p.tierName == null ? null : Text('${p.tierName} tier')),
            ],
            if (p.favoriteItems.isNotEmpty) ...[
              const SectionTitle('Favourites'),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Wrap(spacing: 8, runSpacing: 8, children: [for (final f in p.favoriteItems) Chip(label: Text(f))])),
            ],
            if (p.customer.notes != null && p.customer.notes!.isNotEmpty) ...[const SectionTitle('Notes'), Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(p.customer.notes!))],
            const SectionTitle('Recent orders'),
            if (p.recentOrders.isEmpty) const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('No orders yet'))
            else for (final o in p.recentOrders)
              ListTile(
                title: Text(o.orderNo),
                subtitle: Text(o.createdAt == null ? '' : DateFormat('d MMM y, h:mm a').format(o.createdAt!)),
                trailing: Text(context.money(o.grandTotal), style: const TextStyle(fontWeight: FontWeight.w600)),
                onTap: () => context.push('/order/${o.id}'),
              ),
          ]);
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(children: [
            FittedBox(child: Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
          ]),
        ),
      );
}
