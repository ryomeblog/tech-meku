import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/net.dart';
import '../../core/settings.dart';
import '../../core/techmeku_icon.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../models/models.dart';
import '../../services/stock.dart';
import '../../services/url_save.dart';
import '../../sources/article_source.dart';
import '../common/actions.dart';
import '../common/widgets.dart';

enum _Phase { input, loading, preview, saving, done, error }

/// URLから保存シート（S17）
class UrlSaveSheet extends StatefulWidget {
  const UrlSaveSheet({super.key, this.initialText});
  final String? initialText;

  static Future<void> show(BuildContext context, {String? initialText}) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => UrlSaveSheet(initialText: initialText),
      );

  @override
  State<UrlSaveSheet> createState() => _UrlSaveSheetState();
}

class _UrlSaveSheetState extends State<UrlSaveSheet> {
  final _ctl = TextEditingController();
  Timer? _debounce;
  _Phase _phase = _Phase.input;
  String? _error;
  ArticleRef? _ref;
  ArticleSummary? _summary;
  StockArticle? _saved; // 保存済み（既存）または保存した記事
  bool _wasSaved = false;
  int _req = 0;

  @override
  void initState() {
    super.initState();
    final t = widget.initialText;
    if (t != null && t.isNotEmpty) {
      _ctl.text = extractFirstUrl(t) ?? t;
      WidgetsBinding.instance.addPostFrameCallback((_) => _onChanged(_ctl.text, immediate: true));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _onChanged(String text, {bool immediate = false}) {
    _debounce?.cancel();
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _phase = _Phase.input;
        _error = null;
        _ref = null;
        _summary = null;
      });
      return;
    }
    final ref = UrlSave.resolve(trimmed);
    if (ref == null) {
      setState(() {
        _ref = null;
        _summary = null;
        _phase = _Phase.error;
        _error = '対応していないURLです';
      });
      return;
    }
    setState(() {
      _ref = ref;
      _error = null;
      _phase = _Phase.loading;
    });
    if (immediate) {
      _load(ref);
    } else {
      _debounce = Timer(const Duration(milliseconds: 400), () => _load(ref));
    }
  }

  Future<void> _load(ArticleRef ref) async {
    if (!NetStatus.instance.online) {
      setState(() {
        _phase = _Phase.error;
        _error = 'オフラインです。接続すると保存できます';
      });
      return;
    }
    final req = ++_req;
    try {
      final (s, existing) = await UrlSave.preview(ref);
      // 一括DL由来で保存済みなら、個別DL（manual）に切り替えて入れ替えから守る（端末内の処理だけ）
      final saved = existing != null && existing.origin != 'manual' ? await UrlSave.save(s) : existing;
      if (!mounted || req != _req) return;
      setState(() {
        _summary = s;
        _saved = saved;
        _wasSaved = saved != null;
        _phase = _Phase.preview;
      });
    } on SourceException catch (e) {
      if (!mounted || req != _req) return;
      setState(() {
        _phase = _Phase.error;
        _error = e.notFound ? '記事が見つかりません（削除・非公開の可能性）' : e.message;
      });
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      if (mounted) showSnack(context, 'クリップボードが空です');
      return;
    }
    _ctl.text = extractFirstUrl(text) ?? text;
    _onChanged(_ctl.text, immediate: true);
  }

  Future<void> _save() async {
    final s = _summary;
    if (s == null) return;
    if (!NetStatus.instance.online) {
      setState(() {
        _phase = _Phase.error;
        _error = 'オフラインです。接続すると保存できます';
      });
      return;
    }
    setState(() => _phase = _Phase.saving);
    try {
      final a = await UrlSave.save(s);
      if (!mounted) return;
      setState(() {
        _saved = a;
        _phase = _Phase.done;
      });
      if (await _overLimit() && mounted) {
        await infoDialog(context, title: '保存容量の上限を超えています', body: '設定の「DLしたもの」から不要な記事を削除するか、容量上限を変更してください。', icon: I.warning, warn: true);
      }
    } on SourceException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = e.notFound ? '記事が見つかりません（削除・非公開の可能性）' : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = '保存できませんでした';
      });
    }
  }

  Future<bool> _overLimit() async {
    final bytes = await StockRepo.instance.totalBytes();
    return bytes > Settings.instance.storageLimitBytes;
  }

  void _again() {
    _ctl.clear();
    setState(() {
      _phase = _Phase.input;
      _ref = null;
      _summary = null;
      _saved = null;
      _error = null;
    });
  }

  Future<void> _read() async {
    final a = _saved;
    if (a == null) return;
    final nav = Navigator.of(context);
    nav.pop();
    await ArticleActions.open(nav.context, FeedItem.stock(a));
  }

  @override
  Widget build(BuildContext context) {
    final c = TmColors.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: _phase == _Phase.done ? _doneView(c) : _formView(c),
        ),
      ),
    );
  }

  Widget _header() => Row(children: [
        const TechMekuIcon(I.plus, size: 20),
        const SizedBox(width: 8),
        const Text('URLから保存', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const Spacer(),
        IconButton(icon: const TechMekuIcon(I.close), tooltip: '閉じる', onPressed: () => Navigator.pop(context)),
      ]);

  Widget _formView(TmColors c) {
    final isError = _phase == _Phase.error;
    final s = _summary;
    final alreadySaved = _phase == _Phase.preview && _wasSaved;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header(),
      TextField(
        controller: _ctl,
        autofocus: widget.initialText == null,
        keyboardType: TextInputType.url,
        minLines: 1,
        maxLines: 3,
        onChanged: _onChanged,
        decoration: InputDecoration(
          hintText: '記事のURLを入力（例：https://zenn.dev/…/articles/…）',
          border: const OutlineInputBorder(),
          enabledBorder: isError ? OutlineInputBorder(borderSide: BorderSide(color: c.warn)) : null,
          focusedBorder: isError ? OutlineInputBorder(borderSide: BorderSide(color: c.warn, width: 2)) : null,
          isDense: true,
          suffixIcon: _ctl.text.isEmpty ? null : IconButton(icon: const TechMekuIcon(I.close, size: 18), tooltip: 'クリア', onPressed: _again),
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        OutlinedButton(onPressed: _paste, child: const Text('貼り付け')),
        const SizedBox(width: 10),
        if (_ref != null && !isError) Badge2('${_ref!.source.label} の記事', icon: I.check_circle, color: c.active),
      ]),
      if (isError) ...[
        const SizedBox(height: 8),
        Row(children: [
          TechMekuIcon(I.warning, size: 16, color: c.warn),
          const SizedBox(width: 6),
          Expanded(child: Text(_error ?? '', style: TextStyle(color: c.warn))),
        ]),
      ],
      const SizedBox(height: 12),
      if (_phase == _Phase.loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      if (s != null && (_phase == _Phase.preview || _phase == _Phase.saving)) _preview(c, s, alreadySaved),
      if (_phase == _Phase.input || isError) _sites(c),
      const SizedBox(height: 12),
      if (alreadySaved)
        FilledButton.icon(
          onPressed: _read,
          icon: TechMekuIcon(I.book_open, size: 18, color: c.bg),
          label: const Text('読む'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        )
      else
        FilledButton.icon(
          onPressed: _phase == _Phase.preview ? _save : null,
          icon: _phase == _Phase.saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : TechMekuIcon(I.download, size: 18, color: c.bg),
          label: Text(_phase == _Phase.saving ? '保存しています…' : 'ストックに保存'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      if (_phase == _Phase.preview && !alreadySaved) ...[
        const SizedBox(height: 6),
        Text('本文と画像を端末に保存します。個別DLと同じ扱いで、一括DLの入れ替えでは消えません。', style: TextStyle(fontSize: 12, color: c.muted)),
      ],
    ]);
  }

  Widget _preview(TmColors c, ArticleSummary s, bool alreadySaved) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 56,
            height: 56,
            child: s.thumbnailUrl != null
                ? Image.network(s.thumbnailUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox())
                : Center(child: s.emoji != null ? Text(s.emoji!, style: const TextStyle(fontSize: 30)) : const TechMekuIcon(I.file_text, muted: true)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, height: 1.4)),
            const SizedBox(height: 4),
            Text(
              [s.source.label, ?s.author, if (s.publishedAt != null) formatDate(s.publishedAt!), if (s.likes > 0) '♥ ${s.likes}'].join(' ・ '),
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (alreadySaved) Badge2('保存済み', icon: I.check_circle, color: c.active),
              if (s.isPaidPartial) Badge2('有料記事（無料部分のみ）', color: c.warn),
              for (final t in s.tags.take(3)) Badge2('#$t'),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _sites(TmColors c) {
    Widget line(String site, String pattern) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            SizedBox(width: 80, child: Text(site, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
            Expanded(child: Text(pattern, style: TextStyle(fontSize: 12, color: c.muted))),
          ]),
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: c.line), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const TechMekuIcon(I.info, size: 16), const SizedBox(width: 6), const Text('対応しているURL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))]),
        const SizedBox(height: 4),
        line('Qiita', 'qiita.com/…/items/…'),
        line('Zenn', 'zenn.dev/…/articles/…'),
        line('note', 'note.com/…/n/…'),
        line('GIGAZINE', 'gigazine.net/news/…'),
      ]),
    );
  }

  Widget _doneView(TmColors c) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _header(),
      const SizedBox(height: 8),
      TechMekuIcon(I.check_circle, size: 48, active: true),
      const SizedBox(height: 10),
      const Text('ストックに保存しました', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text(_saved?.title ?? '', textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.muted)),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _read,
        icon: TechMekuIcon(I.book_open, size: 18, color: c.bg),
        label: const Text('読む'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _again,
        icon: const TechMekuIcon(I.plus, size: 18),
        label: const Text('続けて追加'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      ),
    ]);
  }
}
