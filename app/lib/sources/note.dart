import '../core/util.dart';
import '../models/models.dart';
import 'article_source.dart';

/// note 内部 API（doc/design.md 5.5）
///
/// 検証結果（2026-11-04）：
/// - 一覧：`/api/v3/hashtags/{tag}/notes?order=new|popular&page=N`（`data.notes`、`is_last_page`）
///   popular は直近7日に限らないため、人気は新着を数ページ取って直近7日をいいね順に並べる
/// - 本文：`/api/v3/notes/{key}` の `data.body`（HTML）
/// - 有料記事は price > 0。本文は無料部分のみ
class NoteSource implements ArticleSource {
  NoteSource([SourceHttp? http]) : _http = http ?? SourceHttp();
  final SourceHttp _http;

  static const _popularPages = 3;

  @override
  SourceType get type => SourceType.note;

  ArticleSummary _toSummary(Map<String, dynamic> j, String tag) {
    final user = j['user'] as Map? ?? const {};
    final url = 'https://note.com/${user['urlname']}/n/${j['key']}';
    final price = j['price'] as int? ?? 0;
    return ArticleSummary(
      source: type,
      sourceKey: normalizeUrl(url),
      url: url,
      title: j['name'] as String? ?? '',
      author: user['nickname'] as String? ?? user['urlname'] as String?,
      tags: [tag],
      summary: plainExcerpt((j['description'] as String?) ?? (j['body'] as String?) ?? ''),
      thumbnailUrl: j['eyecatch_url'] as String?,
      likes: j['like_count'] as int? ?? 0,
      publishedAt: parseTime(j['publish_at']),
      isPaidPartial: price > 0,
      extra: {'key': j['key']},
    );
  }

  Future<(List<ArticleSummary>, bool)> _list(Tag t, String order, int page) async {
    final uri = Uri.https('note.com', '/api/v3/hashtags/${Uri.encodeComponent(t.note)}/notes', {'order': order, 'page': '$page'});
    final j = await _http.getJson(uri) as Map<String, dynamic>;
    final data = j['data'] as Map<String, dynamic>? ?? const {};
    // 2026-09 以降、一部ハッシュタグは空になることがある
    final list = (data['notes'] as List? ?? const []).cast<Map<String, dynamic>>().where((n) => n['type'] == 'TextNote').toList();
    return (list.map((n) => _toSummary(n, t.note)).toList(), data['is_last_page'] == false);
  }

  @override
  Future<Page<ArticleSummary>> fetchLatest({required List<Tag> tags, String? cursor}) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final results = await Future.wait(tags.map((t) => _list(t, 'new', page)));
    final items = mergeUnique(results.map((r) => r.$1))..sort((a, b) => (b.publishedAt ?? 0).compareTo(a.publishedAt ?? 0));
    return Page(items, results.any((r) => r.$2) ? '${page + 1}' : null);
  }

  @override
  Future<List<ArticleSummary>> fetchPopular({required List<Tag> tags, required int limit}) async {
    final weekAgo = nowMs() - 7 * dayMs;
    final results = <List<ArticleSummary>>[];
    for (final t in tags) {
      for (var page = 1; page <= _popularPages; page++) {
        final (items, hasNext) = await _list(t, 'new', page);
        results.add(items.where((a) => (a.publishedAt ?? 0) >= weekAgo).toList());
        if (!hasNext || items.any((a) => (a.publishedAt ?? 0) < weekAgo)) break;
      }
    }
    final merged = mergeUnique(results)..sort((a, b) => b.likes.compareTo(a.likes));
    return merged.take(limit).toList();
  }

  static final _key = RegExp(r'^n[0-9a-f]+$');

  /// https://note.com/{user}/n/{key}（独自ドメインの note は対象外）
  @override
  ArticleRef? matchUrl(Uri url) {
    final s = url.pathSegments;
    if (url.host != 'note.com' || s.length != 3 || s[1] != 'n' || !_key.hasMatch(s[2])) return null;
    return ArticleRef(type, s[2], url.toString());
  }

  Future<Map<String, dynamic>> _detail(String key) async {
    final j = await _http.getJson(Uri.https('note.com', '/api/v3/notes/$key')) as Map<String, dynamic>;
    return j['data'] as Map<String, dynamic>? ?? const {};
  }

  static String _html(Map<String, dynamic> d) {
    final eyecatch = d['eyecatch'] as String?;
    return '${eyecatch != null ? '<p><img src="$eyecatch"></p>' : ''}${d['body'] as String? ?? ''}';
  }

  @override
  Future<ArticleSummary> fetchByRef(ArticleRef ref) async {
    final d = await _detail(ref.id);
    final user = d['user'] as Map? ?? const {};
    final url = user['urlname'] != null ? 'https://note.com/${user['urlname']}/n/${ref.id}' : ref.url;
    final html = _html(d);
    return ArticleSummary(
      source: type,
      sourceKey: normalizeUrl(url),
      url: url,
      title: d['name'] as String? ?? '',
      author: user['nickname'] as String? ?? user['urlname'] as String?,
      tags: [
        for (final h in (d['hashtag_notes'] as List? ?? const []))
          if ((h as Map)['hashtag'] is Map) ((h['hashtag'] as Map)['name'] as String? ?? '').replaceFirst('#', ''),
      ].where((t) => t.isNotEmpty).toList(),
      summary: plainExcerpt((d['description'] as String?) ?? (d['body'] as String? ?? '')),
      thumbnailUrl: d['eyecatch'] as String?,
      likes: d['like_count'] as int? ?? 0,
      publishedAt: parseTime(d['publish_at']),
      isPaidPartial: (d['price'] as int? ?? 0) > 0,
      extra: {'key': ref.id, 'html': html},
    );
  }

  @override
  Future<ArticleContent> fetchContent(ArticleSummary summary) async {
    final cached = summary.extra['html'] as String?;
    if (cached != null && cached.isNotEmpty) {
      return ArticleContent(html: cached, imageUrls: extractImageUrls(cached), isPaidPartial: summary.isPaidPartial);
    }
    final key = summary.extra['key'] as String? ?? Uri.parse(summary.url).pathSegments.last;
    final d = await _detail(key);
    final html = _html(d);
    final paid = (d['price'] as int? ?? 0) > 0;
    return ArticleContent(html: html, imageUrls: extractImageUrls(html), isPaidPartial: paid);
  }
}
