import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/net.dart';
import '../../core/settings.dart';
import '../../models/models.dart';
import '../../services/api.dart';
import '../../services/auth.dart';
import '../../services/stock.dart';
import '../auth/login_page.dart';
import '../posts/comments_sheet.dart';
import '../reader/reader_page.dart';
import 'widgets.dart';

/// フィードに並ぶ 1 件（外部記事・ストック・投稿）
class FeedItem {
  FeedItem({required this.summary, this.stock, this.post});
  factory FeedItem.stock(StockArticle a) => FeedItem(summary: a.toSummary(), stock: a);
  factory FeedItem.post(Post p) => FeedItem(summary: p.toSummary(), post: p);

  final ArticleSummary summary;
  StockArticle? stock;
  final Post? post;

  bool get isPost => summary.source == SourceType.app;
}

/// 記事に対する操作（2.9）
class ArticleActions {
  static Future<void> open(BuildContext context, FeedItem item) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReaderPage(item: item)));
  }

  /// ログインが必要な操作の前に呼ぶ。ログインできたら true
  static Future<bool> ensureLogin(BuildContext context, {String reason = 'この操作にはログインが必要です'}) async {
    if (AuthService.instance.loggedIn) {
      if (AuthService.instance.banned) {
        await infoDialog(context, title: 'このアカウントは利用停止されています', icon: I.alert_octagon, warn: true);
        return false;
      }
      return true;
    }
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => LoginPage(reason: reason)));
    return ok == true;
  }

  static bool liked(FeedItem item) =>
      item.post?.likedByMe ?? StockRepo.instance.isLiked(item.summary.source, item.summary.sourceKey);

  static bool saved(FeedItem item) => StockRepo.instance.isStocked(item.summary.source, item.summary.sourceKey);

  /// いいね。外部記事は端末に保存、投稿はサーバーに記録＋公開延長
  static Future<void> toggleLike(BuildContext context, FeedItem item, {VoidCallback? onChanged}) async {
    final repo = StockRepo.instance;
    final s = item.summary;
    final post = item.post;
    if (post == null) {
      await repo.setLiked(s, !repo.isLiked(s.source, s.sourceKey));
      onChanged?.call();
      return;
    }
    if (post.isMine) {
      showSnack(context, '自分の投稿にはいいねできません');
      return;
    }
    if (!NetStatus.instance.online) {
      showSnack(context, 'オフラインのため、投稿へのいいねはできません'); // 設計判断 #4
      return;
    }
    if (!await ensureLogin(context, reason: '投稿へのいいねにはログインが必要です')) return;
    final on = !post.likedByMe;
    try {
      final r = await Api.instance.like(post.id, on);
      post
        ..likedByMe = on
        ..likeCount = r['likeCount'] as int
        ..expiresAt = r['expiresAt'] as int;
      await repo.setLiked(s, on);
      onChanged?.call();
    } on ApiException catch (e) {
      if (context.mounted) showSnack(context, e.code == 'POST_GONE' ? 'この投稿は公開終了しました' : e.message);
    }
  }

  /// 個別DL（origin=manual）
  static Future<void> download(BuildContext context, FeedItem item, {VoidCallback? onChanged}) async {
    if (saved(item)) {
      showSnack(context, '保存済みです');
      return;
    }
    if (!NetStatus.instance.online) {
      showSnack(context, 'オフラインのため DL できません');
      return;
    }
    showSnack(context, '保存しています…');
    try {
      Post? post = item.post;
      if (post != null && post.body == null) post = await Api.instance.post(post.id);
      final a = await StockRepo.instance.downloadManual(item.summary, post: post);
      item.stock = a;
      onChanged?.call();
      if (!context.mounted) return;
      showSnack(context, 'ストックに保存しました');
      final bytes = await StockRepo.instance.totalBytes();
      if (context.mounted && bytes > Settings.instance.storageLimitBytes) {
        await infoDialog(context, title: '保存容量の上限を超えています', body: '設定の「DLしたもの」から不要な記事を削除するか、容量上限を変更してください。', icon: I.warning, warn: true);
      }
    } catch (e) {
      if (context.mounted) showSnack(context, 'DL できませんでした：$e');
    }
  }

  /// 共有：外部記事は URL、投稿はタイトル＋冒頭のテキスト（設計判断 #1）
  static Future<void> share(FeedItem item) async {
    final s = item.summary;
    final text = item.isPost ? '${s.title}\n\n${s.summary ?? ''}\n\n— TechMeku の投稿より' : '${s.title}\n${s.url}';
    await SharePlus.instance.share(ShareParams(text: text, subject: s.title));
  }

  static Future<void> openOriginal(BuildContext context, FeedItem item) async {
    final url = item.summary.url;
    if (url.isEmpty) return;
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) showSnack(context, 'ブラウザを開けませんでした');
  }

  static Future<void> comments(BuildContext context, Post post, {VoidCallback? onChanged}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CommentsSheet(post: post),
    );
    onChanged?.call();
  }

  static Future<void> report(BuildContext context, String targetType, String targetId, {VoidCallback? onReported}) async {
    if (!await ensureLogin(context, reason: '通報にはログインが必要です')) return;
    if (!context.mounted) return;
    final reason = await pickReportReason(context);
    if (reason == null) return;
    try {
      await Api.instance.report(targetType, targetId, reason);
      onReported?.call();
      if (context.mounted) showSnack(context, '通報しました。ご協力ありがとうございます');
    } on ApiException catch (e) {
      if (context.mounted) showSnack(context, e.message);
    }
  }

  /// カード右側のアクション（2.9 の表）
  static List<RailAction> rail(BuildContext context, FeedItem item, {required VoidCallback refresh, VoidCallback? onReported, Widget? mine}) {
    final post = item.post;
    final isLiked = liked(item);
    final isSaved = saved(item);
    return [
      RailAction(isLiked ? I.heart_filled : I.heart, 'いいね', () => toggleLike(context, item, onChanged: refresh), active: isLiked, count: post?.likeCount),
      if (post != null) RailAction(I.comment, 'コメント', () => comments(context, post, onChanged: refresh), count: post.commentCount),
      RailAction(isSaved ? I.check_circle : I.download, isSaved ? '保存済' : 'DL', () => download(context, item, onChanged: refresh), active: isSaved),
      RailAction(I.share, '共有', () => share(item)),
      if (post == null) RailAction(I.external_link, '元記事', () => openOriginal(context, item)),
      if (post != null && !post.isMine) RailAction(I.flag, '通報', () => report(context, 'post', post.id, onReported: onReported)),
    ];
  }
}
