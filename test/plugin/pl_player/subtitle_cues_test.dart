import 'package:PiliPlus/plugin/pl_player/subtitle_cues.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses WebVTT with tags and multi-line cues', () {
    const vtt = '''WEBVTT

1
00:00:01.500 --> 00:00:03.000
<b>Hello</b> &amp; welcome

2
00:01:02.000 --> 00:01:04.250 align:middle
line one
line two
''';
    final cues = SubtitleCueParser.parse(vtt);
    expect(cues.length, 2);
    expect(cues[0].start, 1500);
    expect(cues[0].end, 3000);
    expect(cues[0].text, 'Hello & welcome');
    expect(cues[1].start, 62000);
    expect(cues[1].end, 64250);
    expect(cues[1].text, 'line one\nline two');
  });

  test('parses SRT with comma milliseconds and sorts by start', () {
    const srt =
        '2\r\n00:00:05,000 --> 00:00:06,000\r\nsecond\r\n\r\n'
        '1\r\n00:00:01,000 --> 00:00:02,000\r\n{\\an8}first\r\n';
    final cues = SubtitleCueParser.parse(srt, fileName: 'a.srt');
    expect(cues.map((e) => e.text), ['first', 'second']);
    expect(cues.first.start, 1000);
  });

  test('parses ASS dialogue lines with commas in the text', () {
    const ass = '''[Script Info]
Title: test

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.50,0:00:03.05,Default,,0,0,0,,{\\i1}Hi, there\\Nnext line
Comment: 0,0:00:04.00,0:00:05.00,Default,,0,0,0,,ignored
''';
    final cues = SubtitleCueParser.parse(ass, fileName: 'a.ass');
    expect(cues.length, 1);
    expect(cues[0].start, 1500);
    expect(cues[0].end, 3050);
    expect(cues[0].text, 'Hi, there\nnext line');
  });
}
