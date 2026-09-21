import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/auth_controller.dart';
import '../core/models.dart';
import '../ui/common.dart';

String _dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

class ReservationsScreen extends StatefulWidget {
  const ReservationsScreen({super.key});

  @override
  State<ReservationsScreen> createState() => _ReservationsScreenState();
}

class _ReservationsScreenState extends State<ReservationsScreen> {
  DateTime _day = DateTime.now();
  int _version = 0;
  bool _busy = false;

  void _shift(int days) => setState(() { _day = _day.add(Duration(days: days)); _version++; });

  Future<List<Reservation>> _load() async {
    // Fetch a day either side and filter locally so the tenant/device time-zone difference cannot hide a booking.
    final data = Paged.from(
      await context.api.get('reservations', query: {'from': _dayKey(_day.subtract(const Duration(days: 1))), 'to': _dayKey(_day.add(const Duration(days: 1))), 'pageSize': 200}),
      Reservation.fromJson,
    );
    final key = _dayKey(_day);
    final list = data.items.where((r) => r.reservedAt != null && _dayKey(r.reservedAt!) == key).toList()..sort((a, b) => a.reservedAt!.compareTo(b.reservedAt!));
    return list;
  }

  Future<void> _setStatus(Reservation r, String status) async {
    String? reason;
    if (status == 'Cancelled') {
      reason = await _askReason();
      if (reason == null || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await context.api.post('reservations/${r.id}/status', {'status': status, 'reason': reason, 'tableId': null});
      if (mounted) context.toast('${r.guestName}: $status');
      setState(() => _version++);
    } catch (e) {
      if (mounted) context.toastError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askReason() {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel reservation'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Reason (optional)')),
        actions: [TextButton(onPressed: () => ctx.pop(), child: const Text('Back')), FilledButton(onPressed: () => ctx.pop(c.text.trim()), child: const Text('Cancel booking'))],
      ),
    );
  }

  Future<void> _create() async {
    final ok = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => _BookingSheet(day: _day));
    if (ok == true && mounted) {
      context.toast('Reservation created');
      setState(() => _version++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = context.watch<AuthController>().can('Reservation.Manage');
    final label = DateFormat('EEE, d MMM').format(_day);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canManage ? FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: const Text('Book')) : null,
      body: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(tooltip: 'Previous day', onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
          TextButton(onPressed: () => setState(() { _day = DateTime.now(); _version++; }), child: Text(_dayKey(_day) == _dayKey(DateTime.now()) ? 'Today · $label' : label)),
          IconButton(tooltip: 'Next day', onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
        ]),
        Expanded(
          child: AsyncBody<List<Reservation>>(
            key: ValueKey(_version),
            load: _load,
            isEmpty: (d) => d.isEmpty,
            emptyIcon: Icons.event_available_outlined,
            emptyTitle: 'No reservations',
            emptyHint: 'Nothing booked for this day.',
            builder: (context, items, reload) => ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final r = items[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(DateFormat('h:mm a').format(r.reservedAt!), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(r.guestName, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                        StatusChip(r.status),
                      ]),
                      const SizedBox(height: 4),
                      Text([r.reservationNo, '${r.guestCount} guest${r.guestCount == 1 ? '' : 's'}', if (r.tableCode != null) 'Table ${r.tableCode}', if (r.phone != null) r.phone!].join(' · '), style: Theme.of(context).textTheme.bodySmall),
                      if (r.specialRequest != null && r.specialRequest!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('“${r.specialRequest}”', style: const TextStyle(fontStyle: FontStyle.italic))),
                      if (canManage && r.allowedTransitions.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(spacing: 8, runSpacing: 4, children: [
                            for (final s in r.allowedTransitions)
                              (s == 'Cancelled' || s == 'NoShow')
                                  ? OutlinedButton(onPressed: _busy ? null : () => _setStatus(r, s), child: Text(s == 'NoShow' ? 'No-show' : 'Cancel'))
                                  : FilledButton.tonal(onPressed: _busy ? null : () => _setStatus(r, s), child: Text(s)),
                          ]),
                        ),
                    ]),
                  ),
                );
              },
            ),
          ),
        ),
      ]),
    );
  }
}

class _BookingSheet extends StatefulWidget {
  const _BookingSheet({required this.day});
  final DateTime day;

  @override
  State<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<_BookingSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _guests = TextEditingController(text: '2');
  final _request = TextEditingController();
  late TimeOfDay _time = TimeOfDay(hour: (TimeOfDay.now().hour + 1) % 24, minute: 0);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _guests, _request]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final at = DateTime(widget.day.year, widget.day.month, widget.day.day, _time.hour, _time.minute);
    setState(() { _busy = true; _error = null; });
    try {
      await context.api.post('reservations', {
        'customerId': null,
        'guestName': _name.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'guestCount': int.parse(_guests.text),
        'reservedAt': at.toIso8601String() + _offset(at),
        'durationMinutes': 90,
        'tableId': null,
        'specialRequest': _request.text.trim().isEmpty ? null : _request.text.trim(),
      });
      if (mounted) context.pop(true);
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.toString(); });
    }
  }

  static String _offset(DateTime d) {
    final o = d.timeZoneOffset;
    final sign = o.isNegative ? '-' : '+';
    final h = o.inHours.abs().toString().padLeft(2, '0');
    final m = (o.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return '$sign$h:$m';
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(left: 16, right: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('New reservation · ${DateFormat('EEE, d MMM').format(widget.day)}', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextFormField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Guest name'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone'))),
                const SizedBox(width: 12),
                SizedBox(width: 90, child: TextFormField(controller: _guests, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Guests'), validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1 ? 'Min 1' : null)),
              ]),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final t = await showTimePicker(context: context, initialTime: _time);
                  if (t != null) setState(() => _time = t);
                },
                icon: const Icon(Icons.schedule),
                label: Text('Time: ${_time.format(context)}'),
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _request, decoration: const InputDecoration(labelText: 'Special request (optional)')),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              const SizedBox(height: 16),
              FilledButton(onPressed: _busy ? null : _save, child: const Text('Book table')),
            ]),
          ),
        ),
      );
}
