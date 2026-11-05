import 'package:html/parser.dart' as parser;
import 'package:xml/xml.dart';

import '../core/util.dart';
import '../models/models.dart';
import 'article_source.dart';

/// GIGAZINE（RSS ＋ 記事ページ）
///
/// 検証結果（2026-11-05）：
/// - 新着：`/news/rss_2.0/` の最新30件。タイトル・URL・要約・カテゴリ（dc:subject）・日時
///   RSS にページ送りはなく、一覧ページ（/news/P40/ 等）は robots.txt で禁止されているため 30 件まで
/// - タグはなくカテゴリだけ。いいね数のような人気の指標もない
///   → 興味タグに関係なく全新着を流す。一括DLは直近7日の新着を新しい順に取る（ユーザー決定）
/// - 本文：記事ページの `#article .cntimage` から `<!-- google_ad_section_end` まで。
///   一部の画像は data-src（遅延読み込み）
/// - robots.txt に Crawl-delay: 100 の指定がある。一括DLでも他サイトと同じ扱いにする（ユーザー決定）
class GigazineSource implements ArticleSource, Enrichable {
  GigazineSource([SourceHttp? http]) : _http = http ?? SourceHttp();
  final SourceHttp _http;

  static final _rss = Uri.https('gigazine.net', '/news/rss_2.0/');

  @override
  SourceType get type => SourceType.gigazine;

  String _text(XmlElement item, String name) => item.findElements(name).firstOrNull?.innerText.trim() ?? '';

  Future<List<ArticleSummary>> _latest() async {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(await _http.getText(_rss));
    } on XmlException {
      throw SourceException('RSS の形式が想定と違います');
    }
    final out = <ArticleSummary>[];
    for (final item in doc.findAllElements('item')) {
      final url = _text(item, 'link');
      if (url.isEmpty) continue;
      final desc = _text(item, 'description').replaceAll(RegExp(r'<p><b><a[^>]*>続きを読む.*$', dotAll: true), '');
      final cats = _text(item, 'dc:subject').split(',').map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
      out.add(ArticleSummary(
        source: type,
        sourceKey: normalizeUrl(url),
        url: url,
        title: _text(item, 'title'),
        tags: cats,
        summary: plainExcerpt(desc),
        publishedAt: parseTime(_text(item, 'dc:date')),
      ));
    }
    out.sort((a, b) => (b.publishedAt ?? 0).compareTo(a.publishedAt ?? 0));
    return out;
  }

  /// 興味タグは使わない（GIGAZINE にはタグがない）
  @override
  Future<Page<ArticleSummary>> fetchLatest({required List<Tag> tags, String? cursor}) async {
    if (cursor != null) return Page(const [], null);
    return Page(await _latest(), null);
  }

  /// 人気の指標がないため、直近7日の新着を新しい順に
  @override
  Future<List<ArticleSummary>> fetchPopular({required List<Tag> tags, required int limit}) async {
    final weekAgo = nowMs() - 7 * dayMs;
    return (await _latest()).where((a) => (a.publishedAt ?? 0) >= weekAgo).take(limit).toList();
  }

  /// RSS に画像がないため、記事ページから最初の画像を補う（本文は全文表示で再利用）
  @override
  bool needsEnrich(ArticleSummary s) => s.thumbnailUrl == null && s.extra['html'] == null;

  @override
  Future<ArticleSummary> enrich(ArticleSummary s) async {
    final c = await fetchContent(s);
    return s.copyWith(
      thumbnailUrl: c.imageUrls.isEmpty ? null : c.imageUrls.first,
      extra: {...s.extra, 'html': c.html},
    );
  }

  @override
  Future<ArticleContent> fetchContent(ArticleSummary summary) async {
    final cached = summary.extra['html'] as String?;
    if (cached != null && cached.isNotEmpty) return ArticleContent(html: cached, imageUrls: extractImageUrls(cached));
    final page = await _http.getText(Uri.parse(summary.url));
    final html = extractGigazineBody(page);
    if (html.isEmpty) throw SourceException('本文を取得できません（仕様変更の可能性）');
    return ArticleContent(html: html, imageUrls: extractImageUrls(html));
  }
}

/// 記事ページの HTML から本文部分だけを取り出す
String extractGigazineBody(String page) {
  final start = page.indexOf('<div class="cntimage">');
  if (start < 0) return '';
  var end = page.indexOf('<!-- google_ad_section_end', start);
  if (end < 0) end = page.indexOf('</article>', start);
  final frag = parser.parseFragment(page.substring(start, end < 0 ? page.length : end));
  // 見出し・日時・カテゴリは全文表示のテンプレート側で出すので外す
  for (final sel in ['h1.title', 'time', 'span.yeartime', 'style', 'script', 'ins', 'iframe']) {
    for (final e in frag.querySelectorAll(sel)) {
      e.remove();
    }
  }
  return frag.outerHtml.trim();
}
