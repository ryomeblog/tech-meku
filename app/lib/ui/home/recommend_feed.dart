import 'package:flutter/material.dart';

import '../../core/net.dart';
import '../../core/settings.dart';
import '../../core/techmeku_icon.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../models/models.dart';
import '../../services/api.dart';
import '../../services/sources.dart';
import '../../services/stock.dart';
import '../../services/tags.dart';
import '../../sources/article_source.dart';
import '../../sources/zenn.dart';
import '../common/actions.dart';
import '../common/widgets.dart';
import '../tags/tag_select_page.dart';

/// ホーム：おすすめ（S01）。興味タグの新着を混ぜて投稿日時の新しい順
class RecommendFeed extends StatefulWidget {
  const RecommendFeed({super.key});

  @override
  State<RecommendFeed> createState() => _RecommendFeedState();
}

class _RecommendFeedState extends State<RecommendFeed> with AutomaticKeepAliveClientMixin {
  final _page = PageController();
  final List<ArticleSummary> _items = [];
  final Set<String> _keys = {};
  final Map<SourceType, String?> _cursor = {};
  final Set<SourceType> _done = {};
  final Map<SourceType, String> _errors = {};
  String? _tag; // null = すべて
  SourceType? _site; // null = 設定で ON のサイトすべて。app = TechMeku の投稿
  final Map<String, Post> _posts = {}; // TechMeku の投稿（投稿ID → Post）
  final Set<String> _enriching = {};
  int _index = 0;
  bool _loading = false;
  bool _initial = true;
  int _gen = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    NetStatus.instance.addListener(_onNet);
    StockRepo.instance.addListener(_onRepo);
    Settings.instance.addListener(_onSettings);
    _restart();
  }

  @override
  void dispose() {
    NetStatus.instance.removeListener(_onNet);
    StockRepo.instance.removeListener(_onRepo);
    Settings.instance.removeListener(_onSettings);
    _page.dispose();
    super.dispose();
  }

  List<String> _tagLabels = [];

  void _onSettings() {
    final now = TagService.instance.current().map((t) => t.label).toList();
    if (now.join('|') != _tagLabels.join('|')) _restart();
  }

  void _onRepo() {
    if (mounted) setState(() {});
  }

  void _onNet() {
    if (NetStatus.instance.online && _items.isEmpty) _restart();
    if (mounted) setState(() {});
  }

  void _restart() {
    _gen++;
    _items.clear();
    _keys.clear();
    _cursor.clear();
    _done.clear();
    _errors.clear();
    _posts.clear();
    _enriching.clear();
    _index = 0;
    _initial = true;
    _loading = false;
    _tagLabels = TagService.instance.current().map((t) => t.label).toList();
    if (_tag != null && !_tagLabels.contains(_tag)) _tag = null;
    if (_page.hasClients) _page.jumpToPage(0);
    setState(() {});
    _loadMore();
  }

  /// 読み込むサイト。チップで選んだサイトは、設定で OFF でも表示する
  List<SourceType> get _sites => _site != null ? [_site!] : Settings.instance.enabledSites;

  Future<void> _loadMore() async {
    if (_loading || !NetStatus.instance.online) return;
    if (_site == SourceType.app) return _loadPosts();
    final sites = _sites.where((s) => !_done.contains(s)).toList();
    if (sites.isEmpty) {
      setState(() => _initial = false);
      return;
    }
    final gen = _gen;
    setState(() => _loading = true);
    final tags = _tag == null ? TagService.instance.current() : [tagFor(_tag!)];
    final batch = <ArticleSummary>[];
    await Future.wait(sites.map((s) async {
      if (_cursor.containsKey(s) && _cursor[s] == null) return;
      try {
        final page = await Sources.instance.guard(s, () => Sources.instance.of(s).fetchLatest(tags: tags, cursor: _cursor[s]));
        _cursor[s] = page.nextCursor;
        if (page.nextCursor == null) _done.add(s);
        batch.addAll(page.items);
        _errors.remove(s);
      } on SourceException catch (e) {
        _errors[s] = e.message;
        _done.add(s);
      }
    }));
    if (gen != _gen || !mounted) return;
    batch.sort((a, b) => (b.publishedAt ?? 0).compareTo(a.publishedAt ?? 0));
    setState(() {
      for (final a in batch) {
        if (_keys.add('${a.source.name}|${a.sourceKey}')) _items.add(a);
      }
      _loading = false;
      _initial = false;
    });
    _enrichAround(_index);
  }

  /// #TechMeku：みんなの投稿を新しい順に。タグを選んでいればそのタグの投稿だけ
  Future<void> _loadPosts() async {
    if (_done.contains(SourceType.app)) return;
    final gen = _gen;
    setState(() => _loading = true);
    try {
      final list = await Api.instance.posts();
      if (gen != _gen || !mounted) return;
      final tag = _tag?.toLowerCase();
      final hit = list.where((p) => tag == null || p.tags.any((t) => t.toLowerCase() == tag)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      for (final p in hit) {
        _posts[p.id] = p;
      }
      _items.addAll(hit.map((p) => p.toSummary()));
      _errors.remove(SourceType.app);
    } on ApiException catch (e) {
      _errors[SourceType.app] = e.message;
    }
    if (gen != _gen || !mounted) return;
    setState(() {
      _done.add(SourceType.app);
      _loading = false;
      _initial = false;
    });
  }

  /// Zenn のカードは一覧に冒頭がないので、表示中と次の2枚だけ詳細を取って補う
  void _enrichAround(int i) {
    final zenn = Sources.instance.of(SourceType.zenn);
    if (zenn is! ZennSource) return;
    for (var k = i; k < i + 3 && k < _items.length; k++) {
      final a = _items[k];
      if (a.source != SourceType.zenn || (a.summary?.isNotEmpty ?? false) || !_enriching.add(a.sourceKey)) continue;
      final gen = _gen;
      zenn.enrich(a).then((e) {
        if (gen != _gen || !mounted) return;
        final idx = _items.indexWhere((x) => x.source == SourceType.zenn && x.sourceKey == a.sourceKey);
        if (idx >= 0) setState(() => _items[idx] = e);
      }).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = TmColors.of(context);
    if (!NetStatus.instance.online) {
      return const StatusCard(icon: I.cloud_off, title: 'オフラインです', body: 'ストックをご覧ください');
    }
    final usingRandom = TagService.instance.usingRandom;
    return Column(children: [
      SizedBox(
        height: 48,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
          _chip('すべて', _tag == null && _site == null, () {
            _tag = null;
            _site = null;
            _restart();
          }),
          for (final t in _tagLabels)
            _chip('#$t', _tag == t, () {
              _tag = _tag == t ? null : t;
              _restart();
            }),
          // サイトで絞り込む（タグと組み合わせられる）
          for (final s in SourceType.values)
            _chip('#${s.label}', _site == s, () {
              _site = _site == s ? null : s;
              _restart();
            }),
          ActionChip(
            avatar: const TechMekuIcon(I.tag, size: 16),
            label: Text(usingRandom ? '興味タグを設定' : '編集'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TagSelectPage())),
          ),
        ]),
      ),
      if (usingRandom)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text('興味タグが未設定のため「AI」とランダムな2つのタグを表示しています', style: TextStyle(fontSize: 11, color: c.muted)),
        ),
      if (_errors.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(children: [
            TechMekuIcon(I.warning, size: 14, color: c.warn),
            const SizedBox(width: 4),
            Expanded(child: Text(_errors.values.join(' / '), style: TextStyle(fontSize: 11, color: c.warn), maxLines: 2)),
          ]),
        ),
      Expanded(
        child: _initial && _items.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? StatusCard(
                    icon: I.info,
                    title: _site == SourceType.app ? 'まだ投稿はありません' : '記事が見つかりませんでした',
                    action: OutlinedButton.icon(onPressed: _restart, icon: const TechMekuIcon(I.refresh, size: 18), label: const Text('再読み込み')),
                  )
                : SwipePager(
                    controller: _page,
                    itemCount: _items.length + 1,
                    onPageChanged: (i) {
                      _index = i;
                      _enrichAround(i);
                      // 末尾から5枚目を表示したら次のページを読み込む（設計判断 #12）
                      if (i >= _items.length - 5) _loadMore();
                    },
                    itemBuilder: (context, i) {
                      if (i >= _items.length) {
                        if (_loading || _done.length < _sites.length) {
                          WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
                          return const StatusCard(icon: I.loader, loading: true, title: '続きを読み込み中');
                        }
                        return StatusCard(
                          icon: I.check_circle,
                          title: '新着は以上です',
                          action: OutlinedButton.icon(onPressed: _restart, icon: const TechMekuIcon(I.refresh, size: 18), label: const Text('最初から読み込む')),
                        );
                      }
                      final s = _items[i];
                      final post = s.source == SourceType.app ? _posts[s.sourceKey] : null;
                      final item = FeedItem(summary: s, post: post);
                      return StatefulBuilder(builder: (ctx, set) {
                        final saved = ArticleActions.saved(item);
                        return ArticleCard(
                          key: ValueKey(s.sourceKey),
                          summary: s,
                          badges: [
                            if (post != null) Badge2(remaining(post.expiresAt), icon: I.clock, color: c.active),
                            if (saved) Badge2('保存済', icon: I.check_circle, color: c.active),
                            if (s.isPaidPartial) Badge2('有料記事（無料部分のみ）', color: c.warn),
                          ],
                          onOpen: () => ArticleActions.open(context, item),
                          rail: ActionRail(ArticleActions.rail(ctx, item, refresh: () => set(() {}), onReported: () => setState(() => _items.remove(s)))),
                        );
                      });
                    },
                  ),
      ),
    ]);
  }

  Widget _chip(String label, bool on, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(label: Text(label), selected: on, onSelected: (_) => onTap()),
      );
}
