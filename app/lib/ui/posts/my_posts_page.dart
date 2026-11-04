import 'package:flutter/material.dart';

import '../../core/net.dart';
import '../../core/techmeku_icon.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../models/models.dart';
import '../../services/api.dart';
import '../../services/auth.dart';
import '../auth/login_page.dart';
import '../common/actions.dart';
import '../common/widgets.dart';
import 'editor_page.dart';

/// 自分の投稿（S09、ボトムナビ）
class MyPostsPage extends StatefulWidget {
  const MyPostsPage({super.key});

  @override
  State<MyPostsPage> createState() => _MyPostsPageState();
}

class _MyPostsPageState extends State<MyPostsPage> {
  List<Post>? _posts;
  int? _global;
  String? _error;

  @override
  void initState() {
    super.initState();
    AuthService.instance.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (!AuthService.instance.loggedIn || !NetStatus.instance.online) {
      if (mounted) setState(() {});
      return;
    }
    try {
      final list = await Api.instance.myPosts();
      final st = await Api.instance.status();
      if (!mounted) return;
      setState(() {
        _posts = list;
        _global = st['activeCount'] as int?;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _new() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditorPage()));
    _load();
  }

  Future<void> _edit(Post p) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditorPage(post: p)));
    _load();
  }

  Future<void> _delete(Post p) async {
    if (!await confirmDialog(context, title: '投稿を削除しますか？', body: 'この操作は取り消せません。', ok: '削除', danger: true, icon: I.trash)) return;
    try {
      await Api.instance.deletePost(p.id);
      await AuthService.instance.refresh();
      _load();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TmColors.of(context);
    final auth = AuthService.instance;
    Widget body;
    if (!auth.loggedIn) {
      body = StatusCard(
        icon: I.log_in,
        title: '投稿するにはログインが必要です',
        body: '投稿は24時間公開されます。いいね・初回コメントで延長（最大7日）',
        action: FilledButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginPage())),
          child: const Text('ログイン'),
        ),
      );
    } else if (!NetStatus.instance.online) {
      body = const StatusCard(icon: I.cloud_off, title: 'オフラインです');
    } else if (_error != null && _posts == null) {
      body = StatusCard(icon: I.warning, title: _error!, action: OutlinedButton(onPressed: _load, child: const Text('再試行')));
    } else if (_posts == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final posts = _posts!;
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('公開中 ${posts.length}/5 ・ 全体 ${_global ?? '-'}/100', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('期限を過ぎると枠が空きます', style: TextStyle(fontSize: 12, color: c.muted)),
                ]),
              ),
              FilledButton.icon(
                onPressed: posts.length >= 5 ? null : _new,
                icon: TechMekuIcon(I.plus_square, size: 18, color: c.bg),
                label: const Text('新しく投稿する'),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          if (posts.isEmpty) Padding(padding: const EdgeInsets.all(32), child: Center(child: Text('公開中の投稿はありません', style: TextStyle(color: c.muted)))),
          for (final p in posts)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => ArticleActions.open(context, FeedItem.post(p)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      Badge2(remaining(p.expiresAt), icon: I.clock, color: c.active),
                      Badge2('${p.likeCount}', icon: I.heart),
                      Badge2('${p.commentCount}', icon: I.comment),
                      if (p.edited) const Badge2('編集済み'),
                      if (p.hidden) Badge2('通報により非表示', color: c.warn, icon: I.alert_octagon),
                    ]),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton.icon(onPressed: () => _edit(p), icon: const TechMekuIcon(I.edit, size: 16), label: const Text('編集')),
                      TextButton.icon(onPressed: () => _delete(p), icon: TechMekuIcon(I.trash, size: 16, color: c.warn), label: Text('削除', style: TextStyle(color: c.warn))),
                    ]),
                  ]),
                ),
              ),
            ),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Row(children: [TechMekuIcon(I.file_text, size: 20), SizedBox(width: 8), Text('自分の投稿', style: TextStyle(fontSize: 17))])),
      body: body,
    );
  }
}
