import 'package:flutter/material.dart';

import '../../core/net.dart';
import '../../core/settings.dart';
import '../../core/techmeku_icon.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../models/models.dart';
import '../../services/api.dart';
import '../../services/auth.dart';
import '../../services/stock.dart';
import '../auth/login_page.dart';
import '../common/actions.dart';
import '../common/widgets.dart';
import '../tags/tag_select_page.dart';

/// プロフィール：ストック（S08）／いいね（S10）
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = TmColors.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: SafeArea(
          child: Column(children: [
            ListenableBuilder(
              listenable: Listenable.merge([AuthService.instance, Settings.instance]),
              builder: (context, _) {
                final auth = AuthService.instance;
                final tags = Settings.instance.interestTags;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    CircleAvatar(radius: 26, backgroundColor: c.card, child: const TechMekuIcon(I.user, size: 26)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(auth.loggedIn ? (auth.nickname ?? '') : '未ログイン', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Wrap(spacing: 4, runSpacing: 4, children: [
                          if (tags.isEmpty) Text('興味タグ未設定', style: TextStyle(color: c.muted, fontSize: 12)),
                          for (final t in tags) Text('#$t', style: TextStyle(color: c.active, fontSize: 12)),
                        ]),
                      ]),
                    ),
                    Column(children: [
                      if (!auth.loggedIn)
                        FilledButton(
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginPage())),
                          child: const Text('ログイン'),
                        ),
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TagSelectPage())),
                        icon: const TechMekuIcon(I.edit, size: 16),
                        label: const Text('タグ'),
                      ),
                    ]),
                  ]),
                );
              },
            ),
            TabBar(
              labelColor: c.active,
              unselectedLabelColor: c.ink,
              indicatorColor: c.active,
              dividerColor: c.line,
              tabs: const [
                Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [TechMekuIcon(I.library, size: 18), Text(' ストック')])),
                Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [TechMekuIcon(I.heart_filled, size: 18), Text(' いいね')])),
              ],
            ),
            const Expanded(child: TabBarView(children: [_MyStock(), _Likes()])),
          ]),
        ),
      ),
    );
  }
}

/// 自分で保存した記事（個別DL・投稿記事のDL）
class _MyStock extends StatelessWidget {
  const _MyStock();

  @override
  Widget build(BuildContext context) {
    final c = TmColors.of(context);
    return ListenableBuilder(
      listenable: StockRepo.instance,
      builder: (context, _) => FutureBuilder<List<StockArticle>>(
        future: StockRepo.instance.feed(origin: 'manual'),
        builder: (context, snap) {
          final list = snap.data;
          if (list == null) return const Center(child: CircularProgressIndicator());
          if (list.isEmpty) return const EmptyState(icon: I.bookmark, text: 'カードの「DL」で保存した記事がここに並びます');
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: c.line),
            itemBuilder: (_, i) {
              final a = list[i];
              return ListTile(
                leading: TechMekuIcon(a.source == SourceType.app ? I.file_text : I.bookmark_filled, active: true),
                title: Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('${a.source.label} ・ ${formatDate(a.downloadedAt)} に保存${a.source == SourceType.app && (a.appExpiresAt ?? 0) < nowMs() ? ' ・ 公開終了' : ''}',
                    style: TextStyle(fontSize: 12, color: c.muted)),
                trailing: const TechMekuIcon(I.chevron_right, muted: true),
                onTap: () => ArticleActions.open(context, FeedItem.stock(a)),
              );
            },
          );
        },
      ),
    );
  }
}

enum _Ref { local, web, live, gone, unknown }

/// いいね一覧。参照先は表示時に毎回判定（6.4）
class _Likes extends StatefulWidget {
  const _Likes();

  @override
  State<_Likes> createState() => _LikesState();
}

class _LikesState extends State<_Likes> {
  final Map<String, Future<(_Ref, Post?)>> _postChecks = {};

  Future<(_Ref, StockArticle?, Post?)> _resolve(LikedItem l) async {
    final stock = await StockRepo.instance.byKey(l.source, l.sourceKey);
    if (stock != null) return (_Ref.local, stock, null);
    if (l.kind == 'external') return (_Ref.web, null, null);
    if (!NetStatus.instance.online) return (_Ref.unknown, null, null);
    final (ref, post) = await _postChecks.putIfAbsent(l.sourceKey, () async {
      try {
        return (_Ref.live, await Api.instance.post(l.sourceKey));
      } on ApiException catch (e) {
        return (e.code == 'POST_GONE' ? _Ref.gone : _Ref.unknown, null);
      }
    });
    return (ref, null, post);
  }

  @override
  Widget build(BuildContext context) {
    final c = TmColors.of(context);
    return ListenableBuilder(
      listenable: StockRepo.instance,
      builder: (context, _) => FutureBuilder<List<LikedItem>>(
        future: StockRepo.instance.likedItems(),
        builder: (context, snap) {
          final list = snap.data;
          if (list == null) return const Center(child: CircularProgressIndicator());
          if (list.isEmpty) return const EmptyState(icon: I.heart, text: 'いいねした記事・投稿がここに並びます');
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: c.line),
            itemBuilder: (_, i) {
              final l = list[i];
              return FutureBuilder<(_Ref, StockArticle?, Post?)>(
                future: _resolve(l),
                builder: (context, s) {
                  final (ref, stock, post) = s.data ?? (_Ref.unknown, null, null);
                  final (label, color, icon) = switch (ref) {
                    _Ref.local => ('端末に保存済み', c.ok, I.smartphone),
                    _Ref.web => ('Web', c.active, I.external_link),
                    _Ref.live => ('公開中', c.active, I.clock),
                    _Ref.gone => ('公開終了', c.muted, I.clock),
                    _Ref.unknown => (s.connectionState == ConnectionState.done ? 'オフライン' : '確認中', c.muted, I.info),
                  };
                  return ListTile(
                    leading: TechMekuIcon(l.kind == 'app_post' ? I.file_text : I.heart_filled, active: true),
                    title: Text(l.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Row(children: [
                      Badge2(label, color: color, icon: icon),
                      Text('  ${l.source.label}', style: TextStyle(fontSize: 12, color: c.muted)),
                    ]),
                    trailing: ref == _Ref.gone ? null : const TechMekuIcon(I.chevron_right, muted: true),
                    onTap: () {
                      switch (ref) {
                        case _Ref.local:
                          ArticleActions.open(context, FeedItem.stock(stock!));
                        case _Ref.web:
                          ArticleActions.open(context, FeedItem(summary: StockRepo.summaryFromUrl(l.source, l.url!, l.title)));
                        case _Ref.live:
                          ArticleActions.open(context, FeedItem.post(post!));
                        case _Ref.gone:
                          showSnack(context, 'この投稿は公開終了しました');
                        case _Ref.unknown:
                          showSnack(context, '接続すると開けます');
                      }
                    },
                    onLongPress: () async {
                      if (await confirmDialog(context, title: 'いいねを外しますか？', ok: '外す')) {
                        await StockRepo.instance.setLiked(ArticleSummary(source: l.source, sourceKey: l.sourceKey, url: l.url ?? '', title: l.title), false);
                      }
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
