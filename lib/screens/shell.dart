import 'package:flutter/material.dart';

import '../theme.dart';
import 'calendar_screen.dart';
import 'cas_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'reflections_screen.dart';

/// Root layout: a bottom tab bar on phones, a side rail on wide screens.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _Tab {
  const _Tab(this.label, this.icon);
  final String label;
  final IconData icon;
}

const _tabs = [
  _Tab('Home', Icons.home_rounded),
  _Tab('CAS', Icons.flag_rounded),
  _Tab('Reflect', Icons.edit_note_rounded),
  _Tab('Calendar', Icons.calendar_month_rounded),
  _Tab('Profile', Icons.person_rounded),
];

class _ShellState extends State<Shell> {
  int _index = 0;

  void _select(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(onNavigate: _select),
      const CasScreen(),
      const ReflectionsScreen(),
      const CalendarScreen(),
      const ProfileScreen(),
    ];
    final body = IndexedStack(index: _index, children: pages);
    final wide = MediaQuery.sizeOf(context).width >= 760;

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            _SideBar(index: _index, onSelect: _select),
            const VerticalDivider(width: 2, thickness: 2, color: Palette.line),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: body,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: _BottomBar(index: _index, onSelect: _select),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.selected,
    required this.onTap,
    this.showLabel = false,
  });

  final _Tab tab;
  final bool selected;
  final VoidCallback onTap;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Palette.blue : Palette.gray;
    return Tooltip(
      message: tab.label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Palette.blue.withValues(alpha: 0.1) : null,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? Palette.blue.withValues(alpha: 0.6) : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            mainAxisSize: showLabel ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Icon(tab.icon, color: color, size: 30),
              if (showLabel) ...[
                const SizedBox(width: 14),
                Text(
                  tab.label.toUpperCase(),
                  style: TextStyle(
                    color: selected ? Palette.blue : Palette.muted,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Palette.white,
        border: Border(top: BorderSide(color: Palette.line, width: 2)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var i = 0; i < _tabs.length; i++)
                _NavItem(
                  tab: _tabs[i],
                  selected: i == index,
                  onTap: () => onSelect(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideBar extends StatelessWidget {
  const _SideBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        width: 230,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 0, 24),
                child: Text(
                  'betterbac',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Palette.green,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              for (var i = 0; i < _tabs.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _NavItem(
                    tab: _tabs[i],
                    selected: i == index,
                    onTap: () => onSelect(i),
                    showLabel: true,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
