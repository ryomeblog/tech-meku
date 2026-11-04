import 'package:flutter/material.dart';

import '../../core/techmeku_icon.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../models/models.dart';
import '../../services/stock.dart';
import '../common/actions.dart';
import '../common/widgets.dart';

/// DLしたもの一覧（S15）。全件＋キャッシュ（「キャッシュ」表示）。絞り込み・削除
class DownloadedListPage extends StatefulWidget {
  const DownloadedListPage({super.key});

  @override
  State<DownloadedListPage> createState() => _DownloadedListPageState();
}

class _DownloadedListPageState extends State<DownloadedListPage> {
  SourceType? _site;

  Future<(List<StockArticle>, List<CacheEntry>)> _load() async {
    final repo = StockRepo.instance;
    final stock = await repo.feed(site: _site);
    // 表示時に期限切れのキャッシュを削除し、期限切れは出さない（5.9）
    final cache = (await repo.cacheEntries()).where((e) => _site == null || e.source == _site).toList();
    stock.sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
    return (stock, cache);
  }

  @override
  Widget build(BuildContext context) {
    final c = TmColors.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const TechMekuIcon(I.back), onPressed: () => Navigator.pop(context)),
        title: const Text('DLしたもの', style: TextStyle(fontSize: 17)),
        actions: [
          PopupMenuButton<Object>(
            icon: TechMekuIcon(I.filter, active: _site != null),
            onSelected: (v) => setState(() => _site = v == 'all' ? null : v as SourceType),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'all', child: Text('すべて')),
              for (final s in SourceType.values) PopupMenuItem(value: s, child: Text(s == SourceType.app ? '投稿記事' : s.label)),
            ],
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: StockRepo.instance,
        builder: (context, _) => FutureBuilder<(List<StockArticle>, List<CacheEntry>)>(
          future: _load(),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final (stock, cache) = snap.data!;
            if (stock.isEmpty && cache.isEmpty) return const EmptyState(icon: I.database, text: 'DLした記事はありません');
            return ListView(children: [
              for (final a in stock)
                ListTile(
                  leading: TechMekuIcon(switch (a.state) {
                    ReadState.unread => I.eye_off,
                    ReadState.viewed => I.eye,
                    ReadState.read => I.book_open,
                  }, muted: a.state == ReadState.read),
                  title: Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${a.source.label} ・ ${a.origin == 'manual' ? '個別DL' : '一括DL'} ・ ${formatBytes(a.sizeBytes)} ・ ${formatDate(a.downloadedAt)}',
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                  trailing: IconButton(
                    icon: TechMekuIcon(I.trash, color: c.warn, size: 20),
                    onPressed: () async {
                      if (await confirmDialog(context, title: '削除しますか？', body: a.title, ok: '削除', danger: true, icon: I.trash)) {
                        await StockRepo.instance.delete(a);
                      }
                    },
                  ),
                  onTap: () => ArticleActions.open(context, FeedItem.stock(a)),
                ),
              if (cache.isNotEmpty) const SectionTitle('キャッシュ（タイトルとURLのみ・24時間で削除）'),
              for (final e in cache)
                ListTile(
                  leading: const TechMekuIcon(I.external_link, muted: true),
                  title: Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Row(children: [
                    Badge2('キャッシュ', color: c.muted),
                    Text('  ${e.source.label} ・ ${remaining(e.expiresAt).replaceFirst('あと', '残り')}', style: TextStyle(fontSize: 12, color: c.muted)),
                  ]),
                  trailing: IconButton(icon: TechMekuIcon(I.trash, color: c.warn, size: 20), onPressed: () => StockRepo.instance.deleteCache(e.id)),
                  // 開くとオンライン取得して全文表示。「DL」でストックに戻せる
                  onTap: () => ArticleActions.open(context, FeedItem(summary: StockRepo.summaryFromUrl(e.source, e.url, e.title))),
                ),
            ]);
          },
        ),
      ),
    );
  }
}
