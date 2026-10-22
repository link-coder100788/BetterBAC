import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import 'theme.dart';

/// Bumped whenever data changes in Rust so every visible screen reloads.
/// Screens use [ReloadOnChange] to subscribe.
final dataVersion = ValueNotifier<int>(0);

void notifyDataChanged() => dataVersion.value++;

/// Human-readable message for an error thrown from Rust.
String errorMessage(Object e) => switch (e) {
  AnyhowException(:final message) => message.split('\n').first,
  _ => e.toString(),
};

/// Runs [action]; on failure shows the Rust error message in a snackbar
/// and returns null.
Future<T?> guard<T>(BuildContext context, Future<T> Function() action) async {
  try {
    return await action();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Palette.red,
          content: Text(
            errorMessage(e),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
    }
    return null;
  }
}

/// [guard] for actions without a result. Returns true on success.
Future<bool> attempt(BuildContext context, Future<void> Function() action) async =>
    await guard(context, () async {
      await action();
      return true;
    }) ??
    false;

/// Celebratory "+N XP" toast. Does nothing for 0 XP.
void showXp(BuildContext context, int xp, {String? message}) {
  if (xp <= 0 || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: Palette.yellow,
      duration: const Duration(seconds: 2),
      content: Row(
        children: [
          const Icon(Icons.bolt_rounded, color: Palette.orange, size: 28),
          const SizedBox(width: 8),
          Text(
            '+$xp XP',
            style: const TextStyle(
              color: Palette.ink,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          if (message != null) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Palette.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Loads data with [load] and rebuilds with it; reloads whenever
/// [notifyDataChanged] is called. Shows a spinner / error while needed.
class ReloadOnChange<T> extends StatefulWidget {
  const ReloadOnChange({super.key, required this.load, required this.builder});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;

  @override
  State<ReloadOnChange<T>> createState() => _ReloadOnChangeState<T>();
}

class _ReloadOnChangeState<T> extends State<ReloadOnChange<T>> {
  late Future<T> _future;
  T? _last;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
    dataVersion.addListener(_reload);
  }

  @override
  void dispose() {
    dataVersion.removeListener(_reload);
    super.dispose();
  }

  void _reload() => setState(() => _future = widget.load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        // After a successful load, keep showing stale data if a reload fails
        // (e.g. the item was just deleted and this screen is popping).
        if (snap.hasError && _last == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                errorMessage(snap.error!),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (snap.hasData) _last = snap.data;
        // Keep showing the previous data while reloading to avoid flicker.
        final data = snap.data ?? _last;
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return widget.builder(context, data);
      },
    );
  }
}
