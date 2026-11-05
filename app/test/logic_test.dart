import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:techmeku/core/util.dart';
import 'package:techmeku/models/models.dart';
import 'package:techmeku/services/html.dart';
import 'package:techmeku/services/tags.dart';
import 'package:techmeku/sources/article_source.dart';
import 'package:techmeku/sources/gigazine.dart';
import 'package:techmeku/sources/note.dart';
import 'package:techmeku/sources/qiita.dart';
import 'package:techmeku/sources/zenn.dart';

String iso(DateTime d) => d.toIso8601String();

void main() {
  group('util', () {
    test('URL の正規化：クエリ・フラグメント・末尾スラッシュを除く', () {
      expect(normalizeUrl('https://Qiita.com/u/items/abc/?utm=1#x'), 'https://qiita.com/u/items/abc');
      expect(normalizeUrl('https://zenn.dev/a/articles/b'), 'https://zenn.dev/a/articles/b');
    });

    test('残り時間の表示', () {
      final now = DateTime(2026, 11, 4).millisecondsSinceEpoch;
      expect(remaining(now + 3 * hourMs + 12 * 60000, now: now), 'あと 3時間12分');
      expect(remaining(now + 26 * hourMs, now: now), 'あと 1日2時間');
      expect(remaining(now - 1, now: now), '公開終了');
    });

    test('冒頭テキストは 200 字で切る', () {
      final s = plainExcerpt('<p>${'あ' * 300}</p>');
      expect(s.runes.length, 201);
      expect(s.endsWith('…'), isTrue);
      expect(plainExcerpt('# 見出し\n**太字** [link](http://x)'), '見出し 太字 link');
    });
  });

  group('HTML', () {
    test('script・on* 属性・javascript: を除去する', () {
      final out = sanitizeHtml('<p onclick="x()">a</p><script>alert(1)</script><a href="javascript:x">b</a><iframe src="y"></iframe><img src="http://i/1.png" onerror="z">');
      expect(out, isNot(contains('script')));
      expect(out, isNot(contains('onclick')));
      expect(out, isNot(contains('onerror')));
      expect(out, isNot(contains('javascript')));
      expect(out, isNot(contains('iframe')));
      expect(out, contains('<img src="http://i/1.png"'));
    });

    test('画像の src をローカルパスに書き換える', () {
      final out = sanitizeHtml('<img src="http://i/1.png"><img src="http://i/2.png">', rewriteImg: (s) => s.endsWith('1.png') ? 'img/0.png' : s);
      expect(out, contains('src="img/0.png"'));
      expect(out, contains('src="http://i/2.png"'));
    });

    test('投稿の Markdown：attachment:N を画像 URL にし、生の HTML は無害化', () {
      final out = markdownToHtml('# T\n\n![](attachment:2)\n\n<script>x</script>', ['u1', 'u2']);
      expect(out, contains('T</h1>'));
      expect(out, contains('src="u2"'));
      expect(out, isNot(contains('<script')));
    });
  });

  group('タグ', () {
    test('一覧のタグはサイトごとの名前、自由入力は Zenn だけ小文字', () {
      final g = tagFor('Google Cloud');
      expect(g.nameFor(SourceType.qiita), 'GoogleCloud');
      expect(g.nameFor(SourceType.zenn), 'googlecloud');
      final f = tagFor('Svelte');
      expect(f.nameFor(SourceType.qiita), 'Svelte');
      expect(f.nameFor(SourceType.zenn), 'svelte');
      expect(presetTags.length, 24);
    });
  });

  group('Qiita', () {
    Map<String, dynamic> item(String id, int likes, DateTime at, {List<String> tags = const ['Flutter']}) => {
          'id': id,
          'url': 'https://qiita.com/u/items/$id',
          'title': 'title $id',
          'user': {'id': 'u'},
          'tags': [for (final t in tags) {'name': t}],
          'body': 'body $id',
          'rendered_body': '<p>body</p><img src="https://img/$id.png">',
          'likes_count': likes,
          'created_at': iso(at),
        };

    test('新着は OR で複数タグ、人気はタグごと・いいね順・最大20件', () async {
      final queries = <String>[];
      final now = DateTime.now();
      final client = MockClient((req) async {
        queries.add(req.url.queryParameters['query']!);
        final perPage = int.parse(req.url.queryParameters['per_page']!);
        final list = [for (var i = 0; i < perPage.clamp(0, 30); i++) item('${req.url.queryParameters['query']!.hashCode}-$i', i, now)];
        return http.Response(jsonEncode(list), 200, headers: {'content-type': 'application/json'});
      });
      final q = QiitaSource(SourceHttp(client));
      final latest = await q.fetchLatest(tags: [tagFor('Flutter'), tagFor('Go')]);
      expect(queries.last, 'tag:Flutter OR tag:Go');
      expect(latest.items.length, 20);
      expect(latest.nextCursor, '2');
      expect(latest.items.first.thumbnailUrl, startsWith('https://img/'));

      final popular = await q.fetchPopular(tags: [tagFor('Flutter'), tagFor('Go')], limit: 50);
      expect(popular.length, 20);
      expect(queries.where((x) => x.contains('created:>=')).length, 2);
      expect(popular.first.likes >= popular.last.likes, isTrue);
    });

    test('429 はレート制限として扱う', () async {
      final q = QiitaSource(SourceHttp(MockClient((_) async => http.Response('', 429))));
      expect(() => q.fetchLatest(tags: [tagFor('AI')]), throwsA(isA<SourceException>().having((e) => e.rateLimited, 'rateLimited', true)));
    });
  });

  group('Zenn', () {
    test('人気は weekly、直近7日だけをいいね順。本文は body_html', () async {
      final now = DateTime.now();
      final client = MockClient((req) async {
        if (req.url.path == '/api/articles') {
          expect(req.url.queryParameters['order'], 'weekly');
          return http.Response.bytes(
              utf8.encode(jsonEncode({
                'articles': [
                  {'slug': 'a', 'path': '/x/articles/a', 'title': 'A', 'liked_count': 5, 'published_at': iso(now), 'emoji': '🦀', 'user': {'name': 'x'}},
                  {'slug': 'b', 'path': '/x/articles/b', 'title': 'B', 'liked_count': 50, 'published_at': iso(now.subtract(const Duration(days: 9))), 'user': {'name': 'x'}},
                  {'slug': 'c', 'path': '/x/articles/c', 'title': 'C', 'liked_count': 9, 'published_at': iso(now), 'user': {'name': 'x'}},
                ],
                'next_page': null,
              })),
              200);
        }
        return http.Response(jsonEncode({'article': {'body_html': '<p>hi</p>'}}), 200);
      });
      final z = ZennSource(SourceHttp(client));
      final list = await z.fetchPopular(tags: [tagFor('Rust')], limit: 10);
      expect(list.map((a) => a.title), ['C', 'A']);
      expect(list.last.emoji, '🦀');
      expect((await z.fetchContent(list.first)).html, '<p>hi</p>');
    });
  });

  group('Zenn の冒頭補完', () {
    test('詳細から冒頭と最初の画像を補い、全文表示では再取得しない', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        return http.Response.bytes(utf8.encode(jsonEncode({'article': {'body_html': '<p>本文の冒頭です</p><img src="https://img/z.png">'}})), 200);
      });
      final z = ZennSource(SourceHttp(client));
      final s = ArticleSummary(source: SourceType.zenn, sourceKey: 'https://zenn.dev/x/articles/a', url: 'https://zenn.dev/x/articles/a', title: 'A', extra: {'slug': 'a'});
      final e = await z.enrich(s);
      expect(e.summary, '本文の冒頭です');
      expect(e.thumbnailUrl, 'https://img/z.png');
      expect(e.title, 'A');
      await z.fetchContent(e);
      expect(calls, 1);
    });
  });

  group('GIGAZINE', () {
    final now = DateTime.now();
    String rss(List<(String, DateTime, String)> items) => '''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/"><channel><title>GIGAZINE</title>
${items.map((i) => '<item><title>${i.$1}</title><link>https://gigazine.net/news/${i.$1}/</link>'
        '<description><![CDATA[${i.$1}の要約です。<p><b><a href="https://gigazine.net/news/x/">続きを読む...</a></b></p>]]></description>'
        '<dc:subject>${i.$3}</dc:subject><dc:date>${i.$2.toIso8601String()}</dc:date></item>').join()}
</channel></rss>''';
    const page = '<html><body><div id="article"><div class="cntimage">'
        '<time class="yeartime">2026年11月05日</time><span class="yeartime p-category">取材</span>'
        '<h1 class="title">見出し</h1><p class="preface">本文です</p>'
        '<img src="https://i.gzn.jp/a_m.jpg"><img data-src="https://i.gzn.jp/b_m.jpg" class="lazyload">'
        '<script>x()</script></div><!-- google_ad_section_end --><p>広告など</p></div></body></html>';

    test('RSS から新着を取り、タグは使わない。一括DLは直近7日を新しい順', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/news/rss_2.0/') {
          return http.Response.bytes(utf8.encode(rss([
            ('old', now.subtract(const Duration(days: 9)), 'ゲーム,'),
            ('new1', now.subtract(const Duration(hours: 2)), 'AI, ソフトウェア,'),
            ('new2', now.subtract(const Duration(hours: 1)), 'セキュリティ,'),
          ])), 200);
        }
        return http.Response.bytes(utf8.encode(page), 200);
      });
      final g = GigazineSource(SourceHttp(client));
      final latest = await g.fetchLatest(tags: [tagFor('Flutter')]);
      expect(latest.items.map((a) => a.title), ['new2', 'new1', 'old']);
      expect(latest.nextCursor, isNull);
      expect(latest.items[1].tags, ['AI', 'ソフトウェア']);
      expect(latest.items[1].summary, 'new1の要約です。');
      final popular = await g.fetchPopular(tags: const [], limit: 50);
      expect(popular.map((a) => a.title), ['new2', 'new1']);
      // 画像は記事ページから補い、本文は全文表示で再利用する
      final e = await g.enrich(popular.first);
      expect(e.thumbnailUrl, 'https://i.gzn.jp/a_m.jpg');
      expect(g.needsEnrich(e), isFalse);
    });

    test('記事ページから本文だけを取り出す（見出し・日時・スクリプト・広告は除く）', () {
      final body = extractGigazineBody(page);
      expect(body, contains('本文です'));
      expect(body, isNot(contains('見出し')));
      expect(body, isNot(contains('2026年11月05日')));
      expect(body, isNot(contains('<script')));
      expect(body, isNot(contains('広告など')));
      expect(extractImageUrls(body), ['https://i.gzn.jp/a_m.jpg', 'https://i.gzn.jp/b_m.jpg']);
    });
  });

  group('note', () {
    test('有料記事の判定、直近7日のいいね順、URL の組み立て', () async {
      final now = DateTime.now();
      Map<String, dynamic> n(String key, int likes, DateTime at, {int price = 0}) => {
            'key': key,
            'name': 'note $key',
            'type': 'TextNote',
            'like_count': likes,
            'publish_at': iso(at),
            'price': price,
            'description': 'desc',
            'eyecatch_url': 'https://e/$key.png',
            'user': {'urlname': 'me', 'nickname': 'Me'},
          };
      final client = MockClient((req) async => http.Response(
            jsonEncode({
              'data': {
                'notes': [n('n1', 3, now), n('n2', 30, now, price: 300), n('n3', 99, now.subtract(const Duration(days: 8)))],
                'is_last_page': true,
              }
            }),
            200,
          ));
      final s = NoteSource(SourceHttp(client));
      final list = await s.fetchPopular(tags: [tagFor('AI')], limit: 10);
      expect(list.map((a) => a.title), ['note n2', 'note n1']);
      expect(list.first.isPaidPartial, isTrue);
      expect(list.first.url, 'https://note.com/me/n/n2');
    });
  });
}
