import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/router/ai_router.dart';

// ─── Data Models ────────────────────────────────────────────────────────────

class EBookPage {
  final int pageNumber;
  final String chapterTitle;
  final String content;
  final String imagePrompt;
  final String? imageUrl;
  final bool isGenerating;

  const EBookPage({
    required this.pageNumber,
    required this.chapterTitle,
    required this.content,
    required this.imagePrompt,
    this.imageUrl,
    this.isGenerating = false,
  });

  EBookPage copyWith({
    String? content,
    String? imagePrompt,
    String? imageUrl,
    bool? isGenerating,
  }) => EBookPage(
    pageNumber: pageNumber,
    chapterTitle: chapterTitle,
    content: content ?? this.content,
    imagePrompt: imagePrompt ?? this.imagePrompt,
    imageUrl: imageUrl ?? this.imageUrl,
    isGenerating: isGenerating ?? this.isGenerating,
  );
}

class EBookConfig {
  final String title;
  final String genre; // comics, fantasy, sci-fi, educational, etc.
  final String targetAudience; // children, teen, adult
  final String tone; // adventurous, humorous, dramatic, etc.
  final String artStyle; // comic-book, realistic, anime, watercolor
  final int pageCount; // 25–45
  final String language; // English, Tamil, etc.
  final String synopsis; // User-supplied story idea

  const EBookConfig({
    required this.title,
    required this.genre,
    required this.targetAudience,
    required this.tone,
    required this.artStyle,
    this.pageCount = 30,
    this.language = 'English',
    required this.synopsis,
  });
}

class EBookProgress {
  final String stage; // outline | writing | illustrating | done
  final int currentPage;
  final int totalPages;
  final String message;
  final bool isDone;
  final bool hasError;
  final String? errorMessage;

  const EBookProgress({
    required this.stage,
    required this.currentPage,
    required this.totalPages,
    required this.message,
    this.isDone = false,
    this.hasError = false,
    this.errorMessage,
  });
}

// ─── Service ─────────────────────────────────────────────────────────────────

class EBookService {
  final AIRouter _router;

  EBookService(this._router);

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Generates a complete eBook. Yields progress events and page data.
  /// Total token budget: 50k–65k across all pages.
  Stream<({EBookProgress progress, EBookPage? page})> generate(
    EBookConfig config,
  ) async* {
    final totalPages = config.pageCount.clamp(5, 45);
    final tokensPerPage = (55000 ~/ totalPages).clamp(800, 1800);

    // ── Stage 1: Generate outline ────────────────────────────────────────────
    yield (
      progress: EBookProgress(
        stage: 'outline',
        currentPage: 0,
        totalPages: totalPages,
        message: '📖 Generating story outline...',
      ),
      page: null,
    );

    final outline = await _generateOutline(config, totalPages);

    // ── Stage 2: Write pages ─────────────────────────────────────────────────
    final pages = <EBookPage>[];

    for (int i = 0; i < totalPages; i++) {
      yield (
        progress: EBookProgress(
          stage: 'writing',
          currentPage: i + 1,
          totalPages: totalPages,
          message: '✍️ Writing page ${i + 1} of $totalPages...',
        ),
        page: null,
      );

      EBookPage page;
      try {
        page = await _generatePage(
          config: config,
          outline: outline,
          pageIndex: i,
          totalPages: totalPages,
          previousPages: pages,
          tokensPerPage: tokensPerPage,
        );
      } catch (e) {
        debugPrint('EBook page $i error: $e');
        // Graceful fallback page
        page = EBookPage(
          pageNumber: i + 1,
          chapterTitle: 'Chapter ${(i ~/ 5) + 1}',
          content: '[Content generation failed for this page. Please retry.]',
          imagePrompt:
              '${config.artStyle} style illustration for page ${i + 1}',
        );
      }

      pages.add(page);
      yield (
        progress: EBookProgress(
          stage: 'writing',
          currentPage: i + 1,
          totalPages: totalPages,
          message: '✍️ Page ${i + 1} written',
        ),
        page: page,
      );
    }

    // ── Stage 3: Generate images (1 per page) ─────────────────────────────
    for (int i = 0; i < totalPages; i++) {
      yield (
        progress: EBookProgress(
          stage: 'illustrating',
          currentPage: i + 1,
          totalPages: totalPages,
          message: '🎨 Illustrating page ${i + 1}...',
        ),
        page: null,
      );

      final page = pages[i];
      final imageUrl = _buildImageUrl(
        page.imagePrompt,
        config.artStyle,
        seed: i,
      );

      final illustrated = page.copyWith(imageUrl: imageUrl);
      pages[i] = illustrated;

      yield (
        progress: EBookProgress(
          stage: 'illustrating',
          currentPage: i + 1,
          totalPages: totalPages,
          message: '🎨 Page ${i + 1} illustrated',
        ),
        page: illustrated,
      );
    }

    // ── Done ─────────────────────────────────────────────────────────────────
    yield (
      progress: EBookProgress(
        stage: 'done',
        currentPage: totalPages,
        totalPages: totalPages,
        message: '✅ eBook complete! $totalPages pages generated.',
        isDone: true,
      ),
      page: null,
    );
  }

  // ─── Private helpers ─────────────────────────────────────────────────────

  Future<String> _generateOutline(EBookConfig config, int totalPages) async {
    final prompt =
        '''
Create a detailed $totalPages-page ${config.genre} eBook outline.

Title: "${config.title}"
Synopsis: ${config.synopsis}
Genre: ${config.genre}
Audience: ${config.targetAudience}
Tone: ${config.tone}
Language: ${config.language}

Output ONLY a numbered list of $totalPages page titles with a one-sentence description each.
Format: [Page N] Chapter Title — Brief description.
''';

    final buf = StringBuffer();
    await for (final chunk in _router.generateStream(
      prompt,
      maxTokens: 2000,
      providerOverride: AIProvider.ollamaCloud,
      modelOverride: 'minimax-m3',
    )) {
      buf.write(chunk);
    }
    return buf.toString().trim();
  }

  Future<EBookPage> _generatePage({
    required EBookConfig config,
    required String outline,
    required int pageIndex,
    required int totalPages,
    required List<EBookPage> previousPages,
    required int tokensPerPage,
  }) async {
    final chapterNum = (pageIndex ~/ 5) + 1;
    final chapterTitle = 'Chapter $chapterNum';
    final prevSummary = previousPages.length >= 2
        ? 'Previous content summary: ${previousPages.last.content.substring(0, previousPages.last.content.length.clamp(0, 200))}...'
        : '';

    final prompt =
        '''
Write page ${pageIndex + 1} of a $totalPages-page ${config.genre} eBook.

TITLE: ${config.title}
TONE: ${config.tone}
AUDIENCE: ${config.targetAudience}
LANGUAGE: ${config.language}
STORY OUTLINE: ${outline.substring(0, outline.length.clamp(0, 600))}
$prevSummary

Write ONLY the page content (${tokensPerPage ~/ 4} words approx), suitable for a comics/illustrated page.
DO NOT use any markdown formatting like #, *, or **. Output plain readable text.
End with: IMAGE_PROMPT: [a vivid 1-sentence ${config.artStyle} style image description for this page]
''';

    final buf = StringBuffer();
    await for (final chunk in _router.generateStream(
      prompt,
      maxTokens: tokensPerPage,
      providerOverride: AIProvider.ollamaCloud,
      modelOverride: 'minimax-m3',
    )) {
      buf.write(chunk);
    }

    final full = buf.toString().trim();
    final imgMatch = RegExp(
      r'IMAGE_PROMPT:\s*(.+)',
      caseSensitive: false,
    ).firstMatch(full);
    final imagePrompt =
        imgMatch?.group(1)?.trim() ??
        '${config.artStyle} illustration for "${config.title}" page ${pageIndex + 1}';

    // Strip the image prompt, and any leftover markdown headers/bold syntax
    String content = full.replaceAll(
      RegExp(r'IMAGE_PROMPT:.*', caseSensitive: false),
      '',
    );
    content = content.replaceAll(RegExp(r'^#+\s*', multiLine: true), '');
    content = content.replaceAll('**', '');
    content = content.trim();

    return EBookPage(
      pageNumber: pageIndex + 1,
      chapterTitle: chapterTitle,
      content: content,
      imagePrompt: imagePrompt,
    );
  }

  String _buildImageUrl(String prompt, String artStyle, {required int seed}) {
    final fullPrompt = '$artStyle style, comic book illustration: $prompt';
    final encoded = Uri.encodeComponent(fullPrompt);
    final randomCacheBust = DateTime.now().millisecondsSinceEpoch;
    return 'https://image.pollinations.ai/prompt/$encoded?width=768&height=512&seed=$seed&nologo=true&cacheBust=$randomCacheBust';
  }
}
