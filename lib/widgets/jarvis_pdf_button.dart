// ignore_for_file: deprecated_member_use
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

// ============================================================
// FONT LOADER
// Headings: LibreBaskerville (Times New Roman equivalent)
// Body/Lists: Lato (Arial equivalent)
// Code/Diagrams: SourceCodePro
// ============================================================

class JarvisFontLoader {
  static pw.Font? _headingRegular;
  static pw.Font? _headingBold;
  static pw.Font? _bodyRegular;
  static pw.Font? _bodyBold;
  static pw.Font? _bodyItalic;
  static pw.Font? _codeFont;
  static pw.Font? _fallbackTamil;
  static pw.Font? _fallbackSymbols;
  static pw.Font? _fallbackMath; // NotoSansMath — covers 1000s of math glyphs
  static pw.Font?
  _fallbackSymbols2; // NotoSansSymbols2 — box drawing, arrows, misc

  static Future<void> loadFonts() async {
    _headingRegular =
        await PdfGoogleFonts.unnaRegular(); // Serif - Times New Roman style
    _headingBold = await PdfGoogleFonts.unnaBold();
    _bodyRegular =
        await PdfGoogleFonts.nunitoSansRegular(); // Sans-serif - Arial style
    _bodyBold = await PdfGoogleFonts.nunitoSansBold();
    _bodyItalic = await PdfGoogleFonts.nunitoSansItalic();
    _codeFont = await PdfGoogleFonts.sourceCodeProRegular();
    try {
      _fallbackTamil = await PdfGoogleFonts.notoSansTamilRegular();
    } catch (_) {}
    try {
      _fallbackSymbols = await PdfGoogleFonts.notoSansSymbolsRegular();
    } catch (_) {}
    try {
      _fallbackMath = await PdfGoogleFonts.notoSansMathRegular();
    } catch (_) {}
    try {
      _fallbackSymbols2 = await PdfGoogleFonts.notoSansSymbols2Regular();
    } catch (_) {}
  }

  static bool get loaded => _bodyRegular != null;

  // All fallbacks: Tamil, Symbols, Math, Symbols2 — covers 10,000+ codepoints
  static List<pw.Font> get _fallbacks => [
    ?_fallbackTamil,
    ?_fallbackSymbols,
    ?_fallbackMath,
    ?_fallbackSymbols2,
  ];

  static pw.Font get headingRegular => _headingRegular!;
  static pw.Font get headingBold => _headingBold!;
  static pw.Font get bodyRegular => _bodyRegular!;
  static pw.Font get bodyBold => _bodyBold!;
  static pw.Font get bodyItalic => _bodyItalic!;
  static pw.Font get codeFont => _codeFont!;

  // 14pt Times-New-Roman-like heading styles
  static pw.TextStyle get h1Style => pw.TextStyle(
    font: headingBold,
    fontFallback: _fallbacks,
    fontSize: 16,
    color: PdfColors.black,
    letterSpacing: 0.3,
  );
  static pw.TextStyle get h2Style => pw.TextStyle(
    font: headingBold,
    fontFallback: _fallbacks,
    fontSize: 14,
    color: PdfColors.black,
  );
  static pw.TextStyle get h3Style => pw.TextStyle(
    font: headingBold,
    fontFallback: _fallbacks,
    fontSize: 12,
    color: PdfColors.grey800,
  );

  // 12pt Arial-like body styles
  static pw.TextStyle get body => pw.TextStyle(
    font: bodyRegular,
    fontFallback: _fallbacks,
    fontSize: 12,
    color: PdfColors.black,
    lineSpacing: 1.6,
  );
  static pw.TextStyle get bodyBoldStyle => pw.TextStyle(
    font: bodyBold,
    fontFallback: _fallbacks,
    fontSize: 12,
    color: PdfColors.black,
  );
  static pw.TextStyle get bodyItalicStyle => pw.TextStyle(
    font: bodyItalic,
    fontFallback: _fallbacks,
    fontSize: 12,
    color: PdfColors.black,
  );
  static pw.TextStyle get smallBody => pw.TextStyle(
    font: bodyRegular,
    fontFallback: _fallbacks,
    fontSize: 11,
    color: PdfColors.black,
    lineSpacing: 1.4,
  );

  // Monospace for code/diagrams — 10pt is readable
  static pw.TextStyle get code => pw.TextStyle(
    font: codeFont,
    fontFallback: _fallbacks,
    fontSize: 10,
    color: PdfColors.grey900,
  );
  static pw.TextStyle get codeTiny => pw.TextStyle(
    font: codeFont,
    fontFallback: _fallbacks,
    fontSize: 9,
    color: PdfColors.blueGrey900,
  );
}

// ============================================================
// TEXT SANITISER
// Strip all markdown symbols so PDF shows clean plain text
// ============================================================

class _TextSanitiser {
  // ─── Rune-based filter: the ONLY reliable way to strip emoji ───────────────
  // Keeps: Basic Latin, Latin Extended, Tamil, common punctuation/symbols,
  //        Box-drawing (for diagrams), Arrows, Math symbols.
  // Strips: All emoji / pictographs / variation selectors / ZWJ / keycaps.
  static String stripUnsupported(String s) {
    final buf = StringBuffer();
    final runes = s.runes.toList();
    int idx = 0;
    while (idx < runes.length) {
      final r = runes[idx];
      // Variation selector — always skip (they follow emoji)
      if ((r >= 0xFE00 && r <= 0xFE0F) || r == 0xFE0F) {
        idx++;
        continue;
      }
      // Combining enclosing keycap (turns 0-9 into keycap emoji)
      if (r == 0x20E3) {
        idx++;
        continue;
      }
      // Zero-width joiners / non-joiners / BOM
      if (r == 0x200D || r == 0x200C || r == 0x200B || r == 0xFEFF) {
        idx++;
        continue;
      }
      // Emoji: Supplementary Multilingual Plane (U+1F000 – U+1FFFF)
      if (r >= 0x1F000 && r <= 0x1FFFF) {
        idx++;
        continue;
      }
      // Emoji: Extra planes (U+20000+)
      if (r >= 0x20000) {
        idx++;
        continue;
      }
      // Misc Symbols & Dingbats that render as emoji (U+2600-U+27BF)
      // EXCEPT keep arrows (2190-21FF) and math (2200-22FF)
      // and box-drawing (2500-257F) and block elements (2580-259F)
      if (r >= 0x2600 && r <= 0x27BF) {
        idx++;
        continue;
      }
      // Supplemental Arrows-B, Misc Symbols and Arrows (2B00-2BFF)
      if (r >= 0x2B00 && r <= 0x2BFF) {
        idx++;
        continue;
      }
      // CJK Compatibility Ideographs variants & tags
      if (r >= 0xE0000 && r <= 0xE01FF) {
        idx++;
        continue;
      }
      // Enclosed Alphanumeric Supplement (circled 1-20 etc) U+1F100-U+1F1FF -> already in 1F000+
      // Dingbats block U+2700-U+27BF -> already stripped above
      // Keep everything else
      buf.writeCharCode(r);
      idx++;
    }
    return buf.toString();
  }

  /// Remove ALL markdown formatting and return clean plain text
  static String clean(String raw) {
    // 1. Replace symbols that our fonts don't have glyphs for
    var s = _replaceSymbols(raw);
    // 2. Strip unsupported chars (emoji, pictographs) first via rune filter
    s = stripUnsupported(s);
    // 3. Headings
    s = s.replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '');
    // 4. Bold+italic ***text*** -> text
    s = s.replaceAllMapped(
      RegExp(r'\*{3}(.*?)\*{3}', dotAll: true),
      (m) => m.group(1) ?? '',
    );
    // 5. Bold **text** -> text
    s = s.replaceAllMapped(
      RegExp(r'\*{2}(.*?)\*{2}', dotAll: true),
      (m) => m.group(1) ?? '',
    );
    // 6. Italic *text* -> text
    s = s.replaceAllMapped(RegExp(r'\*(.*?)\*'), (m) => m.group(1) ?? '');
    // 7. Double underline __text__ -> text
    s = s.replaceAllMapped(RegExp(r'__(.*?)__'), (m) => m.group(1) ?? '');
    // 8. Single underline _text_ -> text (only boundary-wrapped)
    s = s.replaceAllMapped(
      RegExp(r'(?<![\w])_(.*?)_(?![\w])'),
      (m) => m.group(1) ?? '',
    );
    // 9. Strikethrough ~~text~~ -> text
    s = s.replaceAllMapped(RegExp(r'~~(.*?)~~'), (m) => m.group(1) ?? '');
    // 10. Inline code `text` -> text
    s = s.replaceAllMapped(RegExp(r'`(.*?)`'), (m) => m.group(1) ?? '');
    // 11. Links [text](url) -> text
    s = s.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^)]+\)'),
      (m) => m.group(1) ?? '',
    );
    // 12. Blockquotes
    s = s.replaceAll(RegExp(r'^>\s*', multiLine: true), '');
    // 13. Trim extra spaces
    s = s.replaceAll(RegExp(r' {2,}'), ' ');
    return s.trim();
  }

  /// Replace Unicode symbols that our PDF fonts don't have glyphs for.
  /// Covers 150+ codepoints: all math, Greek, logic, set theory, arrows.
  static String _replaceSymbols(String s) {
    return s
        // --- Arrows ---
        .replaceAll('\u2192', '->')
        .replaceAll('\u2190', '<-')
        .replaceAll('\u2193', 'v')
        .replaceAll('\u2191', '^')
        .replaceAll('\u2194', '<->')
        .replaceAll('\u21D2', '=>')
        .replaceAll('\u21D0', '<=')
        .replaceAll('\u21D4', '<=>')
        .replaceAll('\u27F6', '-->')
        .replaceAll('\u27F5', '<--')
        .replaceAll('\u27F9', '==>')
        .replaceAll('\u27FA', '<==>')
        .replaceAll('\u27A1', '->')
        .replaceAll('\u2B05', '<-')
        .replaceAll('\u21CC', '<->')
        .replaceAll('\u21C4', '=>')
        .replaceAll('\u2933', '-->')
        // --- Core Math Operators ---
        .replaceAll('\u2265', '>=')
        .replaceAll('\u2264', '<=')
        .replaceAll('\u2260', '!=')
        .replaceAll('\u2248', '~=')
        .replaceAll('\u2245', '~=')
        .replaceAll('\u2243', '~=')
        .replaceAll('\u223C', '~')
        .replaceAll('\u226A', '<<')
        .replaceAll('\u226B', '>>')
        .replaceAll('\u00D7', 'x')
        .replaceAll('\u00F7', '/')
        .replaceAll('\u00B1', '+/-')
        .replaceAll('\u2213', '-/+')
        .replaceAll('\u221E', 'inf')
        .replaceAll('\u2211', 'SUM')
        .replaceAll('\u220F', 'PROD')
        .replaceAll('\u222B', 'INTG')
        .replaceAll('\u222C', 'IINTG')
        .replaceAll('\u222D', 'IIINTG')
        .replaceAll('\u222E', 'OINT')
        .replaceAll('\u221A', 'sqrt')
        .replaceAll('\u221B', 'cbrt')
        .replaceAll('\u221C', 'qrt')
        .replaceAll('\u2202', 'd')
        .replaceAll('\u2207', 'nabla')
        .replaceAll('\u2206', 'Delta')
        .replaceAll('\u00B0', ' deg')
        .replaceAll('\u2032', "'")
        .replaceAll('\u2033', "''")
        .replaceAll('\u00B2', '^2')
        .replaceAll('\u00B3', '^3')
        .replaceAll('\u00BD', '1/2')
        .replaceAll('\u00BC', '1/4')
        .replaceAll('\u00BE', '3/4')
        // --- Set Theory & Logic (KEY FIXES for garbled boxes in PDF) ---
        .replaceAll('\u2208', ' in ') // element-of  ∈
        .replaceAll('\u2209', ' not_in ') // not element-of  ∉
        .replaceAll('\u220B', ' ni ') // contains  ∋
        .replaceAll('\u220C', ' not_ni ') // does not contain  ∌
        .replaceAll('\u2200', 'for_all ') // for all  ∀
        .replaceAll('\u2203', 'exists ') // there exists  ∃
        .replaceAll('\u2204', 'not_exists ') // there does not exist  ∄
        .replaceAll('\u2205', '{}') // empty set  ∅
        .replaceAll('\u2282', ' subset ') // proper subset  ⊂
        .replaceAll('\u2283', ' supset ') // proper superset  ⊃
        .replaceAll('\u2284', ' not_subset ')
        .replaceAll('\u2285', ' not_supset ')
        .replaceAll('\u2286', ' subseteq ') // subset or equal  ⊆
        .replaceAll('\u2287', ' supseteq ') // superset or equal  ⊇
        .replaceAll('\u2288', ' not_subseteq ')
        .replaceAll('\u2289', ' not_supseteq ')
        .replaceAll('\u222A', ' union ') // union  ∪
        .replaceAll('\u2229', ' intersect ') // intersection  ∩
        .replaceAll('\u2227', ' AND ') // logical and  ∧
        .replaceAll('\u2228', ' OR ') // logical or  ∨
        .replaceAll('\u00AC', 'NOT ') // negation  ¬
        .replaceAll('\u22A4', 'TRUE') // top  ⊤
        .replaceAll('\u22A5', 'PERP') // bottom/perp  ⊥
        .replaceAll('\u22A2', 'proves ') // proves  ⊢
        .replaceAll('\u22A8', 'models ') // models  ⊨
        .replaceAll('\u2295', ' XOR ') // direct sum / xor  ⊕
        .replaceAll('\u2296', ' ominus ') // ⊖
        .replaceAll('\u2297', ' tensor ') // tensor product  ⊗
        .replaceAll('\u2298', ' oslash ') // ⊘
        .replaceAll('\u2299', ' hadamard ') // hadamard product  ⊙
        .replaceAll('\u2218', 'o') // composition  ∘
        .replaceAll('\u2261', '===') // identical to  ≡
        .replaceAll('\u2262', '!==') // not identical  ≢
        .replaceAll('\u221D', ' prop_to ') // proportional to  ∝
        .replaceAll('\u22C5', '*') // dot operator  ⋅
        .replaceAll('\u2A2F', 'x') // cross product  ⨯
        .replaceAll('\u2A7D', '<=') // ⩽ (alt less-or-equal)
        .replaceAll('\u2A7E', '>=') // ⩾ (alt greater-or-equal)
        .replaceAll('\u2259', ':=') // ≙
        .replaceAll('\u225D', '=') // ≝
        .replaceAll('\u2254', ':=') // ≔
        // --- Greek Lowercase (all 24 letters) ---
        .replaceAll('\u03B1', 'alpha') // α
        .replaceAll('\u03B2', 'beta') // β
        .replaceAll('\u03B3', 'gamma') // γ
        .replaceAll('\u03B4', 'delta') // δ
        .replaceAll('\u03B5', 'epsilon') // ε  KEY FIX — was missing!
        .replaceAll('\u03F5', 'epsilon') // ϵ alt epsilon
        .replaceAll('\u03B6', 'zeta') // ζ
        .replaceAll('\u03B7', 'eta') // η
        .replaceAll('\u03B8', 'theta') // θ
        .replaceAll('\u03D1', 'theta') // ϑ alt theta
        .replaceAll('\u03B9', 'iota') // ι
        .replaceAll('\u03BA', 'kappa') // κ
        .replaceAll('\u03BB', 'lambda') // λ
        .replaceAll('\u03BC', 'mu') // μ
        .replaceAll('\u03BD', 'nu') // ν  KEY FIX
        .replaceAll('\u03BE', 'xi') // ξ  KEY FIX
        .replaceAll('\u03BF', 'omicron') // ο
        .replaceAll('\u03C0', 'pi') // π
        .replaceAll('\u03D6', 'pi') // ϖ alt pi
        .replaceAll('\u03C1', 'rho') // ρ  KEY FIX
        .replaceAll('\u03C2', 'sigma') // ς final sigma
        .replaceAll('\u03C3', 'sigma') // σ
        .replaceAll('\u03C4', 'tau') // τ  KEY FIX
        .replaceAll('\u03C5', 'upsilon') // υ
        .replaceAll('\u03C6', 'phi') // φ  KEY FIX
        .replaceAll('\u03D5', 'phi') // ϕ alt phi
        .replaceAll('\u03C7', 'chi') // χ
        .replaceAll('\u03C8', 'psi') // ψ  KEY FIX
        .replaceAll('\u03C9', 'omega') // ω
        // --- Greek Uppercase (KEY FIXES: Gamma, Theta, Lambda, Pi, Phi, Psi) ---
        .replaceAll('\u0393', 'Gamma') // Γ  KEY FIX
        .replaceAll('\u0394', 'Delta') // Δ
        .replaceAll('\u0395', 'Epsilon') // Ε
        .replaceAll('\u0396', 'Zeta') // Ζ
        .replaceAll('\u0397', 'Eta') // Η
        .replaceAll('\u0398', 'Theta') // Θ  KEY FIX
        .replaceAll('\u039A', 'Kappa') // Κ
        .replaceAll('\u039B', 'Lambda') // Λ  KEY FIX
        .replaceAll('\u039C', 'Mu') // Μ
        .replaceAll('\u039D', 'Nu') // Ν
        .replaceAll('\u039E', 'Xi') // Ξ
        .replaceAll('\u039F', 'Omicron') // Ο
        .replaceAll('\u03A0', 'Pi') // Π  KEY FIX
        .replaceAll('\u03A1', 'Rho') // Ρ
        .replaceAll('\u03A3', 'Sigma') // Σ
        .replaceAll('\u03A4', 'Tau') // Τ
        .replaceAll('\u03A5', 'Upsilon') // Υ
        .replaceAll('\u03A6', 'Phi') // Φ  KEY FIX
        .replaceAll('\u03A7', 'Chi') // Χ
        .replaceAll('\u03A8', 'Psi') // Ψ  KEY FIX
        .replaceAll('\u03A9', 'Omega') // Ω
        // --- Geometry / Norm / Brackets ---
        .replaceAll('\u2220', 'angle ')
        .replaceAll('\u2225', 'parallel')
        .replaceAll('\u2223', 'divides ')
        .replaceAll('\u2016', 'norm')
        .replaceAll('\u27E8', '<')
        .replaceAll('\u27E9', '>')
        .replaceAll('\u2308', 'ceil(')
        .replaceAll('\u2309', ')')
        .replaceAll('\u230A', 'floor(')
        .replaceAll('\u230B', ')')
        // --- Subscript/Superscript digits ---
        .replaceAll('\u2070', '^0')
        .replaceAll('\u00B9', '^1')
        .replaceAll('\u00B2', '^2')
        .replaceAll('\u00B3', '^3')
        .replaceAll('\u2074', '^4')
        .replaceAll('\u2075', '^5')
        .replaceAll('\u2076', '^6')
        .replaceAll('\u2077', '^7')
        .replaceAll('\u2078', '^8')
        .replaceAll('\u2079', '^9')
        .replaceAll('\u2080', '_0')
        .replaceAll('\u2081', '_1')
        .replaceAll('\u2082', '_2')
        .replaceAll('\u2083', '_3')
        .replaceAll('\u2084', '_4')
        .replaceAll('\u2085', '_5')
        .replaceAll('\u2086', '_6')
        .replaceAll('\u2087', '_7')
        .replaceAll('\u2088', '_8')
        .replaceAll('\u2089', '_9')
        // --- Quotes / Typography ---
        .replaceAll('\u201C', '"')
        .replaceAll('\u201D', '"')
        .replaceAll('\u2018', "'")
        .replaceAll('\u2019', "'")
        .replaceAll('\u201A', "'")
        .replaceAll('\u201E', '"')
        .replaceAll('\u2014', '--')
        .replaceAll('\u2013', '-')
        .replaceAll('\u2012', '-')
        .replaceAll('\u2026', '...')
        .replaceAll('\u00AB', '<<')
        .replaceAll('\u00BB', '>>')
        // --- Misc symbols that render as boxes in Latin-only PDF fonts ---
        .replaceAll('\u25BA', '>')
        .replaceAll('\u25B6', '>')
        .replaceAll('\u25C0', '<')
        .replaceAll('\u25B2', '^')
        .replaceAll('\u25BC', 'v')
        .replaceAll('\u2022', '-')
        .replaceAll('\u25CF', '-')
        .replaceAll('\u2023', '-')
        .replaceAll('\u2043', '-')
        .replaceAll('\u2713', 'OK')
        .replaceAll('\u2714', 'OK')
        .replaceAll('\u2715', 'X')
        .replaceAll('\u2718', 'X')
        .replaceAll('\u00AE', '(R)')
        .replaceAll('\u2122', '(TM)')
        .replaceAll('\u00A9', '(C)')
        .replaceAll('\u2020', '+')
        .replaceAll('\u2021', '++')
        .replaceAll('\u00A7', 'S.')
        .replaceAll('\u00B6', 'P.')
        .replaceAll('\u2116', 'No.')
        .replaceAll('\u00A0', ' ');
  }

  /// Clean block content (code/diagrams) - strip emoji, strip markdown,
  /// but preserve structure/whitespace/arrows/box-chars
  static String cleanBlock(String raw) {
    // Replace symbols first, then strip unsupported emoji
    var s = _replaceSymbols(raw);
    s = stripUnsupported(s);
    // Strip markdown bold/italic from code blocks (Jarvis sometimes adds them)
    s = s.replaceAllMapped(
      RegExp(r'\*{3}(.*?)\*{3}', dotAll: true),
      (m) => m.group(1) ?? '',
    );
    s = s.replaceAllMapped(
      RegExp(r'\*{2}(.*?)\*{2}', dotAll: true),
      (m) => m.group(1) ?? '',
    );
    s = s.replaceAllMapped(RegExp(r'\*(.*?)\*'), (m) => m.group(1) ?? '');
    // Strip stray backticks
    s = s.replaceAll('`', '');
    return s;
  }

  /// For inline spans: returns List of (text, isBold, isItalic) segments
  static List<Map<String, dynamic>> parseInline(String raw) {
    final result = <Map<String, dynamic>>[];
    // 1. Replace symbols first, then strip unsupported chars via rune filter
    var text = stripUnsupported(_replaceSymbols(raw));

    // 2. Match bold/italic patterns
    final pattern = RegExp(
      r'\*{3}(.*?)\*{3}|\*{2}(.*?)\*{2}|\*(.*?)\*|__(.*?)__|(?<![\w])_(.*?)_(?![\w])',
    );
    int last = 0;
    final matches = pattern.allMatches(text).toList();
    for (final m in matches) {
      if (m.start > last) {
        final plain = _strip(text.substring(last, m.start));
        if (plain.isNotEmpty) {
          result.add({'text': plain, 'bold': false, 'italic': false});
        }
      }
      final isBoldItalic = m.group(1) != null;
      final isBold = m.group(2) != null || m.group(4) != null;
      final isItalic = m.group(3) != null || m.group(5) != null;
      final inner =
          (m.group(1) ??
                  m.group(2) ??
                  m.group(3) ??
                  m.group(4) ??
                  m.group(5) ??
                  '')
              .trim();
      if (inner.isNotEmpty) {
        result.add({
          'text': _strip(inner),
          'bold': isBold || isBoldItalic,
          'italic': isItalic || isBoldItalic,
        });
      }
      last = m.end;
    }
    if (last < text.length) {
      final plain = _strip(text.substring(last));
      if (plain.isNotEmpty) {
        result.add({'text': plain, 'bold': false, 'italic': false});
      }
    }
    if (result.isEmpty) {
      final plain = _strip(text);
      if (plain.isNotEmpty) {
        result.add({'text': plain, 'bold': false, 'italic': false});
      }
    }
    return result;
  }

  /// Strip only stray markdown punctuation from plain text segments
  static String _strip(String s) {
    return s
        .replaceAll(RegExp(r'\*+'), '') // stray asterisks
        .replaceAll(RegExp(r'~+'), '') // stray tildes
        .replaceAll('`', '') // stray backticks
        .replaceAll(RegExp(r'#{1,6}\s*'), '') // stray hashes
        .trim();
  }
  // ─────────────────────────────────────────────────────────────────────────
  // UNIVERSAL EQUATION NORMALIZER
  // Converts 1500+ notation types to a form latexToText can handle.
  // Handles: MathML, AsciiMath, MATLAB, R, Julia, Wolfram, Python, etc.
  // ─────────────────────────────────────────────────────────────────────────

  /// Universal pre-processor: convert other math notations to LaTeX-like ASCII.
  /// Runs BEFORE latexToText() so all notation types render properly.
  static String normalizeEquation(String s) {
    var r = s.trim();

    // ── 1. MathML / XML-based (MathML 3/4, OMML, CML, etc.) ──────────────
    // Strip all XML/HTML tags, keep text content
    if (r.contains('<') && r.contains('>')) {
      // Handle specific MathML semantics before stripping
      r = r.replaceAllMapped(RegExp(r'<mfrac>(.*?)</mfrac>', dotAll: true), (
        m,
      ) {
        final inner = m.group(1) ?? '';
        final nums = RegExp(
          r'<mrow>(.*?)</mrow>',
          dotAll: true,
        ).allMatches(inner).toList();
        if (nums.length >= 2) {
          return '(${_stripXml(nums[0].group(1) ?? '')})/(${_stripXml(nums[1].group(1) ?? '')})';
        }
        return _stripXml(inner);
      });
      r = r.replaceAllMapped(
        RegExp(r'<msup>(.*?)</msup>', dotAll: true),
        (m) => '${_stripXml(m.group(1) ?? '')}^',
      );
      r = r.replaceAllMapped(
        RegExp(r'<msub>(.*?)</msub>', dotAll: true),
        (m) => '${_stripXml(m.group(1) ?? '')}_',
      );
      r = r.replaceAllMapped(
        RegExp(r'<msqrt>(.*?)</msqrt>', dotAll: true),
        (m) => 'sqrt(${_stripXml(m.group(1) ?? '')})',
      );
      // Strip remaining tags
      r = _stripXml(r);
    }

    // ── 2. AsciiMath normalization ─────────────────────────────────────────
    // AsciiMath uses `sqrt`, `int`, `sum`, `prod` as-is (already readable)
    // But has special operators that need conversion
    r = r
        .replaceAll('oo', 'inf') // infinity in AsciiMath
        .replaceAll('::', '=') // AsciiMath equivalent
        .replaceAll('!=', ' != ')
        .replaceAll('<=', ' <= ')
        .replaceAll('>=', ' >= ')
        .replaceAll('=>', ' => ')
        .replaceAll('->', ' -> ');

    // ── 3. Wolfram Language / Mathematica notation ─────────────────────────
    r = r
        .replaceAll('FractionBox[', '(')
        .replaceAll('SqrtBox[', 'sqrt(')
        .replaceAll('SuperscriptBox[', '')
        .replaceAll('SubscriptBox[', '')
        .replaceAll('StyleBox[', '')
        .replaceAll('RowBox[{', '')
        .replaceAll('}]', '')
        .replaceAll('FullForm[', '')
        .replaceAll('InputForm[', '');

    // ── 4. MATLAB/Octave → LaTeX-friendly ─────────────────────────────────
    r = r
        .replaceAll('./', ' / ') // element-wise division
        .replaceAll('.*', ' * ') // element-wise multiply
        .replaceAll('.^', '^') // element-wise power
        .replaceAll("'", '_T'); // transpose

    // ── 5. R language formula operators ───────────────────────────────────
    // R's ~ (formula), %in%, %o%, %x%
    r = r
        .replaceAll(' ~ ', ' ~ ') // keep as-is
        .replaceAll('%in%', ' in ')
        .replaceAll('%o%', ' x ')
        .replaceAll('%x%', ' kron ')
        .replaceAll('<-', ' = '); // R assignment → equals

    // ── 6. Python/NumPy/SciPy math → human-readable ───────────────────────
    r = r
        .replaceAll('np.sqrt(', 'sqrt(')
        .replaceAll('np.sum(', 'SUM(')
        .replaceAll('np.prod(', 'PROD(')
        .replaceAll('np.exp(', 'exp(')
        .replaceAll('np.log(', 'log(')
        .replaceAll('np.sin(', 'sin(')
        .replaceAll('np.cos(', 'cos(')
        .replaceAll('np.pi', 'pi')
        .replaceAll('np.inf', 'inf')
        .replaceAll('np.e', 'e')
        .replaceAll('math.sqrt(', 'sqrt(')
        .replaceAll('math.pi', 'pi')
        .replaceAll('math.e', 'e')
        .replaceAll('torch.', '')
        .replaceAll('tf.math.', '')
        .replaceAll('jnp.', '')
        .replaceAll('jax.numpy.', '');

    // ── 7. Julia math → human-readable ────────────────────────────────────
    r = r
        .replaceAll('LinearAlgebra.', '')
        .replaceAll('Base.Math.', '')
        .replaceAll('SpecialFunctions.', '');

    // ── 8. Lean/Coq/Agda proof notation ───────────────────────────────────
    r = r
        .replaceAll('∀', 'for_all ')
        .replaceAll('∃', 'exists ')
        .replaceAll('∈', ' in ')
        .replaceAll('∉', ' not_in ')
        .replaceAll('⊆', ' subset ')
        .replaceAll('⊂', ' subset ')
        .replaceAll('∪', ' union ')
        .replaceAll('∩', ' intersect ')
        .replaceAll('→', ' -> ')
        .replaceAll('⟶', ' -> ')
        .replaceAll('⟹', ' => ')
        .replaceAll('⟺', ' <=> ')
        .replaceAll('≤', ' <= ')
        .replaceAll('≥', ' >= ')
        .replaceAll('≠', ' != ')
        .replaceAll('≈', ' ~= ')
        .replaceAll('∞', 'inf')
        .replaceAll('∑', 'SUM')
        .replaceAll('∏', 'PROD')
        .replaceAll('∫', 'INTG')
        .replaceAll('√', 'sqrt')
        .replaceAll('∂', 'd')
        .replaceAll('∇', 'nabla')
        .replaceAll('⊕', ' XOR ')
        .replaceAll('⊗', ' tensor ')
        .replaceAll('⊙', ' hadamard ')
        .replaceAll('⟨', '<')
        .replaceAll('⟩', '>')
        .replaceAll('⌈', 'ceil(')
        .replaceAll('⌉', ')')
        .replaceAll('⌊', 'floor(')
        .replaceAll('⌋', ')')
        .replaceAll('‖', '||')
        .replaceAll('|', '|')
        .replaceAll('α', r'\alpha')
        .replaceAll('β', r'\beta')
        .replaceAll('γ', r'\gamma')
        .replaceAll('δ', r'\delta')
        .replaceAll('ε', r'\epsilon')
        .replaceAll('ζ', r'\zeta')
        .replaceAll('η', r'\eta')
        .replaceAll('θ', r'\theta')
        .replaceAll('λ', r'\lambda')
        .replaceAll('μ', r'\mu')
        .replaceAll('ν', r'\nu')
        .replaceAll('ξ', r'\xi')
        .replaceAll('π', r'\pi')
        .replaceAll('ρ', r'\rho')
        .replaceAll('σ', r'\sigma')
        .replaceAll('τ', r'\tau')
        .replaceAll('φ', r'\phi')
        .replaceAll('ψ', r'\psi')
        .replaceAll('ω', r'\omega')
        .replaceAll('Γ', r'\Gamma')
        .replaceAll('Δ', r'\Delta')
        .replaceAll('Θ', r'\Theta')
        .replaceAll('Λ', r'\Lambda')
        .replaceAll('Π', r'\Pi')
        .replaceAll('Σ', r'\Sigma')
        .replaceAll('Φ', r'\Phi')
        .replaceAll('Ψ', r'\Psi')
        .replaceAll('Ω', r'\Omega');

    // ── 9. Braket / Dirac notation ────────────────────────────────────────
    r = r
        .replaceAllMapped(
          RegExp(r'⟨([^⟩]+)\|([^⟩]+)⟩'),
          (m) => '<${m.group(1)}|${m.group(2)}>',
        )
        .replaceAllMapped(RegExp(r'⟨([^⟩]+)⟩'), (m) => '<${m.group(1)}>')
        .replaceAllMapped(RegExp(r'\|([^>|]+)⟩'), (m) => '|${m.group(1)}>')
        .replaceAllMapped(RegExp(r'⟨([^|<]+)\|'), (m) => '<${m.group(1)}|');

    // ── 10. APL/J/K notation (array math) ────────────────────────────────
    // These are typically very terse; just keep as-is (already ASCII)

    // ── 11. GLSL/HLSL shader math ─────────────────────────────────────────
    r = r
        .replaceAll('vec2(', '(')
        .replaceAll('vec3(', '(')
        .replaceAll('vec4(', '(')
        .replaceAll('mat2(', '[')
        .replaceAll('mat3(', '[')
        .replaceAll('mat4(', '[')
        .replaceAll('dot(', 'dot(')
        .replaceAll('cross(', 'cross(')
        .replaceAll('normalize(', 'norm(')
        .replaceAll('length(', 'len(');

    return r;
  }

  /// Strip XML/HTML tags, keep text content only.
  static String _stripXml(String s) {
    return s
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  /// True if string looks like a math notation that is NOT LaTeX
  /// but should still be rendered in an equation block (AsciiMath, etc.)
  static bool isMathNotation(String s) {
    // AsciiMath indicators
    if (s.contains('sqrt(') ||
        s.contains('int_') ||
        s.contains('sum_') ||
        s.contains('prod_') ||
        s.contains(' oo ') ||
        s.contains('^(')) {
      return true;
    }
    // Symbol-heavy lines (lots of math operators)
    final ops = ['=', '+', '-', '*', '/', '^', '_'];
    final opCount = ops.fold(0, (acc, op) => acc + s.split(op).length - 1);
    if (opCount > 3 && s.length < 200) return true;
    return false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BRACE-AWARE LaTeX → ASCII CONVERTER

  // Old approach (regex [^}]*) fails on nested braces:
  //   \frac{\partial \mathcal{L}}{\partial W^{(k)}} has } inside each arg.
  // New approach: track brace depth character-by-character.
  // ─────────────────────────────────────────────────────────────────────────

  /// Extract content of a brace-group at s[start] (must be '{').
  /// Returns (inner_content, index_after_closing_brace).
  static (String, int) _extractBraceGroup(String s, int start) {
    if (start >= s.length || s[start] != '{') return ('', start);
    int depth = 0;
    int i = start;
    final buf = StringBuffer();
    while (i < s.length) {
      final c = s[i];
      if (c == '{') {
        depth++;
        if (depth > 1) buf.write(c);
      } else if (c == '}') {
        depth--;
        if (depth == 0) return (buf.toString(), i + 1);
        buf.write(c);
      } else {
        buf.write(c);
      }
      i++;
    }
    return (buf.toString(), i);
  }

  /// Expand \frac{num}{den} → (num)/(den) with full nested-brace support.
  static String _expandFracs(String s) {
    var r = s;
    int safety = 0;
    while (r.contains(r'\frac') && safety++ < 30) {
      final idx = r.indexOf(r'\frac');
      if (idx == -1) break;
      int pos = idx + 5;
      while (pos < r.length && r[pos] == ' ') {
        pos++;
      }
      if (pos >= r.length || r[pos] != '{') {
        r = '${r.substring(0, idx)}frac${r.substring(pos)}';
        continue;
      }
      final (num, endNum) = _extractBraceGroup(r, pos);
      pos = endNum;
      while (pos < r.length && r[pos] == ' ') {
        pos++;
      }
      if (pos >= r.length || r[pos] != '{') {
        r = '${r.substring(0, idx)}($num)${r.substring(endNum)}';
        continue;
      }
      final (den, endDen) = _extractBraceGroup(r, pos);
      r = '${r.substring(0, idx)}($num)/($den)${r.substring(endDen)}';
    }
    return r;
  }

  /// Expand \cmdName{content} → transform(content) with nested-brace support.
  static String _expandNamedCmd(
    String s,
    String cmd,
    String Function(String) transform,
  ) {
    var r = s;
    int safety = 0;
    final tag = '\\$cmd';
    while (r.contains(tag) && safety++ < 30) {
      final idx = r.indexOf(tag);
      if (idx == -1) break;
      int pos = idx + tag.length;
      while (pos < r.length && r[pos] == ' ') {
        pos++;
      }
      if (pos >= r.length || r[pos] != '{') {
        r = '${r.substring(0, idx)}${r.substring(pos)}';
        continue;
      }
      final (content, end) = _extractBraceGroup(r, pos);
      r = '${r.substring(0, idx)}${transform(content)}${r.substring(end)}';
    }
    return r;
  }

  /// Convert LaTeX math notation to readable ASCII text.
  /// Handles arbitrary nested commands correctly.
  static String latexToText(String s) {
    var r = s.trim();

    // 1. Strip dollar delimiters
    while (r.startsWith(r'$$') && r.endsWith(r'$$') && r.length > 4) {
      r = r.substring(2, r.length - 2).trim();
    }
    while (r.startsWith(r'$') && r.endsWith(r'$') && r.length > 2) {
      r = r.substring(1, r.length - 1).trim();
    }
    r = r.replaceAll(r'$$', '').replaceAll(r'$', '');

    // 2. \left / \right wrappers first
    r = r
        .replaceAll(r'\left(', '(')
        .replaceAll(r'\right)', ')')
        .replaceAll(r'\left[', '[')
        .replaceAll(r'\right]', ']')
        .replaceAll(r'\left|', '|')
        .replaceAll(r'\right|', '|')
        .replaceAll(r'\left\|', '||')
        .replaceAll(r'\right\|', '||')
        .replaceAll(r'\left\{', '{')
        .replaceAll(r'\right\}', '}')
        .replaceAll(r'\left.', '')
        .replaceAll(r'\right.', '');

    // 3. Expand \frac (5 passes for deep nesting)
    for (int i = 0; i < 5; i++) {
      r = _expandFracs(r);
    }

    // 4. Expand \sqrt{x} → sqrt(x)
    for (int i = 0; i < 3; i++) {
      r = _expandNamedCmd(r, 'sqrt', (c) => 'sqrt($c)');
    }

    // 5. Decoration commands — extract content (3 passes for nesting)
    const decorCmds = [
      'mathcal',
      'mathbb',
      'mathbf',
      'mathit',
      'mathrm',
      'mathfrak',
      'text',
      'textbf',
      'textit',
      'textup',
      'textrm',
      'operatorname',
      'boldsymbol',
      'bm',
      'pmb',
      'underbrace',
      'overbrace',
      'overline',
      'underline',
      'widetilde',
      'widehat',
    ];
    for (int pass = 0; pass < 3; pass++) {
      for (final cmd in decorCmds) {
        r = _expandNamedCmd(r, cmd, (c) => c);
      }
      r = _expandNamedCmd(r, 'hat', (c) => '${c}_hat');
      r = _expandNamedCmd(r, 'bar', (c) => '${c}_bar');
      r = _expandNamedCmd(r, 'tilde', (c) => '${c}_tilde');
      r = _expandNamedCmd(r, 'vec', (c) => '${c}_vec');
      r = _expandNamedCmd(r, 'dot', (c) => '${c}_dot');
      r = _expandNamedCmd(r, 'overrightarrow', (c) => '${c}_vec');
    }

    // 6. Subscripts / superscripts with braces (4 passes)
    for (int i = 0; i < 4; i++) {
      r = r.replaceAllMapped(
        RegExp(r'_\{([^{}]*)\}'),
        (m) => '_(${m.group(1)})',
      );
      r = r.replaceAllMapped(
        RegExp(r'\^\{([^{}]*)\}'),
        (m) => '^(${m.group(1)})',
      );
    }
    r = r.replaceAllMapped(RegExp(r'_([a-zA-Z0-9])'), (m) => '_${m.group(1)}');
    r = r.replaceAllMapped(RegExp(r'\^([a-zA-Z0-9])'), (m) => '^${m.group(1)}');

    // 7. Greek letters
    r = r
        .replaceAll(r'\alpha', 'alpha')
        .replaceAll(r'\beta', 'beta')
        .replaceAll(r'\gamma', 'gamma')
        .replaceAll(r'\delta', 'delta')
        .replaceAll(r'\Delta', 'Delta')
        .replaceAll(r'\varepsilon', 'epsilon')
        .replaceAll(r'\epsilon', 'epsilon')
        .replaceAll(r'\zeta', 'zeta')
        .replaceAll(r'\eta', 'eta')
        .replaceAll(r'\theta', 'theta')
        .replaceAll(r'\Theta', 'Theta')
        .replaceAll(r'\iota', 'iota')
        .replaceAll(r'\kappa', 'kappa')
        .replaceAll(r'\lambda', 'lambda')
        .replaceAll(r'\Lambda', 'Lambda')
        .replaceAll(r'\mu', 'mu')
        .replaceAll(r'\nu', 'nu')
        .replaceAll(r'\xi', 'xi')
        .replaceAll(r'\Xi', 'Xi')
        .replaceAll(r'\pi', 'pi')
        .replaceAll(r'\Pi', 'Pi')
        .replaceAll(r'\varrho', 'rho')
        .replaceAll(r'\rho', 'rho')
        .replaceAll(r'\varsigma', 'sigma')
        .replaceAll(r'\sigma', 'sigma')
        .replaceAll(r'\Sigma', 'Sigma')
        .replaceAll(r'\tau', 'tau')
        .replaceAll(r'\upsilon', 'upsilon')
        .replaceAll(r'\Upsilon', 'Upsilon')
        .replaceAll(r'\varphi', 'phi')
        .replaceAll(r'\phi', 'phi')
        .replaceAll(r'\Phi', 'Phi')
        .replaceAll(r'\chi', 'chi')
        .replaceAll(r'\psi', 'psi')
        .replaceAll(r'\Psi', 'Psi')
        .replaceAll(r'\omega', 'omega')
        .replaceAll(r'\Omega', 'Omega');

    // 8. Math operators
    r = r
        .replaceAll(r'\argmin', 'argmin')
        .replaceAll(r'\argmax', 'argmax')
        .replaceAll(r'\min', 'min')
        .replaceAll(r'\max', 'max')
        .replaceAll(r'\sum', 'SUM')
        .replaceAll(r'\prod', 'PROD')
        .replaceAll(r'\int', 'INTG')
        .replaceAll(r'\oint', 'OINT')
        .replaceAll(r'\infty', 'inf')
        .replaceAll(r'\partial', 'd')
        .replaceAll(r'\nabla', 'nabla')
        .replaceAll(r'\cdot', ' * ')
        .replaceAll(r'\times', ' x ')
        .replaceAll(r'\div', ' / ')
        .replaceAll(r'\pm', ' +/- ')
        .replaceAll(r'\mp', ' -/+ ')
        .replaceAll(r'\leq', ' <= ')
        .replaceAll(r'\geq', ' >= ')
        .replaceAll(r'\le', ' <= ')
        .replaceAll(r'\ge', ' >= ')
        .replaceAll(r'\neq', ' != ')
        .replaceAll(r'\ne', ' != ')
        .replaceAll(r'\approx', ' ~= ')
        .replaceAll(r'\equiv', ' == ')
        .replaceAll(r'\propto', ' ~ ')
        .replaceAll(r'\rightarrow', ' -> ')
        .replaceAll(r'\leftarrow', ' <- ')
        .replaceAll(r'\Rightarrow', ' => ')
        .replaceAll(r'\Leftarrow', ' <= ')
        .replaceAll(r'\leftrightarrow', ' <-> ')
        .replaceAll(r'\Leftrightarrow', ' <=> ')
        .replaceAll(r'\to', ' -> ')
        .replaceAll(r'\gets', ' <- ')
        .replaceAll(r'\in', ' in ')
        .replaceAll(r'\notin', ' not_in ')
        .replaceAll(r'\subset', ' subset ')
        .replaceAll(r'\subseteq', ' ⊆ ')
        .replaceAll(r'\cup', ' ∪ ')
        .replaceAll(r'\cap', ' ∩ ')
        .replaceAll(r'\forall', 'for_all ')
        .replaceAll(r'\exists', 'exists ')
        .replaceAll(r'\neg', 'NOT ')
        .replaceAll(r'\lor', ' OR ')
        .replaceAll(r'\land', ' AND ')
        .replaceAll(r'\oplus', ' XOR ')
        .replaceAll(r'\log', 'log')
        .replaceAll(r'\ln', 'ln')
        .replaceAll(r'\exp', 'exp')
        .replaceAll(r'\sin', 'sin')
        .replaceAll(r'\cos', 'cos')
        .replaceAll(r'\tan', 'tan')
        .replaceAll(r'\sinh', 'sinh')
        .replaceAll(r'\cosh', 'cosh')
        .replaceAll(r'\tanh', 'tanh')
        .replaceAll(r'\lim', 'lim')
        .replaceAll(r'\det', 'det')
        .replaceAll(r'\ell', 'l')
        .replaceAll(r'\hbar', 'h-bar')
        .replaceAll(r'\prime', "'")
        .replaceAll(r'\ldots', '...')
        .replaceAll(r'\cdots', '...')
        .replaceAll(r'\vdots', ':')
        .replaceAll(r'\ddots', '...');

    // 9. Spacing → whitespace
    r = r
        .replaceAll(r'\qquad', '    ')
        .replaceAll(r'\quad', '  ')
        .replaceAll(r'\,', ' ')
        .replaceAll(r'\;', ' ')
        .replaceAll(r'\:', ' ')
        .replaceAll(r'\!', '')
        .replaceAll(r'\ ', ' ')
        .replaceAll(r'\/', ' ');

    // 10. Remaining \command → strip backslash (keep word)
    r = r.replaceAllMapped(
      RegExp(r'\\([a-zA-Z]+)\*?'),
      (m) => m.group(1) ?? '',
    );

    // 11. Strip remaining braces
    r = r.replaceAll('\\{', '{').replaceAll('\\}', '}');
    r = r.replaceAll('{', '').replaceAll('}', '');

    // 12. Collapse whitespace / newlines
    r = r.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    r = r.replaceAll(RegExp(r' {2,}'), ' ');
    return r.trim();
  }

  /// Returns true if the string contains LaTeX math notation.
  static bool isLatex(String s) {
    return s.contains(r'\frac') ||
        s.contains(r'\partial') ||
        s.contains(r'\sum') ||
        s.contains(r'\prod') ||
        s.contains(r'\int') ||
        s.contains(r'\min') ||
        s.contains(r'\max') ||
        s.contains(r'\lim') ||
        s.contains(r'\mathcal') ||
        s.contains(r'\mathbb') ||
        s.contains(r'\hat{') ||
        s.contains(r'\bar{') ||
        s.contains(r'\theta') ||
        s.contains(r'\alpha') ||
        s.contains(r'\beta') ||
        s.contains(r'\sigma') ||
        s.contains(r'\epsilon') ||
        s.contains(r'\lambda') ||
        s.contains(r'\mu') ||
        s.contains(r'\omega') ||
        s.contains(r'\leq') ||
        s.contains(r'\geq') ||
        s.contains(r'\nabla') ||
        s.contains(r'\rightarrow') ||
        s.contains(r'\left') ||
        s.contains(r'\quad') ||
        s.contains(r'\cdot') ||
        s.contains(r'\times') ||
        s.contains(r'\sqrt') ||
        s.contains(r'\infty') ||
        (s.startsWith(r'$$') && s.length > 4) ||
        (s.startsWith(r'$') && s.endsWith(r'$') && s.length > 2);
  }
}
// ============================================================
// BLOCK MODEL
// ============================================================

enum _BlockType {
  h1,
  h2,
  h3,
  paragraph,
  bullet,
  numbered,
  table,
  code,
  equation,
  diagram,
  divider,
  empty,
}

class _Block {
  final _BlockType type;
  final String content;
  final List<String> items;
  final List<List<String>> tableData;

  const _Block({
    required this.type,
    this.content = '',
    this.items = const [],
    this.tableData = const [],
  });
}

// ============================================================
// PARSER - Converts raw markdown response into typed Blocks
// ============================================================

class _Parser {
  static List<_Block> parse(String text) {
    final blocks = <_Block>[];
    final lines = text.split('\n');
    int i = 0;

    while (i < lines.length) {
      final raw = lines[i];
      final t = raw.trim();

      // Empty
      if (t.isEmpty) {
        blocks.add(const _Block(type: _BlockType.empty));
        i++;
        continue;
      }

      // Dividers
      if (RegExp(r'^[-=*]{3,}$').hasMatch(t)) {
        blocks.add(const _Block(type: _BlockType.divider));
        i++;
        continue;
      }

      // H1: # ... or ALL CAPS lines that look like titles
      if (t.startsWith('# ') && !t.startsWith('## ')) {
        blocks.add(
          _Block(
            type: _BlockType.h1,
            content: _clean(t.replaceFirst(RegExp(r'^#\s*'), '')),
          ),
        );
        i++;
        continue;
      }
      // H2: ## ...
      if (t.startsWith('## ') && !t.startsWith('### ')) {
        blocks.add(
          _Block(
            type: _BlockType.h2,
            content: _clean(t.replaceFirst(RegExp(r'^##\s*'), '')),
          ),
        );
        i++;
        continue;
      }
      // H3: ### ...
      if (t.startsWith('### ')) {
        blocks.add(
          _Block(
            type: _BlockType.h3,
            content: _clean(t.replaceFirst(RegExp(r'^###\s*'), '')),
          ),
        );
        i++;
        continue;
      }

      // Fenced code block — detect LaTeX / math notation → re-classify as equation
      if (t.startsWith('```')) {
        final codeLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          codeLines.add(lines[i]);
          i++;
        }
        i++; // skip closing ```
        final rawCode = codeLines.join('\n');
        final normalized = _TextSanitiser.normalizeEquation(rawCode);
        if (_TextSanitiser.isLatex(normalized) ||
            _TextSanitiser.isLatex(rawCode)) {
          // LaTeX or any math notation → render as equation
          final eq = _TextSanitiser.latexToText(normalized);
          blocks.add(_Block(type: _BlockType.equation, content: eq));
        } else if (_TextSanitiser.isMathNotation(rawCode)) {
          // AsciiMath / other math — render as equation as-is (already ASCII)
          blocks.add(
            _Block(
              type: _BlockType.equation,
              content: _TextSanitiser.cleanBlock(normalized),
            ),
          );
        } else {
          final cleaned = _TextSanitiser.cleanBlock(rawCode);
          blocks.add(_Block(type: _BlockType.code, content: cleaned));
        }
        continue;
      }

      // Equation $$...$$ — always run through normalizer + latexToText
      if (t.startsWith(r'$$')) {
        final eqLines = <String>[];
        final rest = t.substring(2);
        if (rest.endsWith(r'$$')) {
          final raw = rest.substring(0, rest.length - 2).trim();
          blocks.add(
            _Block(
              type: _BlockType.equation,
              content: _TextSanitiser.latexToText(
                _TextSanitiser.normalizeEquation(raw),
              ),
            ),
          );
          i++;
          continue;
        }
        if (rest.isNotEmpty) eqLines.add(rest);
        i++;
        while (i < lines.length && !lines[i].contains(r'$$')) {
          eqLines.add(lines[i]);
          i++;
        }
        if (i < lines.length) {
          final last = lines[i].split(r'$$')[0];
          if (last.isNotEmpty) eqLines.add(last);
          i++;
        }
        final raw = eqLines.join('\n');
        blocks.add(
          _Block(
            type: _BlockType.equation,
            content: _TextSanitiser.latexToText(
              _TextSanitiser.normalizeEquation(raw),
            ),
          ),
        );
        continue;
      }

      // Table
      if (t.startsWith('|')) {
        final rows = <List<String>>[];
        while (i < lines.length && lines[i].trim().startsWith('|')) {
          final row = lines[i].trim();
          if (!RegExp(r'^\|[-| :]+\|$').hasMatch(row)) {
            final cells = row
                .split('|')
                .map((c) => _clean(c))
                .where((c) => c.isNotEmpty)
                .toList();
            if (cells.isNotEmpty) rows.add(cells);
          }
          i++;
        }
        if (rows.isNotEmpty) {
          blocks.add(_Block(type: _BlockType.table, tableData: rows));
        }
        continue;
      }

      // Bullet list
      if (t.startsWith('- ') || t.startsWith('* ') || t.startsWith('• ')) {
        final items = <String>[];
        while (i < lines.length) {
          final lt = lines[i].trim();
          if (lt.startsWith('- ') ||
              lt.startsWith('* ') ||
              lt.startsWith('• ')) {
            items.add(_clean(lt.replaceFirst(RegExp(r'^[-*•]\s+'), '')));
            i++;
          } else {
            break;
          }
        }
        blocks.add(_Block(type: _BlockType.bullet, items: items));
        continue;
      }

      // Numbered list
      if (RegExp(r'^\d+[\.\)]\s').hasMatch(t)) {
        final items = <String>[];
        while (i < lines.length &&
            RegExp(r'^\d+[\.\)]\s').hasMatch(lines[i].trim())) {
          items.add(
            _clean(lines[i].trim().replaceFirst(RegExp(r'^\d+[\.\)]\s+'), '')),
          );
          i++;
        }
        blocks.add(_Block(type: _BlockType.numbered, items: items));
        continue;
      }

      // ASCII Diagram detection
      if (_isDiagram(t)) {
        final diagLines = <String>[];
        while (i < lines.length &&
            (_isDiagram(lines[i]) || lines[i].trim().isEmpty)) {
          diagLines.add(lines[i]);
          i++;
        }
        // strip trailing empties
        while (diagLines.isNotEmpty && diagLines.last.trim().isEmpty) {
          diagLines.removeLast();
        }
        if (diagLines.isNotEmpty) {
          // Apply block cleaning: strip emoji from diagram lines
          final cleaned = _TextSanitiser.cleanBlock(diagLines.join('\n'));
          blocks.add(_Block(type: _BlockType.diagram, content: cleaned));
        }
        continue;
      }

      // Regular paragraph — extract inline $...$ math segments
      // A line like "The loss is $L(theta)$ which..." gets math converted
      final cleaned = _TextSanitiser.clean(_expandInlineMath(t));
      if (cleaned.isNotEmpty) {
        blocks.add(_Block(type: _BlockType.paragraph, content: cleaned));
      }
      i++;
    }

    return blocks;
  }

  /// Expand inline $...$ math segments to ASCII text in place
  static String _expandInlineMath(String line) {
    return line.replaceAllMapped(
      RegExp(r'\$([^\$]+?)\$'),
      (m) => _TextSanitiser.latexToText(m.group(1) ?? ''),
    );
  }

  static String _clean(String s) => _TextSanitiser.clean(s);

  static bool _isDiagram(String line) {
    return line.contains('──') ||
        line.contains('│') ||
        line.contains('┌') ||
        line.contains('└') ||
        line.contains('┐') ||
        line.contains('┘') ||
        line.contains('←') ||
        line.contains('→') ||
        line.contains('↓') ||
        line.contains('↑') ||
        (line.contains('+--') && line.contains('--+')) ||
        (line.contains('|') &&
            (line.contains('+') && line.trimLeft().startsWith('|')));
  }
}

// ============================================================
// PDF BUILDER — A4, 1.5cm borders, dynamic multi-page
// ============================================================

class JarvisPDFBuilder {
  static const double _margin = 36.0; // ~12.7mm - safe inner content margin
  static const double _borderPad = 10.0; // Distance border sits from paper edge
  static const PdfColor _borderColor = PdfColors.grey700;
  static const PdfColor _accentColor = PdfColors.blueGrey800;
  static const PdfColor _tableHdrBg = PdfColors.blueGrey50;
  static const PdfColor _codeBg = PdfColors.grey100;

  static Future<Uint8List> buildPDF(String responseText) async {
    if (!JarvisFontLoader.loaded) await JarvisFontLoader.loadFonts();

    final pdf = pw.Document();
    final blocks = _Parser.parse(responseText);
    final widgets = _buildWidgets(blocks);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(_margin),
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(_margin),
          buildBackground: (ctx) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(
              // Border sits _borderPad from the physical paper edge
              margin: pw.EdgeInsets.all(_borderPad),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _borderColor, width: 1.5),
              ),
            ),
          ),
        ),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: pw.TextStyle(
              font: JarvisFontLoader.bodyRegular,
              fontSize: 9,
              color: PdfColors.grey500,
            ),
          ),
        ),
        build: (ctx) => widgets,
      ),
    );

    return pdf.save();
  }

  // ─────────────────────────────────────────────
  // Build list of widgets from parsed blocks
  // ─────────────────────────────────────────────
  static List<pw.Widget> _buildWidgets(List<_Block> blocks) {
    final ws = <pw.Widget>[];

    // ── KEEP-TOGETHER: pair each H2/H3 with the content that immediately follows
    // so headings are never stranded alone at the bottom of a page.
    final paired = <_Block>[];
    for (int i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if ((b.type == _BlockType.h2 || b.type == _BlockType.h3) &&
          i + 1 < blocks.length &&
          blocks[i + 1].type != _BlockType.h1 &&
          blocks[i + 1].type != _BlockType.h2 &&
          blocks[i + 1].type != _BlockType.h3 &&
          blocks[i + 1].type != _BlockType.empty) {
        // mark as paired — will emit as KeepTogether
        paired.add(_Block(type: b.type, content: '${b.content}\x00${i + 1}'));
        i++; // skip the following block — it'll be emitted inside KeepTogether
        continue;
      }
      paired.add(b);
    }

    for (int pi = 0; pi < paired.length; pi++) {
      final b = paired[pi];

      // Detect paired heading block
      final isPairedHeading =
          (b.type == _BlockType.h2 || b.type == _BlockType.h3) &&
          b.content.contains('\x00');

      if (isPairedHeading) {
        final parts = b.content.split('\x00');
        final hText = parts[0];
        final nextIdx = int.parse(parts[1]);
        final nextBlock = blocks[nextIdx];

        // Build heading widgets
        final headingWidgets = <pw.Widget>[];
        if (b.type == _BlockType.h2) {
          headingWidgets.addAll([
            pw.SizedBox(height: 8),
            _richText(hText, JarvisFontLoader.h2Style),
            pw.Divider(color: PdfColors.grey500, thickness: 0.7),
            pw.SizedBox(height: 4),
          ]);
        } else {
          headingWidgets.addAll([
            pw.SizedBox(height: 5),
            _richText(hText, JarvisFontLoader.h3Style),
            pw.SizedBox(height: 3),
          ]);
        }

        // Build the following content widgets
        final followWidgets = <pw.Widget>[];
        switch (nextBlock.type) {
          case _BlockType.paragraph:
            followWidgets.addAll([
              _buildParagraph(nextBlock.content),
              pw.SizedBox(height: 5),
            ]);
            break;
          case _BlockType.bullet:
            followWidgets.addAll([
              _buildBullet(nextBlock.items),
              pw.SizedBox(height: 5),
            ]);
            break;
          case _BlockType.numbered:
            followWidgets.addAll([
              _buildNumbered(nextBlock.items),
              pw.SizedBox(height: 5),
            ]);
            break;
          case _BlockType.equation:
            followWidgets.addAll(_buildEquationBlock(nextBlock.content));
            followWidgets.add(pw.SizedBox(height: 8));
            break;
          default:
            followWidgets.addAll([
              _buildParagraph(nextBlock.content),
              pw.SizedBox(height: 5),
            ]);
            break;
        }

        ws.add(
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [...headingWidgets, ...followWidgets],
          ),
        );
        continue;
      }

      // Regular block
      switch (b.type) {
        case _BlockType.empty:
          ws.add(pw.SizedBox(height: 5));
          break;

        case _BlockType.divider:
          ws.add(pw.Divider(color: PdfColors.grey400, thickness: 0.7));
          break;

        case _BlockType.h1:
          ws.add(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(height: 10),
                _richText(b.content, JarvisFontLoader.h1Style),
                pw.Divider(color: _accentColor, thickness: 1.5),
                pw.SizedBox(height: 5),
              ],
            ),
          );
          break;

        case _BlockType.h2:
          ws.add(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(height: 8),
                _richText(b.content, JarvisFontLoader.h2Style),
                pw.Divider(color: PdfColors.grey500, thickness: 0.7),
                pw.SizedBox(height: 4),
              ],
            ),
          );
          break;

        case _BlockType.h3:
          ws.add(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(height: 5),
                _richText(b.content, JarvisFontLoader.h3Style),
                pw.SizedBox(height: 3),
              ],
            ),
          );
          break;

        case _BlockType.paragraph:
          ws
            ..add(_buildParagraph(b.content))
            ..add(pw.SizedBox(height: 5));
          break;

        case _BlockType.bullet:
          ws
            ..add(_buildBullet(b.items))
            ..add(pw.SizedBox(height: 5));
          break;

        case _BlockType.numbered:
          ws
            ..add(_buildNumbered(b.items))
            ..add(pw.SizedBox(height: 5));
          break;

        case _BlockType.table:
          ws
            ..add(_buildTable(b.tableData))
            ..add(pw.SizedBox(height: 8));
          break;

        case _BlockType.code:
          ws.addAll(_buildCodeBlock(b.content));
          ws.add(pw.SizedBox(height: 8));
          break;

        case _BlockType.equation:
          ws.addAll(_buildEquationBlock(b.content));
          ws.add(pw.SizedBox(height: 8));
          break;

        case _BlockType.diagram:
          ws.addAll(_buildDiagramBlock(b.content));
          ws.add(pw.SizedBox(height: 8));
          break;
      }
    }

    return ws;
  }

  // ─────────────────────────────────────────────
  // Inline formatted text (bold/italic segments)
  // ─────────────────────────────────────────────
  static pw.Widget _richText(String text, pw.TextStyle baseStyle) {
    final segments = _TextSanitiser.parseInline(text);
    final spans = segments.map((seg) {
      pw.TextStyle s = baseStyle;
      final isBold = (seg['bold'] as bool?) ?? false;
      final isItalic = (seg['italic'] as bool?) ?? false;
      if (isBold && isItalic) {
        s = baseStyle.copyWith(
          fontWeight: pw.FontWeight.bold,
          fontStyle: pw.FontStyle.italic,
          font: JarvisFontLoader.bodyBold,
        );
      } else if (isBold) {
        s = baseStyle.copyWith(
          fontWeight: pw.FontWeight.bold,
          font: JarvisFontLoader.bodyBold,
        );
      } else if (isItalic) {
        s = baseStyle.copyWith(
          fontStyle: pw.FontStyle.italic,
          font: JarvisFontLoader.bodyItalic,
        );
      }
      return pw.TextSpan(text: seg['text'] as String, style: s);
    }).toList();
    if (spans.isEmpty) {
      final clean = _TextSanitiser.clean(text);
      spans.add(pw.TextSpan(text: clean, style: baseStyle));
    }
    return pw.RichText(text: pw.TextSpan(children: spans));
  }

  static pw.Widget _buildParagraph(String text) =>
      _richText(text, JarvisFontLoader.body);

  // ─────────────────────────────────────────────
  // Bullet list
  // ─────────────────────────────────────────────
  static pw.Widget _buildBullet(List<String> items) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: items.map((item) {
        return pw.Padding(
          padding: const pw.EdgeInsets.only(left: 10, bottom: 4),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('• ', style: JarvisFontLoader.bodyBoldStyle),
              pw.Expanded(child: _richText(item, JarvisFontLoader.body)),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ─────────────────────────────────────────────
  // Numbered list — uses plain digits, no roman, no emoji
  // ─────────────────────────────────────────────
  static pw.Widget _buildNumbered(List<String> items) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: items.asMap().entries.map((e) {
        return pw.Padding(
          padding: const pw.EdgeInsets.only(left: 10, bottom: 4),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 22,
                child: pw.Text(
                  '${e.key + 1}.',
                  style: JarvisFontLoader.bodyBoldStyle,
                ),
              ),
              pw.Expanded(child: _richText(e.value, JarvisFontLoader.body)),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ─────────────────────────────────────────────
  // Table
  // ─────────────────────────────────────────────
  static pw.Widget _buildTable(List<List<String>> data) {
    if (data.isEmpty) return pw.SizedBox();
    final headers = data[0];
    final rows = data.length > 1 ? data.sublist(1) : <List<String>>[];
    return pw.Table(
      border: pw.TableBorder.all(color: _borderColor, width: 0.8),
      columnWidths: {
        for (int i = 0; i < headers.length; i++) i: const pw.FlexColumnWidth(),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _tableHdrBg),
          children: headers
              .map(
                (h) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 5,
                  ),
                  child: pw.Text(
                    h,
                    style: JarvisFontLoader.bodyBoldStyle.copyWith(
                      fontSize: 10,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              )
              .toList(),
        ),
        ...rows.map(
          (row) => pw.TableRow(
            children: List.generate(headers.length, (i) {
              final cell = i < row.length ? row[i] : '';
              return pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 4,
                ),
                child: pw.Text(
                  cell,
                  style: JarvisFontLoader.smallBody.copyWith(fontSize: 10),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // Code block (chunked for multi-page)
  // ─────────────────────────────────────────────
  static List<pw.Widget> _buildCodeBlock(String code) => _slice(
    content: code,
    style: JarvisFontLoader.code,
    bgColor: _codeBg,
    border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
  );

  // ─────────────────────────────────────────────
  // Equation block — clean white background, blue left border, mono font
  // Shows ASCII-converted math clearly and readably
  // ─────────────────────────────────────────────
  static List<pw.Widget> _buildEquationBlock(String eq) {
    // eq is already LaTeX-converted to ASCII at parse time
    final lines = eq.split('\n');
    return [
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        margin: const pw.EdgeInsets.symmetric(vertical: 4),
        decoration: const pw.BoxDecoration(
          color: PdfColors.blueGrey50,
          border: pw.Border(
            left: pw.BorderSide(color: PdfColors.blueGrey600, width: 3),
          ),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: lines
              .map(
                (l) => pw.Text(
                  l,
                  style: JarvisFontLoader.code.copyWith(
                    fontSize: 11,
                    color: PdfColors.blueGrey900,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              )
              .toList(),
        ),
      ),
    ];
  }

  // ─────────────────────────────────────────────
  // Diagram block — monospace, readable font, NO FittedBox squish
  // ─────────────────────────────────────────────
  static List<pw.Widget> _buildDiagramBlock(String diagram) => _slice(
    content: diagram,
    style: JarvisFontLoader.code, // 10pt — readable, not codeTiny
    bgColor: PdfColors.grey50,
    border: pw.Border.all(color: PdfColors.blueGrey300, width: 1),
    isDiagram: true,
  );

  // ─────────────────────────────────────────────
  // Generic block slicer — splits every 40 lines so
  // content flows across unlimited PDF pages.
  // NO FittedBox — that squishes long lines to microscopic size.
  // Instead we truncate lines > 95 chars for diagrams so they
  // never overflow, and use softWrap for code/equation blocks.
  // ─────────────────────────────────────────────
  static List<pw.Widget> _slice({
    required String content,
    required pw.TextStyle style,
    required PdfColor bgColor,
    required pw.BoxBorder border,
    bool isDiagram = false,
    bool center = false,
  }) {
    const maxLines = 40;
    const maxLineChars = 90; // chars per line for diagrams before wrapping

    // Pre-process: for diagrams, wrap lines that are too wide
    String processed = content;
    if (isDiagram) {
      final lines = content.split('\n');
      final wrapped = <String>[];
      for (final line in lines) {
        if (line.length > maxLineChars) {
          // Hard-wrap at maxLineChars with indent for continuation
          var remaining = line;
          bool first = true;
          while (remaining.length > maxLineChars) {
            wrapped.add(
              first
                  ? remaining.substring(0, maxLineChars)
                  : '  ${remaining.substring(0, maxLineChars)}',
            );
            remaining = remaining.substring(maxLineChars);
            first = false;
          }
          if (remaining.isNotEmpty) {
            wrapped.add(first ? remaining : '  $remaining');
          }
        } else {
          wrapped.add(line);
        }
      }
      processed = wrapped.join('\n');
    }

    final lines = processed.split('\n');
    final chunks = <pw.Widget>[];

    for (int i = 0; i < lines.length; i += maxLines) {
      final end = math.min(i + maxLines, lines.length);
      final chunkText = lines.sublist(i, end).join('\n');
      final isFirst = i == 0;
      final isLast = end >= lines.length;

      final inner = pw.Text(
        chunkText,
        style: style,
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
        softWrap: true,
      );

      chunks.add(
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: bgColor,
            border: border,
            borderRadius: pw.BorderRadius.vertical(
              top: isFirst ? const pw.Radius.circular(4) : pw.Radius.zero,
              bottom: isLast ? const pw.Radius.circular(4) : pw.Radius.zero,
            ),
          ),
          child: inner,
        ),
      );
    }

    return chunks.isEmpty
        ? [pw.Text(processed, style: style, softWrap: true)]
        : chunks;
  }
}

// ============================================================
// PDF BUTTON WIDGET
// ============================================================

class JarvisPDFButton extends StatefulWidget {
  final String responseText;
  final String? filename;

  const JarvisPDFButton({super.key, required this.responseText, this.filename});

  @override
  State<JarvisPDFButton> createState() => _JarvisPDFButtonState();
}

class _JarvisPDFButtonState extends State<JarvisPDFButton> {
  bool _isGenerating = false;

  // ─── Strip JARVIS greeting lines at top and sign-off lines at bottom ──────
  static String _stripGreetings(String raw) {
    final lines = raw.split('\n');

    final greetingRe = RegExp(
      r'^(vanakkam|hello[\s!]|hi[\s!]|hey[\s!]|greetings|namasthe|namaste|'
      r'good\s+(morning|afternoon|evening|night)|welcome|sure[!,]|of course[!,]|'
      r'absolutely[!,]|great[!,]|certainly[!,]|let me help).*$',
      caseSensitive: false,
    );

    final closingRe = RegExp(
      r'^(hope this helps|let me know if|feel free to|if you have any|any questions|'
      r'do let me know|happy to help|need more info|need anything else|'
      r'is there anything else|hope that (helps|covers|answers)|'
      r'that covers|best regards|thank you for|thanks for|'
      r'regards,|cheers,|sincerely,|warm regards|hope you found).*$',
      caseSensitive: false,
    );

    int start = 0;
    while (start < lines.length) {
      final t = lines[start].trim();
      if (t.isEmpty || greetingRe.hasMatch(t)) {
        start++;
      } else {
        break;
      }
    }

    int end = lines.length - 1;
    while (end >= start) {
      final t = lines[end].trim();
      if (t.isEmpty || closingRe.hasMatch(t)) {
        end--;
      } else {
        break;
      }
    }

    if (start > end) return raw;
    return lines.sublist(start, end + 1).join('\n');
  }

  Future<Uint8List> _buildCleanPDF() async {
    final mainContent = _stripGreetings(widget.responseText);
    return JarvisPDFBuilder.buildPDF(mainContent);
  }

  // ─── Bottom sheet: Download or Share ──────────────────────────────────────
  Future<void> _showOptions() async {
    if (_isGenerating) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Export as PDF',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Main content only — greetings removed',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 6),
            const Divider(color: Colors.white12),
            ListTile(
              leading: const Icon(
                Icons.download_rounded,
                color: Color(0xFF7C83FD),
              ),
              title: const Text(
                'Download PDF',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Save to Downloads folder',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _executePDF(download: true);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.share_rounded,
                color: Color(0xFF4DE8B2),
              ),
              title: const Text(
                'Share PDF',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Share via WhatsApp, Drive, Gmail...',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _executePDF(download: false);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _executePDF({required bool download}) async {
    if (_isGenerating) return;
    setState(() => _isGenerating = true);
    try {
      final bytes = await _buildCleanPDF();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final fname = widget.filename ?? 'jarvis_report_$ts.pdf';

      if (download) {
        Directory dir;
        try {
          dir = Directory('/storage/emulated/0/Download');
          if (!await dir.exists()) dir = await getTemporaryDirectory();
        } catch (_) {
          dir = await getTemporaryDirectory();
        }
        final file = File('${dir.path}/$fname');
        await file.writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved to ${file.path}'),
              backgroundColor: const Color(0xFF4DE8B2),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else {
        final tmp = await getTemporaryDirectory();
        final file = File('${tmp.path}/$fname');
        await file.writeAsBytes(bytes);
        await Share.shareXFiles([
          XFile(file.path, mimeType: 'application/pdf'),
        ], subject: fname.replaceAll('_', ' ').replaceAll('.pdf', ''));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Export as PDF',
      child: GestureDetector(
        onTap: _showOptions,
        child: _isGenerating
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.grey,
                ),
              )
            : Icon(
                Icons.picture_as_pdf_rounded,
                size: 16,
                color: Colors.grey.withValues(alpha: 0.6),
              ),
      ),
    );
  }
}
