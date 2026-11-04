import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/net.dart';
import '../../core/settings.dart';
import '../../core/techmeku_icon.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../models/models.dart';
import '../../services/api.dart';
import '../../services/html.dart';
import '../../services/stock.dart';
import '../common/actions.dart';
import '../common/widgets.dart';

/// 記事全文（S04）
class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.item});
  final FeedItem item;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late final WebViewController _web;
  String? _error;
  bool _loading = true;
  bool _local = false;
  Post? _post;

  FeedItem get item => widget.item;

  @override
  void initState() {
    super.initState();
    _post = item.post;
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setNavigationDelegate(NavigationDelegate(onNavigationRequest: (req) {
        final u = req.url;
        if (u.startsWith('http://') || u.startsWith('https://')) {
          launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
          return NavigationDecision.prevent;
        }
        return u.startsWith('about:') || u.startsWith('data:') || u.startsWith('file:') ? NavigationDecision.navigate : NavigationDecision.prevent;
      }));
    final p = _web.platform;
    if (p is AndroidWebViewController) {
      p.setAllowFileAccess(true);
      p.setMediaPlaybackRequiresUserGesture(true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final c = TmColors.of(context);
    _web.setBackgroundColor(c.bg);
    final scale = Settings.instance.textScale;
    final s = item.summary;
    try {
      final repo = StockRepo.instance;
      final stock = item.stock != null ? await repo.byId(item.stock!.id) : await repo.byKey(s.source, s.sourceKey);
      if (stock != null) {
        // ストック：保存済みの本文をローカルで表示
        _local = true;
        await repo.markRead(stock.id);
        final body = await repo.readBody(stock);
        final html = articleTemplate(
          title: stock.title,
          bodyHtml: body,
          c: c,
          textScale: scale,
          meta: _meta(stock.source, stock.author, stock.publishedAt),
          notice: stock.isPaidPartial ? '有料記事（無料部分のみ）' : (stock.source == SourceType.app && (stock.appExpiresAt ?? 0) < nowMs() ? '公開終了（端末に保存したもの）' : null),
        );
        await _web.loadHtmlString(html, baseUrl: 'file://${repo.absDir(stock)}/');
      } else if (s.source == SourceType.app) {
        if (!NetStatus.instance.online) throw 'オフラインです。DL した投稿はストックで読めます';
        var post = _post;
        if (post == null || post.body == null) post = await Api.instance.post(s.sourceKey);
        _post = post;
        final html = markdownToHtml(post.body ?? '', post.images.map(Api.instance.imageUrl).toList());
        await _web.loadHtmlString(articleTemplate(
          title: post.title,
          bodyHtml: html,
          c: c,
          textScale: scale,
          meta: '${post.authorName} ・ ${relativeTime(post.createdAt)}${post.edited ? '（編集済み）' : ''} ・ ${remaining(post.expiresAt)}',
        ));
      } else {
        // おすすめ・キャッシュ・いいね（Web）：その場で取得して表示。保存はしない
        if (!NetStatus.instance.online) throw 'オフラインです。ストックをご覧ください';
        final content = await fetchOnline(s);
        await _web.loadHtmlString(articleTemplate(
          title: s.title,
          bodyHtml: content.html,
          c: c,
          textScale: scale,
          meta: _meta(s.source, s.author, s.publishedAt),
          notice: content.isPaidPartial ? '有料記事（無料部分のみ）' : null,
        ));
      }
    } on ApiException catch (e) {
      _error = e.code == 'POST_GONE' ? 'この投稿は公開終了しました' : e.message;
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  String _meta(SourceType src, String? author, int? at) =>
      [src.label, ?author, if (at != null) formatDate(at), if (_local) '端末に保存済み'].join(' ・ ');

  Future<void> _textSize() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('文字サイズ', style: TextStyle(fontWeight: FontWeight.bold)),
              Slider(
                value: Settings.instance.textScale,
                min: 0.8,
                max: 1.6,
                divisions: 8,
                label: '${(Settings.instance.textScale * 100).round()}%',
                onChanged: (v) => set(() => Settings.instance.setTextScale(v)),
              ),
            ]),
          ),
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = TmColors.of(context);
    final post = _post;
    void refresh() => setState(() {});
    final actions = <RailAction>[
      RailAction(ArticleActions.liked(item) ? I.heart_filled : I.heart, 'いいね', () => ArticleActions.toggleLike(context, item, onChanged: refresh), active: ArticleActions.liked(item)),
      if (post != null) RailAction(I.comment, 'コメント', () => ArticleActions.comments(context, post, onChanged: refresh)),
      RailAction(ArticleActions.saved(item) ? I.check_circle : I.download, ArticleActions.saved(item) ? '保存済' : 'DL',
          () => ArticleActions.download(context, item, onChanged: refresh), active: ArticleActions.saved(item)),
      RailAction(I.share, '共有', () => ArticleActions.share(item)),
      if (post == null) RailAction(I.external_link, '元記事', () => ArticleActions.openOriginal(context, item)),
    ];
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const TechMekuIcon(I.back), onPressed: () => Navigator.pop(context), tooltip: '戻る'),
        title: Text(item.summary.source.label, style: const TextStyle(fontSize: 15)),
        actions: [IconButton(icon: const TechMekuIcon(I.sliders), tooltip: '表示設定', onPressed: _textSize)],
      ),
      body: _error != null
          ? StatusCard(
              icon: I.cloud_off,
              title: _error!,
              action: OutlinedButton.icon(onPressed: _load, icon: const TechMekuIcon(I.refresh, size: 18), label: const Text('再試行')),
            )
          : Stack(children: [
              WebViewWidget(controller: _web),
              if (_loading) LinearProgressIndicator(color: c.active),
            ]),
      bottomNavigationBar: SafeArea(
        child: Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
          height: 64,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (final a in actions)
              InkWell(
                onTap: a.onTap,
                child: SizedBox(
                  width: 64,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    TechMekuIcon(a.icon, active: a.active, size: 22),
                    const SizedBox(height: 2),
                    Text(a.label, style: TextStyle(fontSize: 10, color: a.active ? c.active : c.ink)),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
