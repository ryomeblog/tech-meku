import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/util.dart';
import '../models/models.dart';

/// 興味タグ。サイトごとのタグ名を持つ（doc/design.md 5.2）
class Tag {
  const Tag(this.label, {String? qiita, String? zenn, String? note})
      : qiita = qiita ?? label,
        zenn = zenn ?? label,
        note = note ?? label;

  /// 自由入力：Qiita と note はそのまま、Zenn は小文字化
  factory Tag.free(String label) => Tag(label, zenn: label.toLowerCase().replaceAll(' ', ''));

  final String label;
  final String qiita;
  final String zenn;
  final String note;

  String nameFor(SourceType s) => switch (s) {
        SourceType.qiita => qiita,
        SourceType.zenn => zenn,
        SourceType.note => note,
        SourceType.gigazine || SourceType.app => label,
      };
}

class SourceException implements Exception {
  SourceException(this.message, {this.rateLimited = false, this.notFound = false});
  final String message;
  final bool rateLimited;

  /// 記事が存在しない（404）。サイトの不調ではないので連続失敗に数えない
  final bool notFound;
  @override
  String toString() => message;
}

/// サイトごとに差し替え可能なアダプタ（doc/design.md 5.1）
abstract class ArticleSource {
  SourceType get type;

  /// おすすめ用：タグの新着（投稿日時の新しい順）。cursor でページング
  Future<Page<ArticleSummary>> fetchLatest({required List<Tag> tags, String? cursor});

  /// 一括DL用：タグ内で直近7日のいいね上位
  Future<List<ArticleSummary>> fetchPopular({required List<Tag> tags, required int limit});

  /// 本文HTMLと画像URL一覧
  Future<ArticleContent> fetchContent(ArticleSummary summary);

  /// v2.4：記事 URL（正規化済み）がこのサイトのものなら記事を特定する情報を返す。違えば null
  ArticleRef? matchUrl(Uri url);

  /// v2.4：URL から記事 1 件の要約を取得（プレビュー用）。本文は extra['html'] に入れて保存時に再利用する
  Future<ArticleSummary> fetchByRef(ArticleRef ref);
}

/// 一覧に冒頭や画像がないサイト用：詳細を取ってカードの情報を補う
abstract class Enrichable {
  /// この記事は補う必要があるか
  bool needsEnrich(ArticleSummary s);
  Future<ArticleSummary> enrich(ArticleSummary s);
}

/// 共通の HTTP ヘルパ
class SourceHttp {
  SourceHttp([http.Client? client]) : _client = client ?? http.Client();
  final http.Client _client;

  static const _headers = {'User-Agent': 'TechMeku/0.1 (Android)', 'Accept': 'application/json'};

  /// RSS・HTML などをテキストで取得する
  Future<String> getText(Uri uri) async {
    final http.Response r;
    try {
      r = await _client.get(uri, headers: {'User-Agent': _headers['User-Agent']!}).timeout(const Duration(seconds: 20));
    } catch (e) {
      throw SourceException('通信に失敗しました');
    }
    if (r.statusCode == 429) throw SourceException('レート制限中です', rateLimited: true);
    if (r.statusCode == 404) throw SourceException('記事が見つかりません', notFound: true);
    if (r.statusCode >= 400) throw SourceException('取得に失敗しました（${r.statusCode}）');
    return utf8.decode(r.bodyBytes, allowMalformed: true);
  }

  Future<dynamic> getJson(Uri uri) async {
    final http.Response r;
    try {
      r = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
    } catch (e) {
      throw SourceException('通信に失敗しました');
    }
    if (r.statusCode == 429) throw SourceException('レート制限中です', rateLimited: true);
    if (r.statusCode == 404) throw SourceException('記事が見つかりません', notFound: true);
    if (r.statusCode >= 400) throw SourceException('取得に失敗しました（${r.statusCode}）');
    try {
      return jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      throw SourceException('レスポンスの形式が想定と違います');
    }
  }
}

/// HTML から画像 URL を抜き出す
List<String> extractImageUrls(String html) {
  final re = RegExp(r'''<img[^>]+src=["']([^"']+)["']''', caseSensitive: false);
  return re.allMatches(html).map((m) => m.group(1)!).where((u) => u.startsWith('http')).toSet().toList();
}

/// 本文の冒頭テキスト（カード用、200字程度）
String plainExcerpt(String text, [int n = 200]) {
  final s = text
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ')
      .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1)!)
      .replaceAll(RegExp(r'[#>*_`|]+'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final runes = s.runes.toList();
  return runes.length <= n ? s : '${String.fromCharCodes(runes.take(n))}…';
}

/// 共有テキストなどから最初の http(s) URL を取り出す（v2.4）
String? extractFirstUrl(String text) {
  final m = RegExp(r'''https?://[^\s<>"'「」（）()【】]+''').firstMatch(text);
  if (m == null) return null;
  // 文末の句読点・括弧は URL に含めない
  return m.group(0)!.replaceAll(RegExp(r'[、。,.!?！？）)\]」』]+$'), '');
}

/// 記事 URL の判定用に正規化する：https に統一し、クエリ・フラグメント・末尾スラッシュを除く（6.5）
Uri? articleUri(String text) {
  final raw = extractFirstUrl(text.trim()) ?? text.trim();
  final u = Uri.tryParse(raw);
  if (u == null || u.host.isEmpty || (u.scheme != 'http' && u.scheme != 'https')) return null;
  return Uri.parse(normalizeUrl(u.replace(scheme: 'https').toString()));
}

int? parseTime(Object? s) => s is String ? DateTime.tryParse(s)?.millisecondsSinceEpoch : null;

/// 複数タグの結果を混ぜて URL で重複を除く
List<ArticleSummary> mergeUnique(Iterable<List<ArticleSummary>> lists) {
  final seen = <String>{};
  final out = <ArticleSummary>[];
  for (final l in lists) {
    for (final a in l) {
      if (seen.add(a.sourceKey)) out.add(a);
    }
  }
  return out;
}
