import '../core/util.dart';
import '../models/models.dart';
import 'article_source.dart';

/// Qiita 公式 API v2（doc/design.md 5.3）
///
/// 検証結果（2026-11-04）：
/// - `tag:A OR tag:B` の複数指定は効く（新しい順）
/// - `created:>=日付 (tag:A OR tag:B)` の括弧は 0 件になる → 人気はタグごとに `tag:X created:>=日付` で取る
/// - 認証なしは 1 時間 60 回。429 は呼び出し側で Qiita だけ一時停止する
class QiitaSource implements ArticleSource {
  QiitaSource([SourceHttp? http]) : _http = http ?? SourceHttp();
  final SourceHttp _http;

  static const maxPopular = 20;

  @override
  SourceType get type => SourceType.qiita;

  ArticleSummary _toSummary(Map<String, dynamic> j) {
    final html = j['rendered_body'] as String? ?? '';
    final images = extractImageUrls(html);
    return ArticleSummary(
      source: type,
      sourceKey: normalizeUrl(j['url'] as String),
      url: j['url'] as String,
      title: j['title'] as String? ?? '',
      author: (j['user'] as Map?)?['id'] as String?,
      tags: [for (final t in (j['tags'] as List? ?? const [])) (t as Map)['name'] as String],
      summary: plainExcerpt(j['body'] as String? ?? html),
      thumbnailUrl: images.isEmpty ? null : images.first,
      likes: j['likes_count'] as int? ?? 0,
      publishedAt: parseTime(j['created_at']),
      extra: {'id': j['id'], 'html': html},
    );
  }

  @override
  Future<Page<ArticleSummary>> fetchLatest({required List<Tag> tags, String? cursor}) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final query = tags.map((t) => 'tag:${t.qiita.replaceAll(' ', '')}').join(' OR ');
    final uri = Uri.https('qiita.com', '/api/v2/items', {'query': query, 'per_page': '20', 'page': '$page'});
    final list = (await _http.getJson(uri) as List).cast<Map<String, dynamic>>();
    return Page(list.map(_toSummary).toList(), list.length == 20 && page < 100 ? '${page + 1}' : null);
  }

  @override
  Future<List<ArticleSummary>> fetchPopular({required List<Tag> tags, required int limit}) async {
    final since = DateTime.now().subtract(const Duration(days: 7));
    final date = '${since.year}-${two(since.month)}-${two(since.day)}';
    final results = <List<ArticleSummary>>[];
    for (final t in tags) {
      final uri = Uri.https('qiita.com', '/api/v2/items', {
        'query': 'tag:${t.qiita.replaceAll(' ', '')} created:>=$date',
        'per_page': '100',
        'page': '1',
      });
      final list = (await _http.getJson(uri) as List).cast<Map<String, dynamic>>();
      results.add(list.map(_toSummary).toList());
    }
    final merged = mergeUnique(results)..sort((a, b) => b.likes.compareTo(a.likes));
    return merged.take(limit.clamp(0, maxPopular)).toList();
  }

  @override
  Future<ArticleContent> fetchContent(ArticleSummary summary) async {
    var html = summary.extra['html'] as String?;
    if (html == null || html.isEmpty) {
      final id = summary.extra['id'] as String? ?? Uri.parse(summary.url).pathSegments.last;
      final j = await _http.getJson(Uri.https('qiita.com', '/api/v2/items/$id')) as Map<String, dynamic>;
      html = j['rendered_body'] as String? ?? '';
    }
    return ArticleContent(html: html, imageUrls: extractImageUrls(html));
  }
}
