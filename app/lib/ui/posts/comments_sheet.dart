import 'package:flutter/material.dart';

import '../../core/net.dart';
import '../../core/techmeku_icon.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../models/models.dart';
import '../../services/api.dart';
import '../common/actions.dart';
import '../common/widgets.dart';

/// コメントシート（S12）。1 投稿 50 件まで、1 件 200 字まで
class CommentsSheet extends StatefulWidget {
  const CommentsSheet({super.key, required this.post});
  final Post post;

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _ctl = TextEditingController();
  List<Comment>? _comments;
  String? _error;
  bool _sending = false;

  Post get post => widget.post;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (list, count) = await Api.instance.comments(post.id);
      post.commentCount = count;
      setState(() {
        _comments = list;
        _error = null;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.code == 'POST_GONE' ? 'この投稿は公開終了しました' : e.message);
    }
  }

  Future<void> _send() async {
    final text = _ctl.text.trim();
    if (text.isEmpty) return;
    if (!NetStatus.instance.online) {
      showSnack(context, 'オフラインのため、コメントできません');
      return;
    }
    if (!await ArticleActions.ensureLogin(context, reason: 'コメントにはログインが必要です')) return;
    setState(() => _sending = true);
    try {
      final r = await Api.instance.addComment(post.id, text);
      post
        ..commentCount = r['commentCount'] as int
        ..expiresAt = r['expiresAt'] as int;
      _ctl.clear();
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        showSnack(context, switch (e.code) {
          'COMMENT_LIMIT' => 'この投稿はコメント上限に達しました',
          'POST_GONE' => 'この投稿は公開終了しました',
          _ => e.message,
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(Comment c) async {
    if (!await confirmDialog(context, title: 'コメントを削除しますか？', ok: '削除', danger: true, icon: I.trash)) return;
    try {
      await Api.instance.deleteComment(c.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TmColors.of(context);
    final comments = _comments;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const TechMekuIcon(I.comment, size: 20),
              const SizedBox(width: 8),
              Text('コメント ${post.commentCount}/50', style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(icon: const TechMekuIcon(I.close), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('初めてのコメントで公開期間が延びます（最大7日）', style: TextStyle(fontSize: 12, color: c.muted)),
          ),
          const Divider(),
          Expanded(
            child: _error != null
                ? Center(child: Text(_error!))
                : comments == null
                    ? const Center(child: CircularProgressIndicator())
                    : comments.isEmpty
                        ? Center(child: Text('まだコメントはありません', style: TextStyle(color: c.muted)))
                        : ListView.separated(
                            itemCount: comments.length,
                            separatorBuilder: (_, _) => Divider(height: 1, color: c.line),
                            itemBuilder: (_, i) {
                              final cm = comments[i];
                              return ListTile(
                                title: Text(cm.body),
                                subtitle: Text('${cm.authorName} ・ ${relativeTime(cm.createdAt)}', style: TextStyle(fontSize: 12, color: c.muted)),
                                trailing: PopupMenuButton<String>(
                                  icon: const TechMekuIcon(I.more, size: 20),
                                  onSelected: (v) => v == 'delete'
                                      ? _delete(cm)
                                      : ArticleActions.report(context, 'comment', cm.id, onReported: _load),
                                  itemBuilder: (_) => [
                                    if (cm.canDelete) const PopupMenuItem(value: 'delete', child: Text('削除')),
                                    if (!cm.isMine) const PopupMenuItem(value: 'report', child: Text('通報')),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _ctl,
                    maxLength: 200,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(hintText: 'コメントを書く（200字まで）', border: OutlineInputBorder(), isDense: true, counterText: ''),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  onPressed: _sending ? null : _send,
                  icon: TechMekuIcon(I.send, color: c.bg, size: 20),
                  tooltip: '送信',
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
