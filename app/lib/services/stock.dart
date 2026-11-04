import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../core/config.dart';
import '../core/db.dart';
import '../core/util.dart';
import '../models/models.dart';
import '../sources/article_source.dart';
import 'html.dart';
import 'sources.dart';

/// ストック（端末に保存した記事）・キャッシュ・いいね一覧
class StockRepo extends ChangeNotifier {
  StockRepo._();
  static final StockRepo instance = StockRepo._();

  late Database _db;
  late Directory _root;
  final Set<String> _stockKeys = {};
  final Set<String> _likedKeys = {};
  final _imgClient = http.Client();

  static String keyOf(SourceType s, String sourceKey) => '${s.name}|$sourceKey';

  Future<void> init() async {
    _db = await AppDb.open();
    // OS に消されない領域（キャッシュ領域は使わない）
    _root = Directory(p.join((await getApplicationSupportDirectory()).path, 'articles'));
    await _root.create(recursive: true);
    await _reloadKeys();
    await _backfillSummaries();
  }

  /// 冒頭（summary）がない保存済み記事に、本文ファイルから冒頭を補う
  Future<void> _backfillSummaries() async {
    final rows = await _db.query('stock_articles', columns: ['id', 'dir_path'], where: "summary IS NULL OR summary = ''");
    for (final r in rows) {
      final f = File(p.join(_root.path, r['dir_path'] as String, 'index.html'));
      if (!await f.exists()) continue;
      final text = plainExcerpt(await f.readAsString());
      if (text.isNotEmpty) await _db.update('stock_articles', {'summary': text}, where: 'id = ?', whereArgs: [r['id']]);
    }
  }

  Database get db => _db;

  Future<void> _reloadKeys() async {
    _stockKeys
      ..clear()
      ..addAll((await _db.query('stock_articles', columns: ['source', 'source_key'])).map((r) => '${r['source']}|${r['source_key']}'));
    _likedKeys
      ..clear()
      ..addAll((await _db.query('liked_items', columns: ['source', 'source_key'])).map((r) => '${r['source']}|${r['source_key']}'));
  }

  void changed() => notifyListeners();

  bool isStocked(SourceType s, String key) => _stockKeys.contains(keyOf(s, key));
  bool isLiked(SourceType s, String key) => _likedKeys.contains(keyOf(s, key));

  // ------------------------------------------------------------ 取得

  /// ストックの並び（6.3）：未閲覧 → 閲覧済 → 既読、それぞれ DL が新しい順
  Future<List<StockArticle>> feed({SourceType? site, String? origin}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (site != null) {
      where.add('source = ?');
      args.add(site.name);
    }
    if (origin != null) {
      where.add('origin = ?');
      args.add(origin);
    }
    final rows = await _db.rawQuery('''
      SELECT * FROM stock_articles ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY CASE WHEN viewed_at IS NULL THEN 0 WHEN read_at IS NULL THEN 1 ELSE 2 END, downloaded_at DESC''', args);
    return rows.map(StockArticle.fromRow).toList();
  }

  Future<StockArticle?> byKey(SourceType s, String key) async {
    final r = await _db.query('stock_articles', where: 'source = ? AND source_key = ?', whereArgs: [s.name, key], limit: 1);
    return r.isEmpty ? null : StockArticle.fromRow(r.first);
  }

  Future<StockArticle?> byId(String id) async {
    final r = await _db.query('stock_articles', where: 'id = ?', whereArgs: [id], limit: 1);
    return r.isEmpty ? null : StockArticle.fromRow(r.first);
  }

  Future<int> totalBytes() async {
    final r = await _db.rawQuery('SELECT COALESCE(SUM(size_bytes), 0) AS n FROM stock_articles');
    return (r.first['n'] as int?) ?? 0;
  }

  Future<int> count() async => Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM stock_articles')) ?? 0;

  Future<String> readBody(StockArticle a) async {
    final f = File(p.join(_root.path, a.dirPath, 'index.html'));
    return await f.exists() ? f.readAsString() : '<p>本文ファイルが見つかりません。</p>';
  }

  String absDir(StockArticle a) => p.join(_root.path, a.dirPath);
  String? absThumb(StockArticle a) => a.thumbnailPath == null ? null : p.join(_root.path, a.thumbnailPath!);

  // ------------------------------------------------------------ 保存

  /// 本文と画像を保存してストックに追加する（5.7 の 5）
  Future<StockArticle> save({
    required ArticleSummary summary,
    required ArticleContent content,
    required String origin,
    String? batchRunId,
    int? appExpiresAt,
    bool Function()? canceled,
  }) async {
    final id = newId();
    final rel = id;
    final dir = Directory(p.join(_root.path, rel));
    final imgDir = Directory(p.join(dir.path, 'img'));
    await imgDir.create(recursive: true);
    var size = 0;
    String? thumb;
    try {
      // 画像をダウンロードして src をローカルパスに書き換え（失敗した画像だけ代替表示）
      final map = <String, String>{};
      var n = 0;
      for (final url in content.imageUrls.take(60)) {
        if (canceled?.call() ?? false) break;
        try {
          final r = await _imgClient.get(Uri.parse(url), headers: {'User-Agent': 'TechMeku/0.1 (Android)'}).timeout(const Duration(seconds: 20));
          if (r.statusCode != 200 || r.bodyBytes.isEmpty) continue;
          final ext = _extOf(url, r.headers['content-type']);
          final name = 'img/${n++}$ext';
          await File(p.join(dir.path, name)).writeAsBytes(r.bodyBytes);
          size += r.bodyBytes.length;
          map[url] = name;
          thumb ??= '$rel/$name';
        } catch (_) {}
      }
      final body = sanitizeHtml(content.html, rewriteImg: (src) => map[src] ?? src);
      final bytes = utf8.encode(body);
      await File(p.join(dir.path, 'index.html')).writeAsBytes(bytes);
      size += bytes.length;
    } catch (e) {
      await dir.delete(recursive: true).catchError((_) => dir);
      rethrow;
    }

    final now = nowMs();
    final row = {
      'id': id,
      'source': summary.source.name,
      'source_key': summary.sourceKey,
      'url': summary.source == SourceType.app ? null : summary.url,
      'origin': origin,
      'batch_run_id': batchRunId,
      'title': summary.title,
      'author': summary.author,
      'tags_json': jsonEncode(summary.tags),
      // Zenn など一覧に冒頭がないサイトは、保存した本文から作る
      'summary': (summary.summary == null || summary.summary!.isEmpty) ? plainExcerpt(content.html) : summary.summary,
      'thumbnail_path': thumb,
      'dir_path': rel,
      'size_bytes': size,
      'likes_at_fetch': summary.likes,
      'is_paid_partial': (summary.isPaidPartial || content.isPaidPartial) ? 1 : 0,
      'published_at': summary.publishedAt,
      'downloaded_at': now,
      'app_expires_at': appExpiresAt,
    };
    try {
      await _db.insert('stock_articles', row);
    } on DatabaseException {
      // 同時に保存された（UNIQUE 違反）→ 今回のファイルを捨てる
      await dir.delete(recursive: true).catchError((_) => dir);
      final existing = await byKey(summary.source, summary.sourceKey);
      if (existing != null) return existing;
      rethrow;
    }
    // ストックに戻ったのでキャッシュからは外す
    await _db.delete('cache_entries', where: 'source = ? AND source_key = ?', whereArgs: [summary.source.name, summary.sourceKey]);
    _stockKeys.add(keyOf(summary.source, summary.sourceKey));
    notifyListeners();
    return (await byId(id))!;
  }

  String _extOf(String url, String? ct) {
    if (ct != null) {
      if (ct.contains('png')) return '.png';
      if (ct.contains('gif')) return '.gif';
      if (ct.contains('webp')) return '.webp';
      if (ct.contains('svg')) return '.svg';
      if (ct.contains('jpeg') || ct.contains('jpg')) return '.jpg';
    }
    final e = p.extension(Uri.parse(url).path).toLowerCase();
    return const ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg'].contains(e) ? e : '.img';
  }

  /// 個別DL（origin=manual）。既に一括DL分として持っていれば manual に変えて保護する
  Future<StockArticle> downloadManual(ArticleSummary s, {Post? post}) async {
    final existing = await byKey(s.source, s.sourceKey);
    if (existing != null) {
      if (existing.origin != 'manual') {
        await _db.update('stock_articles', {'origin': 'manual', 'pending_evict': 0}, where: 'id = ?', whereArgs: [existing.id]);
        notifyListeners();
      }
      return (await byId(existing.id))!;
    }
    final ArticleContent content;
    if (s.source == SourceType.app) {
      final pp = post!;
      final urls = pp.images.map((k) => '${AppConfig.apiBase}/images/$k').toList();
      final html = markdownToHtml(pp.body ?? pp.excerpt, urls);
      content = ArticleContent(html: html, imageUrls: urls);
    } else {
      content = await Sources.instance.guard(s.source, () => Sources.instance.of(s.source).fetchContent(s));
    }
    return save(summary: s, content: content, origin: 'manual', appExpiresAt: post?.expiresAt);
  }

  // ------------------------------------------------------------ 閲覧状態

  /// カードを表示した（閲覧済）。pending_evict ならキャッシュへ移す（6.3）
  Future<void> markViewed(String id) async {
    final a = await byId(id);
    if (a == null) return;
    if (a.viewedAt == null) {
      await _db.update('stock_articles', {'viewed_at': nowMs()}, where: 'id = ?', whereArgs: [id]);
    }
    if (a.pendingEvict) {
      await moveToCache([a], clearExisting: false);
      notifyListeners();
    }
  }

  /// 全文を開いた（既読）
  Future<void> markRead(String id) async {
    final t = nowMs();
    await _db.rawUpdate('UPDATE stock_articles SET read_at = COALESCE(read_at, ?), viewed_at = COALESCE(viewed_at, ?) WHERE id = ?', [t, t, id]);
  }

  // ------------------------------------------------------------ 削除・キャッシュ

  Future<void> _deleteFiles(StockArticle a) async {
    final d = Directory(p.join(_root.path, a.dirPath));
    if (await d.exists()) await d.delete(recursive: true);
  }

  Future<void> delete(StockArticle a, {bool notify = true}) async {
    await _deleteFiles(a);
    await _db.delete('stock_articles', where: 'id = ?', whereArgs: [a.id]);
    _stockKeys.remove(keyOf(a.source, a.sourceKey));
    if (notify) notifyListeners();
  }

  Future<void> deleteAll() async {
    await _db.delete('stock_articles');
    await _db.delete('cache_entries');
    if (await _root.exists()) await _root.delete(recursive: true);
    await _root.create(recursive: true);
    _stockKeys.clear();
    notifyListeners();
  }

  /// 本文・画像を削除し、タイトル＋URL だけをキャッシュに残す（24時間）
  Future<void> moveToCache(List<StockArticle> list, {required bool clearExisting}) async {
    if (clearExisting) await _db.delete('cache_entries');
    final now = nowMs();
    for (final a in list) {
      await _deleteFiles(a);
      await _db.delete('stock_articles', where: 'id = ?', whereArgs: [a.id]);
      _stockKeys.remove(keyOf(a.source, a.sourceKey));
      if (a.url == null) continue; // 投稿記事はキャッシュにしない
      await _db.insert(
        'cache_entries',
        {'id': newId(), 'source': a.source.name, 'source_key': a.sourceKey, 'url': a.url, 'title': a.title, 'cached_at': now, 'expires_at': now + dayMs},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// 期限切れのキャッシュを削除（5.9）
  Future<void> purgeExpiredCache() => _db.delete('cache_entries', where: 'expires_at <= ?', whereArgs: [nowMs()]);

  Future<List<CacheEntry>> cacheEntries() async {
    await purgeExpiredCache();
    return (await _db.query('cache_entries', orderBy: 'cached_at DESC')).map(CacheEntry.fromRow).toList();
  }

  Future<void> deleteCache(String id) async {
    await _db.delete('cache_entries', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  // ------------------------------------------------------------ いいね（端末ローカル）

  Future<void> setLiked(ArticleSummary s, bool liked) async {
    final k = keyOf(s.source, s.sourceKey);
    if (liked) {
      await _db.insert(
        'liked_items',
        {
          'id': newId(),
          'kind': s.source == SourceType.app ? 'app_post' : 'external',
          'source': s.source.name,
          'source_key': s.sourceKey,
          'url': s.source == SourceType.app ? null : s.url,
          'title': s.title,
          'liked_at': nowMs(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      _likedKeys.add(k);
    } else {
      await _db.delete('liked_items', where: 'source = ? AND source_key = ?', whereArgs: [s.source.name, s.sourceKey]);
      _likedKeys.remove(k);
    }
    notifyListeners();
  }

  Future<List<LikedItem>> likedItems() async => (await _db.query('liked_items', orderBy: 'liked_at DESC')).map(LikedItem.fromRow).toList();

  // ------------------------------------------------------------ 一括DL用

  Future<List<StockArticle>> batchArticles() async =>
      (await _db.query('stock_articles', where: "origin = 'batch' AND source <> 'app'")).map(StockArticle.fromRow).toList();

  Future<void> setPendingEvict(List<String> ids) async {
    for (final id in ids) {
      await _db.update('stock_articles', {'pending_evict': 1}, where: 'id = ?', whereArgs: [id]);
    }
  }

  /// 「ArticleSummary」から全文用の情報を復元（キャッシュ・いいねの Web 表示用）
  static ArticleSummary summaryFromUrl(SourceType s, String url, String title) =>
      ArticleSummary(source: s, sourceKey: normalizeUrl(url), url: url, title: title);
}

extension on Future<FileSystemEntity> {
  // ignore: unused_element
  Future<void> ignore() => then((_) {});
}

/// 外部記事の全文をオンライン取得（保存しない）
Future<ArticleContent> fetchOnline(ArticleSummary s) =>
    Sources.instance.guard(s.source, () => Sources.instance.of(s.source).fetchContent(s)).then((c) => ArticleContent(
          html: sanitizeHtml(c.html),
          imageUrls: c.imageUrls,
          isPaidPartial: c.isPaidPartial || s.isPaidPartial,
        ));

typedef SourceError = SourceException;
