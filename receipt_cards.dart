// Spending Receipts — Flutter port
//
// Single-file demo. Run with `flutter run` after adding the font dependency:
//   dependencies:
//     google_fonts: ^6.1.0
// (Or remove google_fonts and set fontFamily to a bundled "Baloo 2".)
//
// The illustration area is a placeholder. To use real art, replace the
// `_Illustration` child with: Image.asset('assets/cafe.png', fit: BoxFit.contain)

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

void main() => runApp(const ReceiptApp());

class ReceiptApp extends StatelessWidget {
  const ReceiptApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Spending Receipts',
      theme: ThemeData(scaffoldBackgroundColor: const Color(0xFFFAF3E7)),
      home: const ReceiptScreen(),
    );
  }
}

// ---------------------------------------------------------------- models

class ReceiptItem {
  final String icon; // emoji glyph
  final String name;
  final double price;
  const ReceiptItem(this.icon, this.name, this.price);
}

class Category {
  final String label;
  final String store;
  final String time;
  final String receiptId;
  final String badge; // emoji glyph
  final Color top, mid, accent, tile, ink, sub;
  final List<ReceiptItem> items;

  const Category({
    required this.label,
    required this.store,
    required this.time,
    required this.receiptId,
    required this.badge,
    required this.top,
    required this.mid,
    required this.accent,
    required this.tile,
    required this.ink,
    required this.sub,
    required this.items,
  });

  double get total => items.fold(0.0, (s, i) => s + i.price);

  // 'Fast Food' -> 'fast_food' for asset filenames (assets/illustrations/<key>.png)
  String get assetKey => label.toLowerCase().replaceAll(' ', '_');
}

const _categories = <Category>[
  Category(
    label: 'Cafe',
    store: 'Brew & Co.',
    time: 'Today, 10:42 AM',
    receiptId: '#1024',
    badge: '☕',
    top: Color(0xFFF4E8D6),
    mid: Color(0xFFC9A37C),
    accent: Color(0xFFE2885C),
    tile: Color(0xFFEFDFC7),
    ink: Color(0xFF5A4632),
    sub: Color(0xFF9C8A72),
    items: [
      ReceiptItem('☕', 'Latte', 12.50),
      ReceiptItem('🥐', 'Croissant', 7.90),
      ReceiptItem('🧁', 'Blueberry Muffin', 6.90),
    ],
  ),
  Category(
    label: 'Restaurant',
    store: 'The Copper Pot',
    time: 'Today, 7:28 PM',
    receiptId: '#2087',
    badge: '🍽️',
    top: Color(0xFFF6E9E1),
    mid: Color(0xFFC68C76),
    accent: Color(0xFFC75643),
    tile: Color(0xFFEAD7CC),
    ink: Color(0xFF4F2D23),
    sub: Color(0xFFA07F72),
    items: [
      ReceiptItem('🍝', 'Truffle Pasta', 32.00),
      ReceiptItem('🥗', 'Caesar Salad', 18.50),
      ReceiptItem('🧃', 'Lemonade', 9.00),
    ],
  ),
  Category(
    label: 'Grocery',
    store: 'FreshMart',
    time: 'Today, 5:14 PM',
    receiptId: '#4412',
    badge: '🛒',
    top: Color(0xFFEAF1E2),
    mid: Color(0xFF9FB98A),
    accent: Color(0xFF5E9E51),
    tile: Color(0xFFDCE8CD),
    ink: Color(0xFF36482C),
    sub: Color(0xFF7E9070),
    items: [
      ReceiptItem('🥚', 'Free-Range Eggs', 11.90),
      ReceiptItem('🥛', 'Oat Milk', 9.90),
      ReceiptItem('🍞', 'Sourdough Loaf', 8.50),
      ReceiptItem('🥦', 'Broccoli', 4.20),
    ],
  ),
  Category(
    label: 'Clothing',
    store: 'Thread & Co.',
    time: 'Today, 2:05 PM',
    receiptId: '#3398',
    badge: '🛍️',
    top: Color(0xFFF6E7EE),
    mid: Color(0xFFCDA0B4),
    accent: Color(0xFFD26E97),
    tile: Color(0xFFEBD6E0),
    ink: Color(0xFF4F2E3B),
    sub: Color(0xFFA07F8D),
    items: [
      ReceiptItem('👕', 'Cotton Tee', 49.00),
      ReceiptItem('👖', 'Slim Jeans', 129.00),
      ReceiptItem('🧦', 'Socks (3pk)', 19.00),
    ],
  ),
  Category(
    label: 'Tech',
    store: 'PixelTech',
    time: 'Today, 11:20 AM',
    receiptId: '#5176',
    badge: '💻',
    top: Color(0xFFE8EEF6),
    mid: Color(0xFF9FB2CE),
    accent: Color(0xFF4F86C6),
    tile: Color(0xFFD6E1F0),
    ink: Color(0xFF2C3A4E),
    sub: Color(0xFF7E8EA5),
    items: [
      ReceiptItem('🎧', 'USB-C Earbuds', 89.00),
      ReceiptItem('🔌', '65W Charger', 75.00),
      ReceiptItem('🖱️', 'Wireless Mouse', 59.00),
    ],
  ),
];

String _rm(double v) => 'RM ${v.toStringAsFixed(2)}';

// ---------------------------------------------------------------- screen

class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({super.key});
  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final c = _categories[_selected];
    final w = MediaQuery.of(context).size.width;
    final cardW = w < 412 ? w - 32 : 380.0;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 42, 16, 64),
          child: Column(
            children: [
              Text('Spending receipts',
                  style: GoogleFonts.baloo2(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF2C2C33),
                      letterSpacing: -0.4)),
              const SizedBox(height: 4),
              Text('Pick a category — drop your own illustration into each card',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.baloo2(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF8A8170))),
              const SizedBox(height: 26),
              _Chips(
                categories: _categories,
                selected: _selected,
                onTap: (i) => setState(() => _selected = i),
              ),
              const SizedBox(height: 30),
              _ReceiptCard(category: c, width: cardW),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- chips

class _Chips extends StatelessWidget {
  final List<Category> categories;
  final int selected;
  final ValueChanged<int> onTap;
  const _Chips(
      {required this.categories, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < categories.length; i++)
          _chip(categories[i], i == selected, () => onTap(i)),
      ],
    );
  }

  Widget _chip(Category c, bool on, VoidCallback tap) {
    return GestureDetector(
      onTap: tap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: on ? c.accent : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: on ? c.accent : const Color(0xFFE9DDCA), width: 1.5),
          boxShadow: on
              ? [
                  BoxShadow(
                      color: c.accent.withOpacity(0.33),
                      blurRadius: 16,
                      offset: const Offset(0, 6))
                ]
              : null,
        ),
        child: Text(c.label,
            style: GoogleFonts.baloo2(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: on ? Colors.white : const Color(0xFF9A8F7C))),
      ),
    );
  }
}

// ---------------------------------------------------------------- card

class _ReceiptCard extends StatelessWidget {
  final Category category;
  final double width;
  const _ReceiptCard({required this.category, required this.width});

  @override
  Widget build(BuildContext context) {
    final c = category;
    return Container(
      width: width,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.top,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF3C2814).withOpacity(0.18),
              blurRadius: 44,
              offset: const Offset(0, 20)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 12, color: c.accent), // accent cap
          _header(c),
          _illustration(c),
          _lower(c),
        ],
      ),
    );
  }

  Widget _header(Category c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.10),
                        blurRadius: 8,
                        offset: const Offset(0, 3)),
                  ],
                ),
                child: Text(c.badge, style: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.store,
                      style: GoogleFonts.baloo2(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: c.ink,
                          letterSpacing: -0.3)),
                  const SizedBox(height: 2),
                  Text(c.time,
                      style: GoogleFonts.baloo2(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.sub)),
                ],
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
                color: c.tile, borderRadius: BorderRadius.circular(999)),
            child: Row(
              children: [
                const Text('🧾', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 6),
                Text(c.receiptId,
                    style: GoogleFonts.baloo2(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Full-bleed illustration band. To use real art, add the PNG to assets and
  // replace the `child:` below with:
  //   Image.asset('assets/illustrations/${c.assetKey}.png', fit: BoxFit.cover)
  Widget _illustration(Category c) {
    return SizedBox(
      height: 216,
      width: double.infinity,
      child: Container(
        color: c.top,
        alignment: Alignment.center,
        // --- placeholder empty-state (delete when using Image.asset) ---
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_outlined,
                size: 30, color: c.ink.withOpacity(0.40)),
            const SizedBox(height: 10),
            Text('${c.label} illustration',
                style: GoogleFonts.baloo2(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.ink.withOpacity(0.55))),
          ],
        ),
        // --- real art (uncomment, remove the Column above) ---
        // child: Image.asset('assets/illustrations/${c.assetKey}.png',
        //     fit: BoxFit.cover),
      ),
    );
  }

  Widget _lower(Category c) {
    return Container(
      color: c.mid,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < c.items.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            _itemRow(c, c.items[i]),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 2,
            child: CustomPaint(painter: _DashedLinePainter(c.ink.withOpacity(0.30))),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.25),
                borderRadius: BorderRadius.circular(16)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total',
                    style: GoogleFonts.baloo2(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: c.ink)),
                Text(_rm(c.total),
                    style: GoogleFonts.baloo2(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        color: c.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemRow(Category c, ReceiptItem it) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: c.tile, borderRadius: BorderRadius.circular(10)),
              child: Text(it.icon, style: const TextStyle(fontSize: 17)),
            ),
            const SizedBox(width: 13),
            Text(it.name,
                style: GoogleFonts.baloo2(
                    fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
          ],
        ),
        Text(_rm(it.price),
            style: GoogleFonts.baloo2(
                fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
      ],
    );
  }
}

// ---------------------------------------------------------------- painters

class _DashedLinePainter extends CustomPainter {
  final Color color;
  _DashedLinePainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const dash = 5.0, gap = 5.0;
    final y = size.height / 2;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + dash, size.width), y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter old) => old.color != color;
}
