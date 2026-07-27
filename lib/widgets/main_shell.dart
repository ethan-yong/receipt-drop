import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/platform/platform_feedback.dart';
import '../core/platform/platform_utils.dart';
import '../core/theme/app_theme.dart';
import '../features/share/receipt_capture_flow.dart';

/// Bottom navigation: Home, Feed, Map, Ranks — with a center capture FAB on
/// Home and Map only.
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _goBranch(int index) {
    PlatformFeedback.selectionTap();
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  void _onFabTap(BuildContext context) {
    PlatformFeedback.lightTap();
    ReceiptCaptureFlow.start(context);
  }

  @override
  Widget build(BuildContext context) {
    final index = navigationShell.currentIndex;
    // Capture FAB only on Home (0) and Map (2) — not Feed or Ranks.
    final showFab = index == 0 || index == 2;

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: navigationShell,
      extendBody: true,
      floatingActionButton: showFab
          ? Transform.translate(
              offset: const Offset(0, -12),
              child: FloatingActionButton(
                onPressed: () => _onFabTap(context),
                elevation: 6,
                child: Icon(
                  PlatformUtils.isCupertino ? CupertinoIcons.add : Icons.add,
                  size: 28,
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: PlatformUtils.isCupertino
          ? _IosTabBar(index: index, onTap: _goBranch)
          : _AndroidTabBar(index: index, onTap: _goBranch),
    );
  }
}

class _IosTabBar extends StatelessWidget {
  const _IosTabBar({required this.index, required this.onTap});

  final int index;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: CupertinoColors.systemBackground
                .resolveFrom(context)
                .withValues(alpha: 0.82),
            border: Border(
              top: BorderSide(
                color: CupertinoColors.separator.resolveFrom(context),
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 56,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _NavItem(
                    icon: CupertinoIcons.house,
                    selectedIcon: CupertinoIcons.house_fill,
                    label: 'Home',
                    selected: index == 0,
                    onTap: () => onTap(0),
                  ),
                  _NavItem(
                    icon: CupertinoIcons.person_2,
                    selectedIcon: CupertinoIcons.person_2_fill,
                    label: 'Feed',
                    selected: index == 1,
                    onTap: () => onTap(1),
                  ),
                  const SizedBox(width: 56),
                  _NavItem(
                    icon: CupertinoIcons.map,
                    selectedIcon: CupertinoIcons.map_fill,
                    label: 'Map',
                    selected: index == 2,
                    onTap: () => onTap(2),
                  ),
                  _NavItem(
                    icon: CupertinoIcons.rosette,
                    selectedIcon: CupertinoIcons.rosette,
                    label: 'Ranks',
                    selected: index == 3,
                    onTap: () => onTap(3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AndroidTabBar extends StatelessWidget {
  const _AndroidTabBar({required this.index, required this.onTap});

  final int index;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      notchMargin: 8,
      shape: const CircularNotchedRectangle(),
      color: AppColors.cardSurface,
      elevation: 8,
      shadowColor: Colors.black26,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home,
            label: 'Home',
            selected: index == 0,
            onTap: () => onTap(0),
          ),
          _NavItem(
            icon: Icons.people_outline,
            selectedIcon: Icons.people,
            label: 'Feed',
            selected: index == 1,
            onTap: () => onTap(1),
          ),
          const SizedBox(width: 56),
          _NavItem(
            icon: Icons.map_outlined,
            selectedIcon: Icons.map,
            label: 'Map',
            selected: index == 2,
            onTap: () => onTap(2),
          ),
          _NavItem(
            icon: Icons.emoji_events_outlined,
            selectedIcon: Icons.emoji_events,
            label: 'Ranks',
            selected: index == 3,
            onTap: () => onTap(3),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primaryGreen : AppColors.navUnselected;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? selectedIcon : icon, color: color, size: 26),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
