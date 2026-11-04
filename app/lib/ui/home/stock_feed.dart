import 'package:flutter/material.dart';

import '../../core/net.dart';
import '../../core/settings.dart';
import '../../core/techmeku_icon.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../models/models.dart';
import '../../services/batch.dart';
import '../../services/stock.dart';
import '../common/actions.dart';
import '../common/widgets.dart';
import 'batch_sheet.dart';

/// ホーム：ストック（S02）
class StockFeed extends StatefulWidget {
  const StockFeed({super.key});

  @override
  State<StockFeed> createState() => _StockFeedState();
}

class _StockFeedState extends State<StockFeed> with AutomaticKeepAliveClientMixin {
  final _page = PageController();
  List<StockArticle> _items = [];
  final Set<String> _viewed = {};
  SourceType? _site;
  bool _loaded = false;
  int _index = 0;
  int _bytes = 0;
  bool _wasOnline = NetStatus.instance.online;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    StockRepo.instance.addListener(_onRepo);
    NetStatus.instance.addListener(_onNet);
    _reload();
  }

  @override
  void dispose() {
    StockRepo.instance.removeListener(_onRepo);
    NetStatus.instance.removeListener(_onNet);
    _page.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final items = await StockRepo.instance.feed(site: _site);
    _bytes = await StockRepo.instance.totalBytes();
    if (!mounted) return;
    setState(() {
      _items = items;
      _viewed.clear();
      _loaded = true;
      _index = 0;
    });
    if (_page.hasClients) _page.jumpToPage(0);
    if (items.isNotEmpty) _onShown(0);
  }

  /// セッション中は並びを固定し、新しく DL した記事は末尾に足す（6.3）
  Future<void> _onRepo() async {
    if (!_loaded) return;
    final all = await StockRepo.instance.feed(site: _site);
    _bytes = await StockRepo.instance.totalBytes();
    final have = _items.map((a) => a.id).toSet();
    final added = all.where((a) => !have.contains(a.id)).toList()..sort((a, b) => a.downloadedAt.compareTo(b.downloadedAt));
    if (!mounted) return;
    setState(() => _items = [..._items, ...added]);
  }

  void _onNet() {
    final online = NetStatus.instance.online;
    if (online && !_wasOnline) _checkRefill(); // 接続したら自動で開始
    _wasOnline = online;
    if (mounted) setState(() {});
  }

  int _unreadAfter(int i) {
    var n = 0;
    for (var k = i + 1; k < _items.length; k++) {
      if (_items[k].viewedAt == null && !_viewed.contains(_items[k].id)) n++;
    }
    return n;
  }

  void _onShown(int i) {
    _index = i;
    if (i < _items.length) {
      final a = _items[i];
      if (_viewed.add(a.id)) StockRepo.instance.markViewed(a.id);
    }
    _checkRefill();
  }

  Future<void> _checkRefill() async {
    if (_site != null) return; // 絞り込み中は自動補充しない
    final after = _unreadAfter(_index.clamp(0, _items.length));
    if (after > 4 || BatchRunner.instance.running) return;
    final s = Settings.instance;
    // 自動補充の初回にモバイル通信量の案内を一度出す（設計判断 #15）
    if (NetStatus.instance.online && !NetStatus.instance.onWifi && !s.mobileNoticeShown) {
      await s.setMobileNoticeShown();
      if (mounted) {
        await infoDialog(context,
            title: 'モバイル通信で記事を取得します',
            body: '未閲覧が残り少なくなると、通信の種類に関わらず自動で記事を取得します。画像込みで数百MBの通信になることがあります。',
            icon: I.info);
      }
    }
    await BatchRunner.instance.maybeAutoRefill(unreadAfter: after);
  }

  Future<void> _pickSite() async {
    final v = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: const Text('すべてのサイト'), trailing: _site == null ? const TechMekuIcon(I.check) : null, onTap: () => Navigator.pop(ctx, 'all')),
          for (final s in SourceType.values)
            ListTile(title: Text(s == SourceType.app ? '投稿記事' : s.label), trailing: _site == s ? const TechMekuIcon(I.check) : null, onTap: () => Navigator.pop(ctx, s)),
        ]),
      ),
    );
    if (v == null) return;
    _site = v == 'all' ? null : v as SourceType;
    _reload();
  }

  Widget _header(TmColors c) {
    final s = Settings.instance;
    final last = s.lastBatchAt;
    final unread = _items.where((a) => a.viewedAt == null && !_viewed.contains(a.id)).length;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              TechMekuIcon(I.smartphone, size: 16, active: true),
              Text(' オフラインで読めます', style: TextStyle(color: c.active, fontWeight: FontWeight.bold, fontSize: 13)),
            ]),
            const SizedBox(height: 2),
            Text(
              '${_items.length}件（未閲覧 $unread）・ ${formatBytes(_bytes)} / ${s.storageLimitGb} GB${last != null ? ' ・ 前回更新 ${formatClock(last)}' : ''}',
              style: TextStyle(fontSize: 12, color: _bytes > s.storageLimitBytes ? c.warn : c.muted),
            ),
          ]),
        ),
        IconButton(icon: TechMekuIcon(I.filter, active: _site != null, size: 22), tooltip: 'サイトで絞り込み', onPressed: _pickSite),
        ListenableBuilder(
          listenable: BatchRunner.instance,
          builder: (_, _) => IconButton(
            icon: TechMekuIcon(BatchRunner.instance.running ? I.loader : I.download, active: true, size: 22),
            tooltip: '一括DL',
            onPressed: () async {
              if (!BatchRunner.instance.running) {
                if (!NetStatus.instance.online) {
                  showSnack(context, 'オフラインのため一括DLできません');
                  return;
                }
                BatchRunner.instance.run(BatchTrigger.manual);
              }
              await BatchSheet.show(context);
            },
          ),
        ),
      ]),
    );
  }

  Widget _endCard(TmColors c) {
    return ListenableBuilder(
      listenable: BatchRunner.instance,
      builder: (_, _) {
        final b = BatchRunner.instance;
        if (b.running) {
          return StatusCard(icon: I.loader, loading: true, title: '新しい記事を取得中（${b.done}/${b.total}）', body: '届いた記事から順に後ろへ追加されます');
        }
        if (!NetStatus.instance.online) {
          return const StatusCard(icon: I.cloud_off, title: 'オフラインです', body: '接続すると取得します');
        }
        return StatusCard(
          icon: I.check_circle,
          title: _items.isEmpty ? 'ストックは空です' : 'すべて読みました',
          body: '一括DLで、興味タグの人気記事を端末に保存できます',
          action: FilledButton.icon(
            onPressed: () {
              BatchRunner.instance.run(BatchTrigger.manual);
              BatchSheet.show(context);
            },
            icon: TechMekuIcon(I.download, color: c.bg, size: 18),
            label: const Text('一括DL'),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = TmColors.of(context);
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      _header(c),
      Expanded(
        child: PageView.builder(
          controller: _page,
          scrollDirection: Axis.vertical,
          itemCount: _items.length + 1,
          onPageChanged: _onShown,
          itemBuilder: (context, i) {
            if (i >= _items.length) return _endCard(c);
            final a = _items[i];
            final item = FeedItem.stock(a);
            final badges = <Widget>[
              if (a.readAt != null) const Badge2('既読', icon: I.book_open) else if (a.viewedAt != null || (_viewed.contains(a.id) && i != _index)) const Badge2('閲覧済', icon: I.eye),
              if (a.origin == 'manual') Badge2('個別DL', color: c.active),
              if (a.isPaidPartial) Badge2('有料記事（無料部分のみ）', color: c.warn),
              if (a.source == SourceType.app && (a.appExpiresAt ?? 0) < nowMs()) Badge2('公開終了', color: c.muted),
            ];
            return ArticleCard(
              key: ValueKey(a.id),
              summary: item.summary,
              localThumb: StockRepo.instance.absThumb(a),
              badges: badges,
              onOpen: () async {
                await ArticleActions.open(context, item);
                if (mounted) setState(() {});
              },
              rail: StatefulBuilder(builder: (ctx, set) => ActionRail(ArticleActions.rail(ctx, item, refresh: () => set(() {})))),
            );
          },
        ),
      ),
    ]);
  }
}
