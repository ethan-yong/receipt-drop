import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/bootstrap/app_prefs.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/receipt_card.dart';

/// Onboarding flow (approved design, canvas option 2a).
///
/// Three swipeable pages:
///   1. "Share any RM receipt"       — share-sheet diagram
///   2. "Details filled in for you"  — receipt card mock with suggestion chips
///   3. "Your data, your map"        — map preview with price pins
///
/// Matches the app shell: cream background, ink text, yellow pill CTA,
/// Skip in the header, animated page dots, 150-300ms ease-in-out motion.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;
  double _pageValue = 0;
  bool _interacted = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_controller.hasClients && _controller.page != null) {
        setState(() => _pageValue = _controller.page!);
      }
    });
    // Peek gesture hint: nudge the page and back once, teaching swipeability.
    Future.delayed(const Duration(milliseconds: 900), () async {
      if (!mounted || _interacted || _page != 0) return;
      await _controller.animateTo(
        36,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOut,
      );
      if (!mounted) return;
      await _controller.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOut,
      );
    });
  }

  static const _pages = [
    _PageData(
      title: 'Share any RM receipt',
      subtitle: 'Tap Share on any bank or TNG receipt. It lands here.',
    ),
    _PageData(
      title: 'Details filled in for you',
      subtitle: 'Place and category, auto-suggested. Fix anything later.',
    ),
    _PageData(
      title: 'Your data, your map',
      subtitle:
          'Every receipt pinned where you spent it. Private, and only yours.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finishOnboarding() async {
    await AppPrefs.setOnboardingComplete();
    if (mounted) context.go('/auth');
  }

  void _next() {
    _interacted = true;
    if (_page < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finishOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pages.length - 1;

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        child: Column(
          children: [
            // Header: brand + Skip
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.xs,
                0,
              ),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Text('🧾', style: TextStyle(fontSize: 15)),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  const Text(
                    'Receipt Drop',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _finishOnboarding,
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Pages
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n is ScrollStartNotification && n.dragDetails != null) {
                    _interacted = true;
                  }
                  return false;
                },
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) {
                    // Parallax: visuals lag slightly behind the page drag.
                    final delta = (_pageValue - i).clamp(-1.0, 1.0);
                    return _OnboardingPage(
                      data: _pages[i],
                      visual: Transform.translate(
                        offset: Offset(-delta * 26, 0),
                        child: switch (i) {
                          0 => const _ShareSheetVisual(),
                          1 => _ReceiptMockVisual(active: i == _page),
                          _ => const _MapPreviewVisual(),
                        },
                      ),
                    );
                  },
                ),
              ),
            ),

            // Footer: dots + CTA
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_pages.length, (i) {
                      final active = i == _page;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        width: active ? 22 : 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(horizontal: 3.5),
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.primaryGreen
                              : AppColors.divider,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: AppColors.textPrimary,
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          isLast ? "Let's get started" : 'Next',
                          key: ValueKey(isLast),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- page shell

class _PageData {
  const _PageData({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.data, required this.visual});

  final _PageData data;
  final Widget visual;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          visual,
          const SizedBox(height: AppSpacing.lg),
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 270),
            child: Text(
              data.subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- visual 1

class _ShareSheetVisual extends StatelessWidget {
  const _ShareSheetVisual();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x143C3214),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // bank notification row
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.creamDark,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A4B9F),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'TNG',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Touch 'n Go eWallet",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Payment receipt',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Text(
                  'RM 12.00',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          _dashedConnector(),
          // "tap Share" pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.creamDark,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'tap Share ↗',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          _dashedConnector(),
          // share sheet row
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.creamDark,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _shareTarget('💬', 'Messages', highlighted: false),
                _shareTarget('🧾', 'Receipt Drop', highlighted: true),
                _shareTarget('✉️', 'Mail', highlighted: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashedConnector() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        height: 22,
        child: CustomPaint(
          size: const Size(2, 22),
          painter: _VerticalDashPainter(color: AppColors.divider),
        ),
      ),
    );
  }

  Widget _shareTarget(
    String emoji,
    String label, {
    required bool highlighted,
  }) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: highlighted
                  ? AppColors.primaryGreen
                  : AppColors.divider.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(14),
              border: highlighted
                  ? Border.all(color: AppColors.cardSurface, width: 3)
                  : null,
              boxShadow: highlighted
                  ? const [
                      BoxShadow(
                        color: AppColors.primaryGreen,
                        spreadRadius: 2,
                        blurRadius: 0,
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Opacity(
              opacity: highlighted ? 1 : 0.5,
              child: Text(emoji, style: const TextStyle(fontSize: 19)),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: highlighted ? FontWeight.w800 : FontWeight.w500,
              color: highlighted
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- visual 2

class _ReceiptMockVisual extends StatefulWidget {
  const _ReceiptMockVisual({required this.active});
  final bool active;

  @override
  State<_ReceiptMockVisual> createState() => _ReceiptMockVisualState();
}

class _ReceiptMockVisualState extends State<_ReceiptMockVisual> {
  bool _chipsIn = false;

  @override
  void didUpdateWidget(_ReceiptMockVisual old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      setState(() => _chipsIn = false);
      Future.delayed(const Duration(milliseconds: 80), () {
        if (mounted) setState(() => _chipsIn = true);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      Future.delayed(const Duration(milliseconds: 80), () {
        if (mounted) setState(() => _chipsIn = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Mock of the home receipt card (The Copper Pot), styled with the real
    // restaurant category palette so it stays in sync with the home screen.
    final palette = receiptPaletteForCategory('restaurant');
    final illustration = receiptIllustrationAssetForCategory('restaurant');

    return Container(
      decoration: BoxDecoration(
        color: palette.mid,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x293C3214),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 10, color: palette.acc),
          Container(
            color: palette.top,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(palette.emoji, style: const TextStyle(fontSize: 18)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'The Copper Pot',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: palette.ink,
                        ),
                      ),
                      Text(
                        'Today, 7:28 PM',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: palette.sub,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'RM 59.50',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: palette.ink,
                  ),
                ),
              ],
            ),
          ),
          if (illustration != null)
            SizedBox(
              height: 96,
              child: Image.asset(
                illustration,
                fit: BoxFit.cover,
                alignment: const Alignment(0, 0.24),
                errorBuilder: (context, error, stackTrace) =>
                    ColoredBox(color: palette.tile),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _settleChip(
                      '✨ #EAT',
                      AppColors.primaryGreen,
                      AppColors.textPrimary,
                      0,
                    ),
                    _settleChip(
                      '📍 Bangsar',
                      Colors.white.withValues(alpha: 0.35),
                      palette.ink,
                      1,
                    ),
                    _settleChip(
                      '✏️ edit anytime',
                      Colors.transparent,
                      Colors.white.withValues(alpha: 0.9),
                      2,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.55),
                        width: 1.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: palette.ink,
                        ),
                      ),
                      Text(
                        'RM 59.50',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: palette.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _settleChip(
    String label,
    Color bg,
    Color fg,
    int index, {
    BoxBorder? border,
  }) {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      offset: _chipsIn ? Offset.zero : const Offset(0, 0.35),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        opacity: _chipsIn ? 1 : 0,
        child: _chip(label, bg, fg, border: border),
      ),
    );
  }

  Widget _chip(String label, Color bg, Color fg, {BoxBorder? border}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: border,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- visual 3

class _MapPreviewVisual extends StatelessWidget {
  const _MapPreviewVisual();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 216,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F1DF),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A3C3214),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          // roads
          Positioned(
            left: -20,
            top: 76,
            right: -20,
            child: Transform.rotate(
              angle: -0.16,
              child: Container(height: 12, color: const Color(0xFFF6DE8F)),
            ),
          ),
          Positioned(
            left: -20,
            top: 162,
            right: -20,
            child: Transform.rotate(
              angle: 0.10,
              child: Container(height: 9, color: const Color(0xFFF6DE8F)),
            ),
          ),
          // search bar
          Positioned(
            left: 12,
            right: 56,
            top: 12,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.centerLeft,
              child: const Text(
                '🔍 Search places',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          // filter chips
          Positioned(
            left: 12,
            top: 54,
            child: Row(
              children: [
                _filterChip('✓ This month'),
                const SizedBox(width: 6),
                _filterChip('✓ All categories'),
              ],
            ),
          ),
          // pins
          const Positioned(
            left: 26,
            top: 96,
            child: _MapPin(label: 'RM 45', borderColor: Color(0xFF4C8C4A)),
          ),
          const Positioned(
            left: 194,
            top: 104,
            child: _MapPin(
              label: 'RM 541',
              borderColor: Color(0xFF8C857B),
              badge: '5',
            ),
          ),
          const Positioned(
            left: 110,
            top: 140,
            child: _MapPin(label: 'RM 157', borderColor: Color(0xFF2E6E8E)),
          ),
          // privacy pills
          Positioned(
            left: 12,
            bottom: 12,
            child: _pill('🔒 Only you', AppColors.textPrimary, Colors.white),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: _pill(
              '🛡️ Not a bank',
              AppColors.cardSurface,
              AppColors.textPrimary,
            ),
          ),
          // faded nav preview: hints at what unlocks after sign-in
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Opacity(
              opacity: 0.4,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: const BoxDecoration(
                    color: AppColors.cardSurface,
                    border: Border(
                      top: BorderSide(color: AppColors.divider, width: 1.5),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _navIcon('🏠', 'Home'),
                      _navIcon('👥', 'Feed'),
                      Container(
                        width: 34,
                        height: 34,
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGreen,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          '+',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      _navIcon('🗺️', 'Map'),
                      _navIcon('🏆', 'Ranks'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navIcon(String emoji, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 15)),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFBEFC5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFFB08900),
        ),
      ),
    );
  }

  Widget _pill(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.label, required this.borderColor, this.badge});

  final String label;
  final Color borderColor;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 11,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 2),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (badge != null)
              Positioned(
                top: -8,
                right: -8,
                child: Container(
                  width: 17,
                  height: 17,
                  decoration: BoxDecoration(
                    color: borderColor,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
        // tail
        Transform.translate(
          offset: const Offset(0, -5),
          child: Transform.rotate(
            angle: 0.785398, // 45deg
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  right: BorderSide(color: borderColor, width: 2),
                  bottom: BorderSide(color: borderColor, width: 2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- painters

class _VerticalDashPainter extends CustomPainter {
  const _VerticalDashPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    const dash = 5.0, gap = 4.0;
    double y = 0;
    while (y < size.height) {
      canvas.drawLine(Offset(0, y), Offset(0, y + dash), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_VerticalDashPainter old) => old.color != color;
}
