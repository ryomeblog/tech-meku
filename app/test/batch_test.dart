import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:techmeku/core/settings.dart';
import 'package:techmeku/core/util.dart';
import 'package:techmeku/models/models.dart';
import 'package:techmeku/services/batch.dart';
import 'package:techmeku/services/sources.dart';
import 'package:techmeku/services/stock.dart';
import 'package:techmeku/sources/article_source.dart';

class _FakePaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePaths(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

/// 返すセットをテストから差し替えられるアダプタ
class FakeSource implements ArticleSource {
  FakeSource(this.type);
  @override
  final SourceType type;
  List<String> popular = [];
  bool fail = false;
  int contentCalls = 0;
  int? lastLimit;

  ArticleSummary s(String k) => ArticleSummary(source: type, sourceKey: 'https://${type.name}/$k', url: 'https://${type.name}/$k', title: '${type.name} $k', likes: 1);

  @override
  Future<List<ArticleSummary>> fetchPopular({required List<Tag> tags, required int limit}) async {
    lastLimit = limit;
    if (fail) throw SourceException('down');
    return popular.map(s).toList();
  }

  @override
  Future<ArticleContent> fetchContent(ArticleSummary summary) async {
    contentCalls++;
    return ArticleContent(html: '<p>${summary.title}</p>');
  }

  @override
  Future<Page<ArticleSummary>> fetchLatest({required List<Tag> tags, String? cursor}) async => Page([], null);
}

void main() {
  late FakeSource qiita, zenn, note;
  final repo = StockRepo.instance;
  final runner = BatchRunner.instance;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tmp = await Directory.systemTemp.createTemp('techmeku_test');
    PathProviderPlatform.instance = _FakePaths(tmp.path);
    SharedPreferences.setMockInitialValues({'interestTags': ['Flutter']});
    await Settings.instance.init();
    await repo.init();
  });

  setUp(() async {
    await repo.deleteAll();
    await repo.db.delete('liked_items');
    await repo.db.delete('batch_runs');
    await repo.init();
    await Settings.instance.setSwipeCooldownUntil(0);
    qiita = FakeSource(SourceType.qiita);
    zenn = FakeSource(SourceType.zenn);
    note = FakeSource(SourceType.note);
    for (final f in [qiita, zenn, note]) {
      Sources.instance.override(f.type, f);
      await Settings.instance.setFailures(f.type, 0);
    }
  });

  Future<Map<String, StockArticle>> stock() async => {for (final a in await repo.feed()) a.sourceKey.split('/').last: a};
  Future<List<String>> cache() async => (await repo.cacheEntries()).map((e) => e.sourceKey.split('/').last).toList();

  test('初回：人気セットを DL する。Qiita は最大20件', () async {
    qiita.popular = ['q1', 'q2'];
    zenn.popular = ['z1'];
    note.popular = ['n1'];
    final r = await runner.run(BatchTrigger.manual);
    expect(r!.newCount, 4);
    expect((await stock()).keys.toSet(), {'q1', 'q2', 'z1', 'n1'});
    expect(qiita.lastLimit, 20);
    expect(zenn.lastLimit, 50);
    expect((await stock())['q1']!.origin, 'batch');
    expect(File('${repo.absDir((await stock())['q1']!)}/index.html').existsSync(), isTrue);
    // 一覧に冒頭がない記事は、保存した本文から冒頭を作る
    expect((await stock())['z1']!.summary, 'zenn z1');
  });

  test('入れ替え：未閲覧は削除、閲覧済・既読はキャッシュ、個別DL・いいね・新セットは残す', () async {
    qiita.popular = ['keep', 'unread', 'viewed', 'read', 'liked', 'manual'];
    zenn.popular = [];
    note.popular = [];
    await runner.run(BatchTrigger.manual);
    final s = await stock();
    await repo.markViewed(s['viewed']!.id);
    await repo.markRead(s['read']!.id);
    await repo.setLiked(s['liked']!.toSummary(), true);
    await repo.downloadManual(s['manual']!.toSummary());
    final callsBefore = qiita.contentCalls;

    qiita.popular = ['keep', 'new1'];
    final r = await runner.run(BatchTrigger.manual);
    final after = await stock();
    expect(after.keys.toSet(), {'keep', 'new1', 'liked', 'manual'});
    expect(await cache(), unorderedEquals(['viewed', 'read']));
    expect(r!.newCount, 1);
    expect(r.keptCount, 1);
    expect(r.deletedCount, 1);
    expect(r.cachedCount, 2);
    expect(qiita.contentCalls - callsBefore, 1, reason: '新しいセットに含まれる既存記事は再DLしない');
    expect(after['keep']!.id, s['keep']!.id, reason: '閲覧状態を保つため同じ行のまま');
  });

  test('キャッシュは直近1回分だけ。ストックに戻すとキャッシュから外れる', () async {
    qiita.popular = ['a', 'b'];
    await runner.run(BatchTrigger.manual);
    for (final a in (await stock()).values) {
      await repo.markViewed(a.id);
    }
    qiita.popular = ['c'];
    await runner.run(BatchTrigger.manual);
    expect(await cache(), unorderedEquals(['a', 'b']));
    await repo.markViewed((await stock())['c']!.id);
    qiita.popular = ['d'];
    await runner.run(BatchTrigger.manual);
    expect(await cache(), ['c'], reason: '前回のキャッシュはすべて消える');

    await repo.downloadManual(FakeSource(SourceType.qiita).s('c'));
    expect(await cache(), isEmpty);
  });

  test('自動補充：残りの未閲覧はすぐ消さず、見終わった時点でキャッシュへ', () async {
    qiita.popular = ['u1', 'u2'];
    await runner.run(BatchTrigger.manual);
    qiita.popular = ['n1'];
    await runner.maybeAutoRefill(unreadAfter: 4);
    // オンライン判定が無い環境でも run は直接呼べる
    if (runner.lastResult?.newCount != 1) await runner.run(BatchTrigger.swipe, pendingUnread: true);
    final s = await stock();
    expect(s.keys.toSet(), {'u1', 'u2', 'n1'});
    expect(s['u1']!.pendingEvict, isTrue);
    await repo.markViewed(s['u1']!.id);
    expect((await stock()).containsKey('u1'), isFalse);
    expect(await cache(), ['u1']);
  });

  test('自動補充で新規0件なら30分は再実行しない', () async {
    qiita.popular = ['x'];
    await runner.run(BatchTrigger.manual);
    await runner.run(BatchTrigger.swipe, pendingUnread: true);
    expect(Settings.instance.swipeCooldownUntil, greaterThan(nowMs() + 29 * 60 * 1000));
  });

  test('中止したら入れ替えを行わない', () async {
    qiita.popular = ['old'];
    await runner.run(BatchTrigger.manual);
    qiita.popular = List.generate(10, (i) => 'n$i');
    final f = runner.run(BatchTrigger.manual);
    runner.cancel();
    final r = await f;
    expect(r!.canceled, isTrue);
    expect((await stock()).containsKey('old'), isTrue);
  });

  test('一部のサイトが失敗しても全部入れ替える。全サイト失敗なら入れ替えない', () async {
    qiita.popular = ['q'];
    zenn.popular = ['z'];
    await runner.run(BatchTrigger.manual);
    zenn.fail = true;
    qiita.popular = ['q2'];
    final r = await runner.run(BatchTrigger.manual);
    expect(r!.errors.containsKey(SourceType.zenn), isTrue);
    expect((await stock()).keys.toSet(), {'q2'}, reason: '失敗したサイトの古い一括DL分も処理される');

    qiita.fail = true;
    note.fail = true;
    await runner.run(BatchTrigger.manual);
    expect((await stock()).keys.toSet(), {'q2'});
  });

  test('ストックの並び：未閲覧 → 閲覧済 → 既読', () async {
    qiita.popular = ['a', 'b', 'c'];
    await runner.run(BatchTrigger.manual);
    final s = await stock();
    await repo.markRead(s['a']!.id);
    await repo.markViewed(s['b']!.id);
    final order = (await repo.feed()).map((a) => a.sourceKey.split('/').last).toList();
    expect(order, ['c', 'b', 'a']);
  });
}
