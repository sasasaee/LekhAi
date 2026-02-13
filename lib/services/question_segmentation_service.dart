import 'dart:math';
import 'ocr_service.dart';

import '../models/paper_model.dart';

class _RowLine {
  final String text;
  final double l, t, r, b;
  final List<int> indices;

  _RowLine({
    required this.text,
    required this.l,
    required this.t,
    required this.r,
    required this.b,
    required this.indices,
  });

  double get yCenter => (t + b) / 2.0;
  double get height => (b - t).abs();
}

class QuestionSegmentationService {
  // --- regex patterns (tweakable) ---
  static final RegExp _qStart = RegExp(r'^\s*(\d{1,2})\s*[\.\)]\s+');
  static final RegExp _qStartAlt = RegExp(
    r'^\s*Q\s*[:.]?\s*(\d{1,3})\b',
    caseSensitive: false,
  );

  static final RegExp _partHeader = RegExp(
    r'^\s*Part\s*[A-Z]\b',
    caseSensitive: false,
  );
  static final RegExp _sectionHeader = RegExp(
    r'^\s*Section\s*[A-Z]\b',
    caseSensitive: false,
  );

  static final RegExp _marksExpr = RegExp(
    r'(\d+(\.\d+)?)\s*[x×]\s*(\d+)\s*=\s*(\d+(\.\d+)?)',
  );
  static final RegExp _marksWord = RegExp(
    r'\b(Marks?|Total Marks?)\b',
    caseSensitive: false,
  );

  ParsedDocument segment(List<OcrLine> rawLines) {
    if (rawLines.isEmpty) {
      return ParsedDocument(header: [], sections: []);
    }

    // Normalize + remove empty
    final lines = rawLines
        .map(
          (e) => OcrLine(
            index: e.index,
            text: e.text.trim(),
            l: e.l,
            t: e.t,
            r: e.r,
            b: e.b,
          ),
        )
        .where((e) => e.text.isNotEmpty)
        .toList();

    // Estimate page width/height for alignment heuristics
    final pageW = lines.map((e) => e.r).reduce(max);

    // Sort by top then left
    lines.sort((a, b) {
      final dy = a.t.compareTo(b.t);
      if (dy != 0) return dy;
      return a.l.compareTo(b.l);
    });

    // Build "row lines" by grouping similar y-centers (helps tables/word boxes)
    final rowLines = _mergeIntoRows(lines, pageW);

    // Now do sequential parsing
    final header = <String>[];
    final sections = <ParsedSection>[];

    ParsedSection currentSection = ParsedSection(
      title: null,
      context: null,
      questions: [],
    );
    ParsedQuestion? currentQuestion;

    void flushQuestion() {
      if (currentQuestion != null) {
        currentSection.questions.add(currentQuestion!);
        currentQuestion = null;
      }
    }

    void flushSectionIfHasContent() {
      flushQuestion();
      if (currentSection.questions.isNotEmpty ||
          (currentSection.title != null &&
              currentSection.title!.trim().isNotEmpty)) {
        sections.add(currentSection);
      }
    }

    for (final rl in rowLines) {
      final text = rl.text;

      // If this looks like a standalone marks expression on the far right, attach it
      if (_isRightSideMarksOnly(rl, pageW) && currentQuestion != null) {
        currentQuestion!.marks = _extractMarks(text) ?? currentQuestion!.marks;
        currentQuestion!.sourceLineIndices.addAll(rl.indices);
        continue;
      }

      // Section header like "Part A: Grammar (60 Marks)"
      if (_isSectionHeader(text)) {
        flushSectionIfHasContent();
        currentSection = ParsedSection(
          title: text,
          context: null,
          questions: [],
        );
        continue;
      }

      // New question start
      final qNum = _extractQuestionNumber(text);
      if (qNum != null) {
        flushQuestion();

        var prompt = _removeQuestionNumberPrefix(text);

        // Extract marks from same line if present
        final marks = _extractMarks(prompt) ?? _extractMarks(text);
        if (marks != null) {
          prompt = prompt.replaceAll(_marksExpr, '').trim();
        }

        currentQuestion = ParsedQuestion(
          number: qNum,
          prompt: prompt,
          body: [],
          marks: marks,
          sourceLineIndices: [...rl.indices],
        );
        continue;
      }

      // Not a question yet -> header region (especially top part of page)
      if (currentQuestion == null) {
        // heuristic: keep header mostly in top 35% OR until first question appears
        // (since we already handle question-start above, anything before that is header)
        // heuristic: keep header mostly in top 35% OR until first question appears
        // currently simplified to always add if not a question
        header.add(text);
        continue;
      }

      // Otherwise, it's question body
      // Merge continuation lines nicely: keep as separate lines, UI can join with '\n'
      currentQuestion!.body.add(text);
      currentQuestion!.sourceLineIndices.addAll(rl.indices);
    }

    // flush last
    flushSectionIfHasContent();

    // If no sections detected, put everything into one section
    if (sections.isEmpty && currentSection.questions.isNotEmpty) {
      sections.add(currentSection);
    }

    return ParsedDocument(header: header, sections: sections);
  }

  // ---------------- helpers ----------------

  bool _isSectionHeader(String s) {
    return _partHeader.hasMatch(s) || _sectionHeader.hasMatch(s);
  }

  String? _extractQuestionNumber(String s) {
    final m1 = _qStart.firstMatch(s);
    if (m1 != null) return m1.group(1);

    final m2 = _qStartAlt.firstMatch(s);
    if (m2 != null) return m2.group(1);

    return null;
  }

  String _removeQuestionNumberPrefix(String s) {
    final m1 = _qStart.firstMatch(s);
    if (m1 != null) return s.substring(m1.end).trim();

    final m2 = _qStartAlt.firstMatch(s);
    if (m2 != null) {
      // remove "Q1" style
      return s.replaceFirst(m2.group(0)!, '').trim();
    }

    return s.trim();
  }

  String? _extractMarks(String s) {
    final m = _marksExpr.firstMatch(s);
    if (m != null) return m.group(0);

    if (_marksWord.hasMatch(s)) return s; // fallback: "Total Marks: 100"
    return null;
  }

  bool _isRightSideMarksOnly(_RowLine rl, double pageW) {
    final isRight = rl.l > 0.70 * pageW; // right margin-ish
    if (!isRight) return false;

    final short = rl.text.length <= 25;
    final looksLikeMarks =
        _marksExpr.hasMatch(rl.text) ||
        rl.text.contains('×') ||
        rl.text.contains('x') ||
        rl.text.contains('=') ||
        _marksWord.hasMatch(rl.text);

    return short && looksLikeMarks;
  }

  List<_RowLine> _mergeIntoRows(List<OcrLine> lines, double pageW) {
    // Median line height
    final heights =
        lines.map((e) => (e.b - e.t).abs()).where((h) => h > 0).toList()
          ..sort();
    final medianH = heights.isEmpty ? 12.0 : heights[heights.length ~/ 2];
    final rowThreshold = max(6.0, 0.60 * medianH);

    final rows = <List<OcrLine>>[];
    List<OcrLine> current = [];
    double? currentYC;

    for (final ln in lines) {
      final yc = (ln.t + ln.b) / 2.0;
      if (current.isEmpty) {
        current.add(ln);
        currentYC = yc;
        continue;
      }

      if ((yc - currentYC!).abs() <= rowThreshold) {
        current.add(ln);
        // update center softly
        currentYC = (currentYC * 0.7) + (yc * 0.3);
      } else {
        rows.add(current);
        current = [ln];
        currentYC = yc;
      }
    }
    if (current.isNotEmpty) rows.add(current);

    // Convert each row to a single rowline
    final out = <_RowLine>[];
    for (final row in rows) {
      row.sort((a, b) => a.l.compareTo(b.l));

      final indices = <int>[];
      double l = double.infinity,
          t = double.infinity,
          r = -double.infinity,
          b = -double.infinity;

      // Join row cells: if big horizontal gaps, insert " | " (tables)
      final parts = <String>[];
      OcrLine? prev;

      for (final cell in row) {
        indices.add(cell.index);
        l = min(l, cell.l);
        t = min(t, cell.t);
        r = max(r, cell.r);
        b = max(b, cell.b);

        if (prev != null) {
          final gap = cell.l - prev.r;
          if (gap > 0.06 * pageW) {
            parts.add(" | "); // likely a table column split
          } else {
            parts.add(" ");
          }
        }
        parts.add(cell.text);
        prev = cell;
      }

      final joined = parts.join();
      // Add spacing around parenthesized items like (a) -> (a)
      // This helps the TTS service's regex match it correctly as a separate token
      final cleaned = joined.replaceAllMapped(
        RegExp(r'(?<=\w)\((?=[a-zA-Z0-9])|(?<=[a-zA-Z0-9])\)(?=\w)'),
        (m) => m.group(0) == '(' ? ' (' : ') ',
      );

      final text = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
      out.add(_RowLine(text: text, l: l, t: t, r: r, b: b, indices: indices));
    }

    // Second pass: remove duplicates / junk lines (optional)
    return out.where((rl) => rl.text.isNotEmpty).toList();
  }
}
