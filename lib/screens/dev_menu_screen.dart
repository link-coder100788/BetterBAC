import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../src/rust/api/dev.dart';
import '../src/rust/api/tutorial.dart';
import '../theme.dart';
import '../widgets/chunky.dart';
import '../widgets/confirm.dart';
import 'welcome_screen.dart';

/// Testing tools. Only reachable when `DEV_MENU` is true in `rust/src/api/dev.rs`.
class DevMenuScreen extends StatelessWidget {
  const DevMenuScreen({super.key});

  /// Runs a dev action, refreshes every screen and confirms with a snackbar.
  static Future<void> _run(
    BuildContext context,
    String done,
    Future<void> Function() action,
  ) async {
    if (!await attempt(context, action)) return;
    notifyDataChanged();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    }
  }

  /// Runs [action], then restarts the app flow from the welcome screen.
  static Future<void> _restartFromWelcome(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    final navigator = Navigator.of(context);
    if (!await attempt(context, action)) return;
    notifyDataChanged();
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget button(String label, IconData icon, VoidCallback onPressed) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ChunkyButton.outlined(label: label, icon: icon, onPressed: onPressed),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Developer menu')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const _Banner(),
          const SectionTitle('XP & streaks'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final xp in const [10, 50, 100, 500])
                ChunkyButton(
                  label: '+$xp XP',
                  expand: false,
                  color: Palette.yellow,
                  lipColor: Palette.yellowLip,
                  textColor: Palette.ink,
                  onPressed: () =>
                      _run(context, 'Added $xp XP', () => devAddXp(amount: xp)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final days in const [3, 7, 30])
                ChunkyButton(
                  label: '$days-day streak',
                  icon: Icons.local_fire_department_rounded,
                  expand: false,
                  color: Palette.orange,
                  lipColor: Palette.orangeLip,
                  onPressed: () => _run(
                    context,
                    'Streak set to $days days',
                    () => devSetStreak(days: days),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          button('Reset all XP', Icons.restart_alt_rounded, () async {
            final ok = await confirm(
              context,
              title: 'Reset all XP?',
              message: 'Total XP, level, streak and history go back to zero.',
              action: 'Reset',
            );
            if (ok && context.mounted) _run(context, 'XP reset', devResetXp);
          }),

          const SectionTitle('Data'),
          button('Seed sample data', Icons.auto_fix_high_rounded, () {
            _run(context, 'Sample data added', devSeedSampleData);
          }),
          ChunkyButton(
            label: 'Clear all progress',
            icon: Icons.delete_forever_rounded,
            color: Palette.red,
            lipColor: Palette.redLip,
            onPressed: () async {
              final ok = await confirm(
                context,
                title: 'Clear all progress?',
                message:
                    'Deletes every experience, reflection, event, XP award and '
                    "setting on this device, then restarts at the welcome screen. "
                    "This can't be undone.",
                action: 'Clear',
              );
              if (ok && context.mounted) _restartFromWelcome(context, devClearAll);
            },
          ),

          const SectionTitle('Onboarding & tour'),
          button('Full tour on next launch', Icons.school_rounded, () {
            _run(
              context,
              'Full tour will show next launch',
              () => devSetTutorialSeen(version: 0),
            );
          }),
          button("\"What's new\" on next launch", Icons.new_releases_rounded, () async {
            final status = await tutorialStatus();
            if (!context.mounted) return;
            if (status.currentVersion < 2) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Only one tour version so far, so there's nothing new to show."),
                ),
              );
              return;
            }
            _run(
              context,
              "\"What's new\" will show next launch",
              () => devSetTutorialSeen(version: status.currentVersion - 1),
            );
          }),
          button('Restart onboarding now', Icons.waving_hand_rounded, () {
            _restartFromWelcome(context, devResetOnboarding);
          }),

          const SectionTitle('Database'),
          const _DatabaseOverview(),
          const SizedBox(height: 12),
          button('SQL console', Icons.terminal_rounded, () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const _SqlConsole()),
            );
          }),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Palette.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        children: [
          Icon(Icons.build_rounded, color: Palette.orange),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'For testing only. Turn off with DEV_MENU in rust/src/api/dev.rs before release.',
              style: TextStyle(color: Palette.orangeLip, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
}

class _DatabaseOverview extends StatelessWidget {
  const _DatabaseOverview();

  @override
  Widget build(BuildContext context) {
    return ReloadOnChange<DbOverview>(
      load: devDbOverview,
      builder: (context, db) => ChunkyCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv('Size', _formatBytes(db.sizeBytes.toInt())),
            _kv('Schema version', '${db.schemaVersion}'),
            _kv('SQLite', db.sqliteVersion),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    db.path,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Palette.muted,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy path',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: db.path)),
                ),
              ],
            ),
            const Divider(height: 24),
            for (final t in db.tables)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.table_chart_rounded, color: Palette.blue),
                title: Text(
                  t.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${t.rows} rows'
                  '${t.deletedRows == null ? '' : ' · ${t.deletedRows} soft-deleted'}',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => _TableScreen(table: t.name)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(k, style: const TextStyle(color: Palette.muted)),
        ),
        Expanded(
          child: Text(v, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
}

/// Pages through one table's raw rows.
class _TableScreen extends StatefulWidget {
  const _TableScreen({required this.table});

  final String table;

  @override
  State<_TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<_TableScreen> {
  static const _pageSize = 50;
  int _offset = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.table)),
      body: ReloadOnChange<DevTable>(
        key: ValueKey(_offset),
        load: () => devTable(table: widget.table, offset: _offset, limit: _pageSize),
        builder: (context, data) {
          final total = data.totalRows?.toInt() ?? 0;
          final end = (_offset + data.rows.length).clamp(0, total);
          return Column(
            children: [
              Expanded(child: _ResultTable(data: data)),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _offset == 0
                          ? null
                          : () => setState(() => _offset -= _pageSize),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Text(
                        total == 0 ? 'Empty' : '${_offset + 1}–$end of $total',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      onPressed: end >= total
                          ? null
                          : () => setState(() => _offset += _pageSize),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Scrollable grid of results. Tap a row to see every field in full.
class _ResultTable extends StatelessWidget {
  const _ResultTable({required this.data});

  final DevTable data;

  void _showRow(BuildContext context, List<String> row) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            for (final (i, col) in data.columns.indexed) ...[
              Text(
                col,
                style: const TextStyle(color: Palette.muted, fontWeight: FontWeight.w800),
              ),
              SelectableText(row[i], style: const TextStyle(fontFamily: 'monospace')),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (data.columns.isEmpty) {
      return const Center(child: Text('No columns'));
    }
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 12);
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DataTable(
              showCheckboxColumn: false,
              headingRowHeight: 40,
              dataRowMinHeight: 36,
              dataRowMaxHeight: 48,
              columns: [
                for (final c in data.columns)
                  DataColumn(
                    label: Text(c, style: mono.copyWith(fontWeight: FontWeight.w800)),
                  ),
              ],
              rows: [
                for (final row in data.rows)
                  DataRow(
                    onSelectChanged: (_) => _showRow(context, row),
                    cells: [
                      for (final cell in row)
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 240),
                            child: Text(
                              cell,
                              style: cell == 'NULL'
                                  ? mono.copyWith(color: Palette.gray)
                                  : mono,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            if (data.truncated)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Showing the first 500 rows.',
                  style: TextStyle(color: Palette.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SqlConsole extends StatefulWidget {
  const _SqlConsole();

  @override
  State<_SqlConsole> createState() => _SqlConsoleState();
}

class _SqlConsoleState extends State<_SqlConsole> {
  static const _examples = [
    'SELECT key, amount, earned_on FROM xp_log ORDER BY created_at DESC',
    'SELECT title, length(body) AS chars, exported_at FROM reflections',
    "SELECT name, sql FROM sqlite_master WHERE type = 'table'",
    'PRAGMA table_info(events)',
  ];

  final _sql = TextEditingController(text: _examples.first);
  DevTable? _result;
  bool _running = false;

  @override
  void dispose() {
    _sql.dispose();
    super.dispose();
  }

  Future<void> _runQuery() async {
    setState(() => _running = true);
    final result = await guard(context, () => devQuery(sql: _sql.text));
    if (!mounted) return;
    setState(() {
      _running = false;
      if (result != null) _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('SQL console')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _sql,
              minLines: 2,
              maxLines: 5,
              autocorrect: false,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(hintText: 'Read-only SQL'),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final ex in _examples)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text(
                        ex.length > 32 ? '${ex.substring(0, 32)}…' : ex,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                      ),
                      onPressed: () => setState(() => _sql.text = ex),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ChunkyButton(
              label: _running ? 'Running…' : 'Run',
              icon: Icons.play_arrow_rounded,
              color: Palette.blue,
              lipColor: Palette.blueLip,
              onPressed: _running ? null : _runQuery,
            ),
          ),
          if (result != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${result.rows.length} row${result.rows.length == 1 ? '' : 's'}',
                  style: const TextStyle(color: Palette.muted),
                ),
              ),
            ),
          Expanded(
            child: result == null
                ? const Center(
                    child: Text(
                      'Only read-only statements run here.',
                      style: TextStyle(color: Palette.muted),
                    ),
                  )
                : _ResultTable(data: result),
          ),
        ],
      ),
    );
  }
}
