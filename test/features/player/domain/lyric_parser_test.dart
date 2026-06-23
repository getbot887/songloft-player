import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/features/player/domain/lyric_parser.dart';

void main() {
  group('LyricParser.stringify', () {
    test('formats time as [mm:ss.xxx]', () {
      const lines = [
        LyricLine(time: Duration(milliseconds: 1500), text: 'hello'),
        LyricLine(
          time: Duration(minutes: 1, seconds: 23, milliseconds: 456),
          text: 'world',
        ),
      ];
      expect(LyricParser.stringify(lines), '[00:01.500]hello\n[01:23.456]world\n');
    });

    test('sorts lines before serializing', () {
      const lines = [
        LyricLine(time: Duration(seconds: 5), text: 'b'),
        LyricLine(time: Duration(seconds: 2), text: 'a'),
      ];
      expect(LyricParser.stringify(lines), '[00:02.000]a\n[00:05.000]b\n');
    });

    test('clamps negative times to zero', () {
      const lines = [
        LyricLine(time: Duration(seconds: -3), text: 'x'),
      ];
      expect(LyricParser.stringify(lines), '[00:00.000]x\n');
    });

    test('parse(stringify(parse(lrc))) round-trips', () {
      const original = '[00:01.500]hello\n[01:23.456]world\n';
      final parsed = LyricParser.parse(original);
      final out = LyricParser.stringify(parsed);
      expect(LyricParser.parse(out).map((l) => l.time.inMilliseconds).toList(),
          [1500, 83456]);
    });

    test('returns empty string for empty input', () {
      expect(LyricParser.stringify(const []), '');
    });
  });

  group('LyricParser.applyOffset', () {
    test('shifts each line by given offset', () {
      const lines = [
        LyricLine(time: Duration(seconds: 1), text: 'a'),
        LyricLine(time: Duration(seconds: 2), text: 'b'),
      ];
      final shifted = LyricParser.applyOffset(lines, const Duration(milliseconds: 500));
      expect(shifted[0].time, const Duration(milliseconds: 1500));
      expect(shifted[1].time, const Duration(milliseconds: 2500));
    });

    test('clamps negative result to zero', () {
      const lines = [
        LyricLine(time: Duration(milliseconds: 200), text: 'a'),
        LyricLine(time: Duration(seconds: 5), text: 'b'),
      ];
      final shifted =
          LyricParser.applyOffset(lines, const Duration(seconds: -1));
      expect(shifted[0].time, Duration.zero);
      expect(shifted[1].time, const Duration(seconds: 4));
    });

    test('preserves text', () {
      const lines = [LyricLine(time: Duration(seconds: 1), text: 'hello')];
      final shifted =
          LyricParser.applyOffset(lines, const Duration(milliseconds: 100));
      expect(shifted.single.text, 'hello');
    });
  });
}
