import '../core/util.dart';
import '../models/models.dart';
import 'article_source.dart';

/// Zenn 非公式 API（doc/design.md 5.4）
///
/// 検証結果（2026-11-04）：
/// - 新着：`/api/articles?topicname={topic}&order=latest&page=N`（`next_page` あり）
/// - 人気：`order=weekly` が直近1週間の人気順
/// - 本文：`/api/articles/{slug}` の `article.body_html`
/// - 一覧に本文の冒頭はない → カードはタイトル・絵文字・いいね数・トピック
class ZennSource implements ArticleSource {
  ZennSource([SourceHttp? http]) : _http = http ?? SourceHttp();
  final SourceHttp _http;

  @override
  SourceType get type => SourceType.zenn;

  ArticleSummary _toSummary(Map<String, dynamic> j, String topic) {
    final url = 'https://zenn.dev${j['path']}';
    return ArticleSummary(
      source: type,
      sourceKey: normalizeUrl(url),
      url: url,
      title: j['title'] as String? ?? '',
      author: (j['user'] as Map?)?['name'] as String? ?? (j['user'] as Map?)?['username'] as String?,
      tags: [topic],
      likes: j['liked_count'] as int? ?? 0,
      publishedAt: parseTime(j['published_at']),
      emoji: j['emoji'] as String?,
      extra: {'slug': j['slug']},
    );
  }

  Future<(List<ArticleSummary>, bool)> _list(Tag t, String order, int page) async {
    final uri = Uri.https('zenn.dev', '/api/articles', {'topicname': t.zenn, 'order': order, 'page': '$page'});
    final j = await _http.getJson(uri) as Map<String, dynamic>;
    final list = (j['articles'] as List? ?? const []).cast<Map<String, dynamic>>();
    return (list.map((a) => _toSummary(a, t.zenn)).toList(), j['next_page'] != null);
  }

  @override
  Future<Page<ArticleSummary>> fetchLatest({required List<Tag> tags, String? cursor}) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final results = await Future.wait(tags.map((t) => _list(t, 'latest', page)));
    final items = mergeUnique(results.map((r) => r.$1))..sort((a, b) => (b.publishedAt ?? 0).compareTo(a.publishedAt ?? 0));
    return Page(items, results.any((r) => r.$2) ? '${page + 1}' : null);
  }

  @override
  Future<List<ArticleSummary>> fetchPopular({required List<Tag> tags, required int limit}) async {
    final weekAgo = nowMs() - 7 * dayMs;
    final results = <List<ArticleSummary>>[];
    for (final t in tags) {
      results.add((await _list(t, 'weekly', 1)).$1);
    }
    final merged = mergeUnique(results).where((a) => (a.publishedAt ?? 0) >= weekAgo).toList()
      ..sort((a, b) => b.likes.compareTo(a.likes));
    return merged.take(limit).toList();
  }

  /// 一覧には本文の冒頭がないため、詳細を取って冒頭と最初の画像を補う。
  /// 取った本文は extra['html'] に入れ、全文表示で再取得しない
  Future<ArticleSummary> enrich(ArticleSummary s) async {
    final c = await fetchContent(s);
    final images = c.imageUrls;
    return s.copyWith(
      summary: plainExcerpt(c.html),
      thumbnailUrl: images.isEmpty ? null : images.first,
      extra: {...s.extra, 'html': c.html},
    );
  }

  @override
  Future<ArticleContent> fetchContent(ArticleSummary summary) async {
    final cached = summary.extra['html'] as String?;
    if (cached != null && cached.isNotEmpty) return ArticleContent(html: cached, imageUrls: extractImageUrls(cached));
    final slug = summary.extra['slug'] as String? ?? Uri.parse(summary.url).pathSegments.last;
    final j = await _http.getJson(Uri.https('zenn.dev', '/api/articles/$slug')) as Map<String, dynamic>;
    final a = j['article'] as Map<String, dynamic>? ?? const {};
    final html = a['body_html'] as String? ?? '';
    if (html.isEmpty) throw SourceException('本文を取得できません（仕様変更の可能性）');
    return ArticleContent(html: html, imageUrls: extractImageUrls(html));
  }
}
