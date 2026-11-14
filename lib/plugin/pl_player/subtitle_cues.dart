/// Subtitles shown by Flutter while the iOS system player plays (mpv renders
/// its own). Parses WebVTT (bilibili subtitles are converted to it), SRT and
/// the dialogue lines of ASS/SSA.
class SubtitleCue {
  const SubtitleCue(this.start, this.end, this.text);

  /// Milliseconds.
  final int start;
  final int end;
  final String text;
}

abstract final class SubtitleCueParser {
  static final _timestamp = RegExp(
    r'(?:(\d+):)?(\d{1,2}):(\d{2})[.,](\d{1,3})',
  );
  static final _tags = RegExp(r'<[^>]*>');
  static final _assOverrides = RegExp(r'\{[^}]*\}');

  /// Cues sorted by start time.
  static List<SubtitleCue> parse(String content, {String? fileName}) {
    final lower = fileName?.toLowerCase() ?? '';
    final isAss =
        lower.endsWith('.ass') ||
        lower.endsWith('.ssa') ||
        content.contains('[Events]');
    final cues = isAss ? _parseAss(content) : _parseTimed(content);
    return cues..sort((a, b) => a.start.compareTo(b.start));
  }

  static int? _parseTime(String value) {
    final m = _timestamp.firstMatch(value);
    if (m == null) return null;
    final hours = int.parse(m[1] ?? '0');
    final minutes = int.parse(m[2]!);
    final seconds = int.parse(m[3]!);
    final fraction = m[4]!;
    // ".5" is half a second, ".05" (ASS centiseconds) is 50 ms.
    final millis = int.parse(fraction.padRight(3, '0'));
    return ((hours * 60 + minutes) * 60 + seconds) * 1000 + millis;
  }

  static String _unescape(String text) => text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');

  /// WebVTT and SRT: a "start --> end" line followed by text lines.
  static List<SubtitleCue> _parseTimed(String content) {
    final cues = <SubtitleCue>[];
    final lines = content.replaceAll('\r\n', '\n').split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final arrow = line.indexOf('-->');
      if (arrow < 0) continue;
      final start = _parseTime(line.substring(0, arrow));
      final end = _parseTime(line.substring(arrow + 3));
      if (start == null || end == null) continue;
      final text = <String>[];
      while (i + 1 < lines.length && lines[i + 1].trim().isNotEmpty) {
        i++;
        text.add(lines[i]);
      }
      final value = _unescape(
        text.join('\n').replaceAll(_tags, '').replaceAll(_assOverrides, ''),
      ).trim();
      if (value.isNotEmpty) cues.add(SubtitleCue(start, end, value));
    }
    return cues;
  }

  /// ASS/SSA: "Dialogue:" lines in the [Events] section, fields in the order
  /// of its "Format:" line.
  static List<SubtitleCue> _parseAss(String content) {
    final cues = <SubtitleCue>[];
    var fields = const [
      'layer', 'start', 'end', 'style', 'name', //
      'marginl', 'marginr', 'marginv', 'effect', 'text',
    ];
    var inEvents = false;
    for (final raw in content.replaceAll('\r\n', '\n').split('\n')) {
      final line = raw.trim();
      if (line.startsWith('[')) {
        inEvents = line.toLowerCase() == '[events]';
        continue;
      }
      if (!inEvents) continue;
      if (line.startsWith('Format:')) {
        fields = line
            .substring(7)
            .split(',')
            .map((e) => e.trim().toLowerCase())
            .toList();
        continue;
      }
      if (!line.startsWith('Dialogue:')) continue;
      // The text field is last and may itself contain commas.
      final parts = _splitFields(line.substring(9), fields.length);
      if (parts.length < fields.length) continue;
      final start = _parseTime(parts[fields.indexOf('start')]);
      final end = _parseTime(parts[fields.indexOf('end')]);
      final textIndex = fields.indexOf('text');
      if (start == null || end == null || textIndex < 0) continue;
      final text = parts[textIndex]
          .replaceAll(_assOverrides, '')
          .replaceAll(r'\N', '\n')
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\h', ' ')
          .trim();
      if (text.isNotEmpty) cues.add(SubtitleCue(start, end, text));
    }
    return cues;
  }

  static List<String> _splitFields(String value, int count) {
    final parts = <String>[];
    var rest = value;
    while (parts.length < count - 1) {
      final comma = rest.indexOf(',');
      if (comma < 0) break;
      parts.add(rest.substring(0, comma).trim());
      rest = rest.substring(comma + 1);
    }
    parts.add(rest);
    return parts;
  }
}
