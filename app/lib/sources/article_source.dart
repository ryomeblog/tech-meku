import 'dart:convert';

import 'package:http/http.dart' as http;

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
        SourceType.app => label,
      };
}

class SourceException implements Exception {
  SourceException(this.message, {this.rateLimited = false});
  final String message;
  final bool rateLimited;
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
}

/// 共通の HTTP ヘルパ
class SourceHttp {
  SourceHttp([http.Client? client]) : _client = client ?? http.Client();
  final http.Client _client;

  static const _headers = {'User-Agent': 'TechMeku/0.1 (Android)', 'Accept': 'application/json'};

  Future<dynamic> getJson(Uri uri) async {
    final http.Response r;
    try {
      r = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
    } catch (e) {
      throw SourceException('通信に失敗しました');
    }
    if (r.statusCode == 429) throw SourceException('レート制限中です', rateLimited: true);
    if (r.statusCode == 404) throw SourceException('記事が見つかりません');
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
