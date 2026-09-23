import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/branding_controller.dart';
import '../core/services/signalr_service.dart';

extension ContextX on BuildContext {
  ApiClient get api => read<ApiClient>();
  BrandingController get brand => watch<BrandingController>();
  SignalrService get signalr => read<SignalrService>();
  String money(num v) => watch<BrandingController>().money(v);

  void toast(String message, {bool error = false}) {
    final messenger = ScaffoldMessenger.of(this);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Theme.of(this).colorScheme.error : null,
      ));
  }

  void toastError(Object e) => toast(e is ApiException ? e.message : 'Something went wrong. Please try again.', error: true);
}

/// Loads data once, shows a skeleton / error with retry / empty state, and supports pull-to-refresh.
class AsyncBody<T> extends StatefulWidget {
  const AsyncBody({super.key, required this.load, required this.builder, this.isEmpty, this.emptyIcon = Icons.inbox_outlined, this.emptyTitle = 'Nothing here yet', this.emptyHint});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final bool Function(T data)? isEmpty;
  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptyHint;

  @override
  State<AsyncBody<T>> createState() => _AsyncBodyState<T>();
}

class _AsyncBodyState<T> extends State<AsyncBody<T>> {
  T? _data;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _run(initial: true);
  }

  Future<void> _run({bool initial = false}) async {
    if (initial || _data == null) setState(() { _loading = true; _error = null; });
    try {
      final d = await widget.load();
      if (!mounted) return;
      setState(() { _data = d; _loading = false; _error = null; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e; _loading = false; });
      if (_data != null && mounted) context.toastError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_data == null) {
      return ErrorView(message: _error is ApiException ? (_error as ApiException).message : 'Could not load this screen.', onRetry: () => _run(initial: true));
    }
    final data = _data as T;
    if (widget.isEmpty?.call(data) ?? false) {
      return RefreshIndicator(
        onRefresh: _run,
        child: LayoutBuilder(builder: (context, c) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(height: c.maxHeight, child: EmptyView(icon: widget.emptyIcon, title: widget.emptyTitle, hint: widget.emptyHint)),
        )),
      );
    }
    return RefreshIndicator(onRefresh: _run, child: widget.builder(context, data, _run));
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.title, this.hint});
  final IconData icon;
  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: t.colorScheme.outline),
          const SizedBox(height: 12),
          Text(title, style: t.textTheme.titleMedium, textAlign: TextAlign.center),
          if (hint != null) ...[const SizedBox(height: 4), Text(hint!, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.outline), textAlign: TextAlign.center)],
        ]),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off_outlined, size: 56, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
          ]),
        ),
      );
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;

  static Color colorFor(String s, ColorScheme c) => switch (s) {
        'Available' || 'Completed' || 'Paid' || 'Ready' || 'Served' || 'Confirmed' || 'OK' => Colors.green.shade700,
        'Occupied' || 'Cancelled' || 'NoShow' || 'Out' || 'Rejected' => Colors.red.shade700,
        'Reserved' || 'Pending' || 'Requested' || 'Low' || 'Preparing' || 'Sent' || 'PartiallyPaid' => Colors.orange.shade800,
        'Cleaning' || 'Seated' || 'Arrived' || 'Draft' => Colors.blue.shade700,
        _ => c.outline,
      };

  @override
  Widget build(BuildContext context) {
    final color = colorFor(status, Theme.of(context).colorScheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(status, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Row(children: [Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))), ?trailing]),
      );
}

String timeAgo(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}
