import 'dart:convert';

enum SourceType {
  qiita('Qiita'),
  zenn('Zenn'),
  note('note'),
  app('TechMeku');

  const SourceType(this.label);
  final String label;

  static const external = [qiita, zenn, note];
  static SourceType parse(String s) => values.firstWhere((v) => v.name == s, orElse: () => app);
}

/// 外部記事（またはアプリ投稿）のカード用の要約
class ArticleSummary {
  ArticleSummary({
    required this.source,
    required this.sourceKey,
    required this.url,
    required this.title,
    this.author,
    this.tags = const [],
    this.summary,
    this.thumbnailUrl,
    this.likes = 0,
    this.publishedAt,
    this.isPaidPartial = false,
    this.emoji,
    this.extra = const {},
  });

  final SourceType source;

  /// 外部：正規化URL ／ app：投稿ID
  final String sourceKey;
  final String url;
  final String title;
  final String? author;
  final List<String> tags;
  final String? summary;
  final String? thumbnailUrl;
  final int likes;
  final int? publishedAt;
  final bool isPaidPartial;
  final String? emoji;

  /// サイト固有の情報（Qiita の本文 HTML、Zenn の slug、note の key など）
  final Map<String, Object?> extra;
}

/// 全文（サニタイズ前の HTML）
class ArticleContent {
  ArticleContent({required this.html, this.imageUrls = const [], this.isPaidPartial = false});
  final String html;
  final List<String> imageUrls;
  final bool isPaidPartial;
}

class Page<T> {
  Page(this.items, this.nextCursor);
  final List<T> items;
  final String? nextCursor;
}

enum ReadState { unread, viewed, read }

/// ストックの記事（stock_articles）
class StockArticle {
  StockArticle.fromRow(Map<String, Object?> r)
      : id = r['id'] as String,
        source = SourceType.parse(r['source'] as String),
        sourceKey = r['source_key'] as String,
        url = r['url'] as String?,
        origin = r['origin'] as String,
        batchRunId = r['batch_run_id'] as String?,
        title = r['title'] as String,
        author = r['author'] as String?,
        tags = ((jsonDecode((r['tags_json'] as String?) ?? '[]') as List).cast<String>()),
        summary = r['summary'] as String?,
        thumbnailPath = r['thumbnail_path'] as String?,
        dirPath = r['dir_path'] as String,
        sizeBytes = r['size_bytes'] as int,
        likesAtFetch = r['likes_at_fetch'] as int?,
        isPaidPartial = (r['is_paid_partial'] as int? ?? 0) == 1,
        publishedAt = r['published_at'] as int?,
        downloadedAt = r['downloaded_at'] as int,
        viewedAt = r['viewed_at'] as int?,
        readAt = r['read_at'] as int?,
        pendingEvict = (r['pending_evict'] as int? ?? 0) == 1,
        appExpiresAt = r['app_expires_at'] as int?;

  final String id;
  final SourceType source;
  final String sourceKey;
  final String? url;
  final String origin; // 'batch' | 'manual'
  final String? batchRunId;
  final String title;
  final String? author;
  final List<String> tags;
  final String? summary;
  final String? thumbnailPath;
  final String dirPath;
  final int sizeBytes;
  final int? likesAtFetch;
  final bool isPaidPartial;
  final int? publishedAt;
  final int downloadedAt;
  final int? viewedAt;
  final int? readAt;
  final bool pendingEvict;
  final int? appExpiresAt;

  ReadState get state => viewedAt == null ? ReadState.unread : (readAt == null ? ReadState.viewed : ReadState.read);

  ArticleSummary toSummary() => ArticleSummary(
        source: source,
        sourceKey: sourceKey,
        url: url ?? '',
        title: title,
        author: author,
        tags: tags,
        summary: summary,
        likes: likesAtFetch ?? 0,
        publishedAt: publishedAt,
        isPaidPartial: isPaidPartial,
      );
}

class CacheEntry {
  CacheEntry.fromRow(Map<String, Object?> r)
      : id = r['id'] as String,
        source = SourceType.parse(r['source'] as String),
        sourceKey = r['source_key'] as String,
        url = r['url'] as String,
        title = r['title'] as String,
        cachedAt = r['cached_at'] as int,
        expiresAt = r['expires_at'] as int;

  final String id;
  final SourceType source;
  final String sourceKey;
  final String url;
  final String title;
  final int cachedAt;
  final int expiresAt;
}

class LikedItem {
  LikedItem.fromRow(Map<String, Object?> r)
      : id = r['id'] as String,
        kind = r['kind'] as String,
        source = SourceType.parse(r['source'] as String),
        sourceKey = r['source_key'] as String,
        url = r['url'] as String?,
        title = r['title'] as String,
        likedAt = r['liked_at'] as int;

  final String id;
  final String kind; // 'external' | 'app_post'
  final SourceType source;
  final String sourceKey;
  final String? url;
  final String title;
  final int likedAt;
}

/// みんなの投稿（サーバー）
class Post {
  Post.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        title = j['title'] as String,
        excerpt = j['excerpt'] as String? ?? '',
        body = j['body'] as String?,
        tags = (j['tags'] as List? ?? const []).cast<String>(),
        images = (j['images'] as List? ?? const []).cast<String>(),
        authorName = (j['author'] as Map?)?['nickname'] as String? ?? '',
        isMine = j['isMine'] as bool? ?? false,
        likedByMe = j['likedByMe'] as bool? ?? false,
        likeCount = j['likeCount'] as int? ?? 0,
        commentCount = j['commentCount'] as int? ?? 0,
        createdAt = j['createdAt'] as int,
        updatedAt = j['updatedAt'] as int? ?? j['createdAt'] as int,
        edited = j['edited'] as bool? ?? false,
        expiresAt = j['expiresAt'] as int,
        hidden = j['hidden'] as bool? ?? false;

  final String id;
  final String title;
  final String excerpt;
  final String? body;
  final List<String> tags;
  final List<String> images;
  final String authorName;
  final bool isMine;
  bool likedByMe;
  int likeCount;
  int commentCount;
  final int createdAt;
  final int updatedAt;
  final bool edited;
  int expiresAt;
  final bool hidden;

  ArticleSummary toSummary() => ArticleSummary(
        source: SourceType.app,
        sourceKey: id,
        url: '',
        title: title,
        author: authorName,
        tags: tags,
        summary: excerpt,
        likes: likeCount,
        publishedAt: createdAt,
      );
}

class Comment {
  Comment.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        body = j['body'] as String,
        createdAt = j['createdAt'] as int,
        authorName = (j['author'] as Map?)?['nickname'] as String? ?? '',
        isMine = j['isMine'] as bool? ?? false,
        canDelete = j['canDelete'] as bool? ?? false;

  final String id;
  final String body;
  final int createdAt;
  final String authorName;
  final bool isMine;
  final bool canDelete;
}

enum BatchTrigger { manual, scheduled, swipe }

class SiteProgress {
  SiteProgress(this.source);
  final SourceType source;
  int total = 0;
  int done = 0;
  bool finished = false;
  String? error;
}

class BatchResult {
  int newCount = 0;
  int keptCount = 0;
  int cachedCount = 0;
  int deletedCount = 0;
  bool canceled = false;
  bool overLimit = false;
  final Map<SourceType, String> errors = {};
}
