import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/logic/misread_pattern_extractor.dart';

void main() {
  group('extractMisreadPatterns', () {
    test('identical strings emit nothing', () {
      expect(extractMisreadPatterns('12.50', '12.50'), isEmpty);
    });

    test('a single-digit localized fix emits one pattern', () {
      final patterns = extractMisreadPatterns('12.5O', '12.50');
      expect(patterns, hasLength(1));
      expect(patterns.single.fromChar, 'O');
      expect(patterns.single.toChar, '0');
    });

    test('two differing digits within budget emit both patterns', () {
      final patterns = extractMisreadPatterns('1Z.5O', '12.50');
      expect(patterns, hasLength(2));
      expect(patterns[0].fromChar, 'Z');
      expect(patterns[0].toChar, '2');
      expect(patterns[1].fromChar, 'O');
      expect(patterns[1].toChar, '0');
    });

    test('more than the alignment budget emits nothing (wholesale rewrite)',
        () {
      expect(extractMisreadPatterns('12.34', '99.99'), isEmpty);
    });

    test('different-length strings never align, emits nothing', () {
      expect(extractMisreadPatterns('9.50', '19.50'), isEmpty);
    });

    test('a decimal-point shift is not a digit misread, emits nothing', () {
      expect(extractMisreadPatterns('1.250', '12.50'), isEmpty);
    });

    test('the actual amount value never appears in emitted patterns', () {
      final patterns = extractMisreadPatterns('45.OO', '45.00');
      for (final p in patterns) {
        expect(p.fromChar, isNot(contains('45')));
        expect(p.toChar, isNot(contains('45')));
      }
      expect(patterns.map((p) => '${p.fromChar}${p.toChar}').join(),
          isNot(contains('45')));
    });
  });
}
