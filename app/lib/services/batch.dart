import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/net.dart';
import '../core/settings.dart';
import '../core/util.dart';
import '../models/models.dart';
import '../sources/article_source.dart';
import '../sources/qiita.dart';
import 'sources.dart';
import 'stock.dart';
import 'tags.dart';

/// 一括DL（入れ替え）（doc/design.md 2.4〜2.6・5.7）
class BatchRunner extends ChangeNotifier {
  BatchRunner._();
  static final BatchRunner instance = BatchRunner._();

  bool running = false;
  BatchTrigger? trigger;
  final Map<SourceType, SiteProgress> progress = {};
  BatchResult? lastResult;
  bool _cancel = false;

  int get total => progress.values.fold(0, (a, p) => a + p.total);
  int get done => progress.values.fold(0, (a, p) => a + p.done);

  /// 手動の一括DLを中止する。中止したら入れ替えは行わない（設計判断 #7）
  void cancel() {
    if (running) _cancel = true;
  }

  /// 自動補充（2.6）：表示したカードの後ろの未閲覧が 4 件以下になったら開始
  Future<void> maybeAutoRefill({required int unreadAfter}) async {
    if (unreadAfter > 4 || running) return;
    if (Settings.instance.swipeCooldownUntil > nowMs()) return;
    if (!NetStatus.instance.online) return; // 接続したら StockFeed 側から再度呼ぶ
    await run(BatchTrigger.swipe, pendingUnread: true);
  }

  Future<BatchResult?> run(BatchTrigger t, {bool pendingUnread = false}) async {
    if (running) return null;
    final s = Settings.instance;
    final repo = StockRepo.instance;
    final sites = s.enabledSites;
    final result = BatchResult();
    if (sites.isEmpty) return result;

    running = true;
    trigger = t;
    _cancel = false;
    progress
      ..clear()
      ..addEntries(sites.map((x) => MapEntry(x, SiteProgress(x))));
    notifyListeners();

    final tags = TagService.instance.current();
    final runId = newId();
    final started = nowMs();
    await repo.db.insert('batch_runs', {
      'id': runId,
      'trigger': t.name,
      'tags_json': jsonEncode(tags.map((x) => x.label).toList()),
      'started_at': started,
      'status': 'running',
    });

    // 自動補充のきっかけになった「残りの未閲覧」は消さずに、見終わった時点でキャッシュへ
    final protectedUnread = <String>{};
    if (pendingUnread) {
      for (final a in await repo.batchArticles()) {
        if (a.viewedAt == null) protectedUnread.add(a.id);
      }
    }

    try {
      // 1) サイトごとに新しいセットを決める
      final newSet = <String>{};
      final toDownload = <SourceType, List<ArticleSummary>>{};
      final failedSites = <SourceType>{};
      await Future.wait(sites.map((site) async {
        final limit = site == SourceType.qiita ? (s.fetchCount < QiitaSource.maxPopular ? s.fetchCount : QiitaSource.maxPopular) : s.fetchCount;
        try {
          final list = await Sources.instance.guard(site, () => Sources.instance.of(site).fetchPopular(tags: tags, limit: limit));
          final pr = progress[site]!;
          final dl = <ArticleSummary>[];
          for (final a in list) {
            newSet.add(StockRepo.keyOf(a.source, a.sourceKey));
            if (repo.isStocked(a.source, a.sourceKey)) {
              result.keptCount++;
            } else {
              dl.add(a);
            }
          }
          pr.total = dl.length;
          toDownload[site] = dl;
        } catch (e) {
          failedSites.add(site);
          progress[site]!
            ..error = e.toString()
            ..finished = true;
          result.errors[site] = e.toString();
        }
        notifyListeners();
      }));

      // 2) 持っていない記事を DL（サイトごとに並列 2）
      await Future.wait(toDownload.entries.map((e) async {
        final pr = progress[e.key]!;
        final queue = [...e.value];
        Future<void> worker() async {
          while (queue.isNotEmpty && !_cancel) {
            final a = queue.removeAt(0);
            try {
              final content = await Sources.instance.guard(a.source, () => Sources.instance.of(a.source).fetchContent(a));
              await repo.save(summary: a, content: content, origin: 'batch', batchRunId: runId, canceled: () => _cancel);
              result.newCount++;
            } on SourceException catch (err) {
              if (err.rateLimited) {
                queue.clear();
                pr.error = err.message;
                result.errors[e.key] = err.message;
              }
            } catch (_) {}
            pr.done++;
            notifyListeners();
          }
        }

        await Future.wait([worker(), worker()]);
        pr.finished = true;
        notifyListeners();
      }));

      if (_cancel) {
        result.canceled = true;
      } else if (failedSites.length < sites.length) {
        // 3) 入れ替え（2.5）。一部のサイトが失敗しても全部入れ替える。
        //    全サイトが失敗したとき（オフライン等）は、手元の記事を守るため入れ替えない【設計判断】
        await _replace(runId, newSet, protectedUnread, result);
      }

      final bytes = await repo.totalBytes();
      result.overLimit = bytes > s.storageLimitBytes;
      if (t == BatchTrigger.swipe && result.newCount == 0) {
        await s.setSwipeCooldownUntil(nowMs() + 30 * 60 * 1000); // 設計判断 #9
      }
      if (!result.canceled) await s.setLastBatchAt(nowMs());
    } finally {
      await repo.db.update(
        'batch_runs',
        {
          'finished_at': nowMs(),
          'status': result.canceled ? 'canceled' : 'done',
          'new_count': result.newCount,
          'kept_count': result.keptCount,
          'cached_count': result.cachedCount,
          'deleted_count': result.deletedCount,
          'errors_json': jsonEncode(result.errors.map((k, v) => MapEntry(k.name, v))),
        },
        where: 'id = ?',
        whereArgs: [runId],
      );
      running = false;
      lastResult = result;
      notifyListeners();
      repo.changed();
    }
    return result;
  }

  Future<void> _replace(String runId, Set<String> newSet, Set<String> protectedUnread, BatchResult result) async {
    final repo = StockRepo.instance;
    final toCache = <StockArticle>[];
    final pending = <String>[];
    for (final a in await repo.batchArticles()) {
      if (a.batchRunId == runId) continue;
      if (newSet.contains(StockRepo.keyOf(a.source, a.sourceKey))) continue; // 新しいセットに含まれる既存記事は残す
      if (repo.isLiked(a.source, a.sourceKey)) continue; // いいね済みは残す
      if (a.viewedAt == null) {
        if (protectedUnread.contains(a.id)) {
          pending.add(a.id);
        } else {
          await repo.delete(a, notify: false);
          result.deletedCount++;
        }
      } else {
        toCache.add(a);
      }
    }
    if (pending.isNotEmpty) await repo.setPendingEvict(pending);
    if (toCache.isNotEmpty) {
      // 次の入れ替えでキャッシュに追加するときは、それまでのキャッシュを全削除（2.8）
      await repo.moveToCache(toCache, clearExisting: true);
      result.cachedCount += toCache.length;
    }
  }
}
