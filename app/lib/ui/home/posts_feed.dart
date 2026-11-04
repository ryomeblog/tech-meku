import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/net.dart';
import '../../core/techmeku_icon.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../models/models.dart';
import '../../services/api.dart';
import '../../services/auth.dart';
import '../common/actions.dart';
import '../common/widgets.dart';
import '../posts/editor_page.dart';

/// ホーム：みんなの投稿（S03）
class PostsFeed extends StatefulWidget {
  const PostsFeed({super.key});

  @override
  State<PostsFeed> createState() => _PostsFeedState();
}

class _PostsFeedState extends State<PostsFeed> with AutomaticKeepAliveClientMixin {
  final _page = PageController();
  List<Post>? _posts;
  String? _error;
  int _activeCount = 0;
  Timer? _tick;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    AuthService.instance.addListener(_load);
    NetStatus.instance.addListener(_onNet);
    // 残り時間の表示更新。期限を過ぎた投稿は表示から消す
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted || _posts == null) return;
      setState(() => _posts!.removeWhere((p) => p.expiresAt <= nowMs()));
    });
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_load);
    NetStatus.instance.removeListener(_onNet);
    _tick?.cancel();
    _page.dispose();
    super.dispose();
  }

  void _onNet() {
    if (NetStatus.instance.online && _posts == null) _load();
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (!NetStatus.instance.online) return;
    try {
      final list = await Api.instance.posts();
      final st = await Api.instance.status();
      if (!mounted) return;
      setState(() {
        _posts = list;
        _activeCount = st['activeCount'] as int? ?? list.length;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _mineMenu(Post p) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const TechMekuIcon(I.edit), title: const Text('編集'), onTap: () => Navigator.pop(ctx, 'edit')),
          ListTile(leading: TechMekuIcon(I.trash, color: TmColors.of(ctx).warn), title: const Text('削除'), onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
    if (!mounted || v == null) return;
    if (v == 'edit') {
      final full = await Api.instance.post(p.id);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditorPage(post: full)));
      _load();
    } else if (await confirmDialog(context, title: '投稿を削除しますか？', body: 'この操作は取り消せません。', ok: '削除', danger: true, icon: I.trash)) {
      try {
        await Api.instance.deletePost(p.id);
        _load();
      } on ApiException catch (e) {
        if (mounted) showSnack(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = TmColors.of(context);
    if (!NetStatus.instance.online) {
      return const StatusCard(icon: I.cloud_off, title: 'オフラインです', body: 'DL した投稿はストックで読めます');
    }
    final posts = _posts;
    return Column(children: [
      Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('公開中 $_activeCount/100', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text('投稿は24時間で消えます。いいね・初回コメントで延長（最大7日）', style: TextStyle(fontSize: 11, color: c.muted)),
            ]),
          ),
          IconButton(icon: const TechMekuIcon(I.refresh, size: 22), tooltip: '更新', onPressed: _load),
        ]),
      ),
      Expanded(
        child: _error != null && posts == null
            ? StatusCard(icon: I.cloud_off, title: _error!, action: OutlinedButton(onPressed: _load, child: const Text('再試行')))
            : posts == null
                ? const Center(child: CircularProgressIndicator())
                : posts.isEmpty
                    ? StatusCard(
                        icon: I.file_text,
                        title: 'まだ投稿はありません',
                        body: '下の「＋新規投稿」から投稿できます',
                        action: OutlinedButton.icon(onPressed: _load, icon: const TechMekuIcon(I.refresh, size: 18), label: const Text('更新')),
                      )
                    : PageView.builder(
                        controller: _page,
                        scrollDirection: Axis.vertical,
                        itemCount: posts.length,
                        itemBuilder: (context, i) {
                          final p = posts[i];
                          final item = FeedItem.post(p);
                          return StatefulBuilder(builder: (ctx, set) {
                            final actions = ArticleActions.rail(ctx, item, refresh: () => set(() {}), onReported: () => setState(() => posts.remove(p)));
                            if (p.isMine) actions.add(RailAction(I.more, 'メニュー', () => _mineMenu(p)));
                            return ArticleCard(
                              key: ValueKey(p.id),
                              summary: item.summary,
                              badges: [
                                Badge2(remaining(p.expiresAt), icon: I.clock, color: c.active),
                                if (p.isMine) const Badge2('自分の投稿', icon: I.user),
                                if (p.edited) const Badge2('編集済み'),
                              ],
                              footer: Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text('いいね・初回コメントで延長（最大7日）', style: TextStyle(fontSize: 11, color: c.muted)),
                              ),
                              onOpen: () async {
                                await ArticleActions.open(context, item);
                                if (mounted) setState(() {});
                              },
                              rail: ActionRail(actions),
                            );
                          });
                        },
                      ),
      ),
    ]);
  }
}
