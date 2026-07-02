import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/models/transaction_view.dart';
import 'receipt_thumbnail_file.dart'
    if (dart.library.html) 'receipt_thumbnail_file_web.dart' as file_image;

class ReceiptCardPalette {
  const ReceiptCardPalette({
    required this.acc,
    required this.top,
    required this.mid,
    required this.tile,
    required this.ink,
    required this.sub,
    required this.emoji,
  });

  final Color acc;
  final Color top;
  final Color mid;
  final Color tile;
  final Color ink;
  final Color sub;
  final String emoji;
}

ReceiptCardPalette receiptPaletteForCategory(String category) {
  final c = category.toLowerCase();

  if (c.contains('cafe') ||
      c.contains('coffee') ||
      c.contains('espresso') ||
      c.contains('latte') ||
      c.contains('tea') ||
      c.contains('boba') ||
      c.contains('bubble')) {
    return const ReceiptCardPalette(
      acc: Color(0xFFE2885C),
      top: Color(0xFFF4E8D6),
      mid: Color(0xFFC9A37C),
      tile: Color(0xFFEFDFC7),
      ink: Color(0xFF5A4632),
      sub: Color(0xFF9C8A72),
      emoji: '☕',
    );
  }

  if (c.contains('grocery') ||
      c.contains('groceries') ||
      c.contains('market') ||
      c.contains('supermarket')) {
    return const ReceiptCardPalette(
      acc: Color(0xFF5E9E51),
      top: Color(0xFFEAF1E2),
      mid: Color(0xFF9FB98A),
      tile: Color(0xFFDCE8CD),
      ink: Color(0xFF36482C),
      sub: Color(0xFF7E9070),
      emoji: '🛒',
    );
  }

  if (c.contains('clothing') ||
      c.contains('clothes') ||
      c.contains('fashion') ||
      c.contains('shopping') ||
      c.contains('mall') ||
      c.contains('boutique')) {
    return const ReceiptCardPalette(
      acc: Color(0xFFD26E97),
      top: Color(0xFFF6E7EE),
      mid: Color(0xFFCDA0B4),
      tile: Color(0xFFEBD6E0),
      ink: Color(0xFF4F2E3B),
      sub: Color(0xFFA07F8D),
      emoji: '🛍️',
    );
  }

  if (c.contains('tech') ||
      c.contains('electronics') ||
      c.contains('gaming') ||
      c.contains('game') ||
      c.contains('console') ||
      c.contains('pc')) {
    return const ReceiptCardPalette(
      acc: Color(0xFF4F86C6),
      top: Color(0xFFE8EEF6),
      mid: Color(0xFF9FB2CE),
      tile: Color(0xFFD6E1F0),
      ink: Color(0xFF2C3A4E),
      sub: Color(0xFF7E8EA5),
      emoji: '💻',
    );
  }

  if (c.contains('transport') ||
      c.contains('petrol') ||
      c.contains('fuel') ||
      c.contains('gas') ||
      c.contains('grab') ||
      c.contains('taxi') ||
      c.contains('transit') ||
      c.contains('train') ||
      c.contains('bus') ||
      c.contains('mrt')) {
    return const ReceiptCardPalette(
      acc: Color(0xFF4F86C6),
      top: Color(0xFFE3EBF4),
      mid: Color(0xFF8FAAC5),
      tile: Color(0xFFD0DFF0),
      ink: Color(0xFF2C3A4E),
      sub: Color(0xFF7E8EA5),
      emoji: '🚗',
    );
  }

  if (c.contains('beauty') ||
      c.contains('cosmetics') ||
      c.contains('skincare') ||
      c.contains('makeup') ||
      c.contains('salon')) {
    return const ReceiptCardPalette(
      acc: Color(0xFFD26E97),
      top: Color(0xFFF6E7EE),
      mid: Color(0xFFCDA0B4),
      tile: Color(0xFFEBD6E0),
      ink: Color(0xFF4F2E3B),
      sub: Color(0xFFA07F8D),
      emoji: '✨',
    );
  }

  if (c.contains('gym') ||
      c.contains('fitness') ||
      c.contains('workout') ||
      c.contains('yoga')) {
    return const ReceiptCardPalette(
      acc: Color(0xFFE67E57),
      top: Color(0xFFF2EAE4),
      mid: Color(0xFFC9A487),
      tile: Color(0xFFEBDDD4),
      ink: Color(0xFF4A2E1E),
      sub: Color(0xFF9C8070),
      emoji: '💪',
    );
  }

  if (c.contains('food') ||
      c.contains('restaurant') ||
      c.contains('dining') ||
      c.contains('meal') ||
      c.contains('fast food') ||
      c.contains('fastfood') ||
      c.contains('burger') ||
      c.contains('takeaway')) {
    return const ReceiptCardPalette(
      acc: Color(0xFFC75643),
      top: Color(0xFFF6E9E1),
      mid: Color(0xFFC68C76),
      tile: Color(0xFFEAD7CC),
      ink: Color(0xFF4F2D23),
      sub: Color(0xFFA07F72),
      emoji: '🍽️',
    );
  }

  // default
  return const ReceiptCardPalette(
    acc: Color(0xFFE2885C),
    top: Color(0xFFF4E8D6),
    mid: Color(0xFFC9A37C),
    tile: Color(0xFFEFDFC7),
    ink: Color(0xFF5A4632),
    sub: Color(0xFF9C8A72),
    emoji: '🧾',
  );
}

/// Bundled category illustration from [receipt_images/], if available.
String? receiptIllustrationAssetForCategory(String category) {
  final c = category.toLowerCase();

  if (c.contains('cafe') ||
      c.contains('coffee') ||
      c.contains('espresso') ||
      c.contains('latte') ||
      c.contains('tea') ||
      c.contains('boba') ||
      c.contains('bubble')) {
    return 'receipt_images/cafe.png';
  }

  if (c.contains('grocery') ||
      c.contains('groceries') ||
      c.contains('market') ||
      c.contains('supermarket')) {
    return 'receipt_images/grocery.png';
  }

  if (c.contains('restaurant') ||
      c.contains('dining') ||
      c.contains('food') ||
      c.contains('meal') ||
      c.contains('fast food') ||
      c.contains('fastfood') ||
      c.contains('burger') ||
      c.contains('takeaway')) {
    return 'receipt_images/restaurant.png';
  }

  return null;
}

String _formatReceiptTime(DateTime dt, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(dt.year, dt.month, dt.day);
  final timeStr = DateFormat('h:mm a').format(dt);
  if (d == today) return 'Today, $timeStr';
  if (d == today.subtract(const Duration(days: 1))) return 'Yesterday, $timeStr';
  return '${DateFormat('d MMM').format(dt)}, $timeStr';
}

String _receiptNumber(String id) {
  final clean = id.replaceAll('-', '');
  final suffix = clean.length >= 4
      ? clean.substring(clean.length - 4).toUpperCase()
      : clean.toUpperCase();
  return '#$suffix';
}

class ReceiptCard extends StatelessWidget {
  const ReceiptCard({super.key, required this.tx, this.onTap});

  final TransactionView tx;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = receiptPaletteForCategory(tx.effectiveCategory);
    final now = DateTime.now();
    final timeLabel = _formatReceiptTime(tx.occurredAt, now);
    final receiptNum = _receiptNumber(tx.id);
    final amountText = tx.amountMyr != null
        ? 'RM ${tx.amountMyr!.toStringAsFixed(2)}'
        : '—';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: palette.top,
          borderRadius: BorderRadius.circular(26),
          boxShadow: const [
            BoxShadow(
              color: Color(0x2E3C2814),
              blurRadius: 44,
              offset: Offset(0, 20),
            ),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top accent bar
            Container(height: 12, color: palette.acc),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      palette.emoji,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tx.displayPlace,
                          style: TextStyle(
                            fontFamily: 'Baloo 2',
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: palette.ink,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          timeLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: palette.sub,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: palette.tile,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🧾', style: TextStyle(fontSize: 12)),
                        const SizedBox(width: 4),
                        Text(
                          receiptNum,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: palette.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Category illustration — full-bleed, edge to edge
            SizedBox(
              height: 216,
              width: double.infinity,
              child: _ReceiptIllustration(
                tx: tx,
                palette: palette,
              ),
            ),

            // Items + total section
            Container(
              color: palette.mid,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                children: [
                  // Single item row
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: palette.tile,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          palette.emoji,
                          style: const TextStyle(fontSize: 17),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: tx.needsAmount
                            ? Text(
                                'Needs amount',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  fontStyle: FontStyle.italic,
                                  color: palette.ink.withValues(alpha: 0.6),
                                ),
                              )
                            : Text(
                                tx.displayPlace,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: palette.ink,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                      Text(
                        tx.needsAmount ? '' : amountText,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: palette.ink,
                        ),
                      ),
                    ],
                  ),

                  // Dashed divider
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: CustomPaint(
                      size: const Size(double.infinity, 2),
                      painter: _DashedLinePainter(
                        color: palette.ink.withValues(alpha: 0.28),
                      ),
                    ),
                  ),

                  // Total row
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.24),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: palette.ink,
                          ),
                        ),
                        Text(
                          tx.needsAmount ? 'Pending' : amountText,
                          style: TextStyle(
                            fontSize: 22,
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
      ),
    );
  }
}

class _ReceiptIllustration extends StatelessWidget {
  const _ReceiptIllustration({
    required this.tx,
    required this.palette,
  });

  final TransactionView tx;
  final ReceiptCardPalette palette;

  static const _illustrationHeight = 216.0;

  @override
  Widget build(BuildContext context) {
    final assetPath =
        receiptIllustrationAssetForCategory(tx.effectiveCategory);

    if (assetPath != null) {
      return Image.asset(
        assetPath,
        width: double.infinity,
        height: _illustrationHeight,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        errorBuilder: (context, error, stackTrace) => _placeholder(),
      );
    }

    final bytes = tx.thumbnailBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        width: double.infinity,
        height: _illustrationHeight,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        errorBuilder: (context, error, stackTrace) => _placeholder(),
      );
    }

    final thumbPath = tx.localThumbnailPath;
    if (thumbPath != null && thumbPath.isNotEmpty) {
      return SizedBox(
        width: double.infinity,
        height: _illustrationHeight,
        child: file_image.buildLocalFileImage(
          thumbPath,
          placeholder: _placeholder(),
        ),
      );
    }

    return _placeholder();
  }

  Widget _placeholder() {
    return ColoredBox(
      color: palette.top,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(palette.emoji, style: const TextStyle(fontSize: 52)),
            const SizedBox(height: 6),
            Text(
              tx.effectiveCategory,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: palette.sub,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const dashWidth = 6.0;
    const gapWidth = 5.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + gapWidth;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}
