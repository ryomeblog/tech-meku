import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/config.dart';
import '../../core/settings.dart';
import '../../core/techmeku_icon.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../models/models.dart';
import '../../services/api.dart';
import '../../services/auth.dart';
import '../../services/html.dart';
import '../common/actions.dart';
import '../common/widgets.dart';

class _Img {
  _Img.existing(this.key) : bytes = null;
  _Img.picked(this.bytes) : key = null;
  final String? key;
  final Uint8List? bytes;
}

/// 投稿エディタ（S11）。post を渡すと編集
class EditorPage extends StatefulWidget {
  const EditorPage({super.key, this.post});
  final Post? post;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> with SingleTickerProviderStateMixin {
  late final _title = TextEditingController(text: widget.post?.title);
  late final _body = TextEditingController(text: widget.post?.body);
  final _tagInput = TextEditingController();
  late final List<String> _tags = [...?widget.post?.tags];
  late final List<_Img> _images = [...?widget.post?.images.map(_Img.existing)];
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _preview = WebViewController()..setJavaScriptMode(JavaScriptMode.disabled);
  bool _saving = false;
  int? _mine;
  int? _global;

  bool get _editing => widget.post != null;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (_tabs.index == 1) _renderPreview();
      setState(() {});
    });
    _preview.setNavigationDelegate(
      NavigationDelegate(onNavigationRequest: (r) => r.url.startsWith('http') ? NavigationDecision.prevent : NavigationDecision.navigate),
    );
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    try {
      final st = await Api.instance.status();
      await AuthService.instance.refresh();
      if (!mounted) return;
      setState(() {
        _global = st['activeCount'] as int?;
        _mine = AuthService.instance.activePostCount;
      });
    } catch (_) {}
  }

  void _renderPreview() {
    final c = TmColors.of(context);
    // 新しく選んだ画像はまだ URL がないので data URI で表示する
    final urls = _images.map((i) => i.key != null ? Api.instance.imageUrl(i.key!) : 'data:image/jpeg;base64,${_b64(i.bytes!)}').toList();
    _preview.setBackgroundColor(c.bg);
    _preview.loadHtmlString(
      articleTemplate(
        title: _title.text.isEmpty ? '（タイトル）' : _title.text,
        bodyHtml: markdownToHtml(_body.text, urls),
        c: c,
        textScale: Settings.instance.textScale,
      ),
    );
  }

  String _b64(Uint8List b) => base64Encode(b);

  Future<void> _pickImage() async {
    if (_images.length >= 3) {
      showSnack(context, '画像は3枚までです');
      return;
    }
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x == null) return;
    try {
      final bytes = await _compress(await x.readAsBytes());
      setState(() => _images.add(_Img.picked(bytes)));
      _insert('![](attachment:${_images.length})');
    } catch (e) {
      if (mounted) showSnack(context, '画像を読み込めませんでした');
    }
  }

  /// 長辺 1280px・JPEG・500KB 以下に圧縮（7.8）
  Future<Uint8List> _compress(Uint8List src) async {
    final img = await decodeImageFromList(src);
    final w = img.width, h = img.height;
    img.dispose();
    final scale = (w > h ? w : h) > 1280 ? 1280 / (w > h ? w : h) : 1.0;
    final tw = (w * scale).round(), th = (h * scale).round();
    for (var q = 85; q >= 30; q -= 10) {
      final out = await FlutterImageCompress.compressWithList(src, minWidth: tw, minHeight: th, quality: q, format: CompressFormat.jpeg);
      if (out.length <= 500 * 1024) return out;
    }
    throw '画像を 500KB 以下にできませんでした';
  }

  void _insert(String text) {
    final sel = _body.selection;
    final t = _body.text;
    final pos = sel.isValid ? sel.start : t.length;
    _body.text = '${t.substring(0, pos)}$text${t.substring(pos)}';
    _body.selection = TextSelection.collapsed(offset: pos + text.length);
  }

  void _addTag() {
    final t = _tagInput.text.trim().replaceAll('#', '');
    if (t.isEmpty) return;
    if (_tags.length >= 5) {
      showSnack(context, 'タグは5個までです');
      return;
    }
    if (!_tags.contains(t)) setState(() => _tags.add(t));
    _tagInput.clear();
  }

  Future<bool> _ensureTerms() async {
    if (Settings.instance.termsAccepted) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const TechMekuIcon(I.shield, size: 32, active: true),
        title: const Text('利用規約への同意', style: TextStyle(fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('投稿する前に利用規約に同意してください。スパム・誹謗中傷・性的・違法なコンテンツは禁止です。違反した投稿は削除され、アカウントが停止されることがあります。'),
            TextButton(
              onPressed: () => launchUrl(Uri.parse(AppConfig.termsUrl), mode: LaunchMode.externalApplication),
              child: const Text('利用規約を読む'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('同意する')),
        ],
      ),
    );
    if (ok == true) await Settings.instance.setTermsAccepted();
    return ok == true;
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty || body.isEmpty) {
      showSnack(context, 'タイトルと本文を入力してください');
      return;
    }
    if (title.runes.length > 100 || body.runes.length > 10000) {
      showSnack(context, '文字数の上限を超えています');
      return;
    }
    if (!await ArticleActions.ensureLogin(context, reason: '投稿にはログインが必要です')) return;
    if (!mounted || !await _ensureTerms()) return;
    setState(() => _saving = true);
    try {
      await Api.instance.savePost(
        id: widget.post?.id,
        title: title,
        body: body,
        tags: _tags,
        keepImages: [for (final i in _images) ?i.key],
        images: [
          for (final i in _images)
            if (i.bytes != null) UploadImage(i.bytes!, 'image/jpeg'),
        ],
      );
      await AuthService.instance.refresh();
      if (!mounted) return;
      showSnack(context, _editing ? '更新しました' : '投稿しました（24時間公開）');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      final next = e.nextFreeAt;
      switch (e.code) {
        case 'POST_LIMIT_USER':
          await infoDialog(context, title: '公開中の投稿が5件あります', body: next != null ? '最短で ${waitText(next)} 後に投稿できます' : null, icon: I.warning, warn: true);
        case 'POST_LIMIT_GLOBAL':
          await infoDialog(context, title: '現在満員です', body: next != null ? '次に空く予定：${formatClock(next)}' : '公開中の投稿が全体で100件に達しています', icon: I.warning, warn: true);
        case 'POST_GONE':
          await infoDialog(context, title: 'この投稿は公開終了しました', icon: I.clock);
        case 'BANNED':
          await infoDialog(context, title: 'このアカウントは利用停止されています', icon: I.alert_octagon, warn: true);
        default:
          showSnack(context, e.message);
      }
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TmColors.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const TechMekuIcon(I.close), onPressed: () => Navigator.pop(context)),
        title: Text(_editing ? '投稿を編集' : '新規投稿', style: const TextStyle(fontSize: 16)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : TechMekuIcon(I.check, size: 18, color: c.bg),
              label: Text(_editing ? '更新' : '投稿'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: c.card,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                _editing
                    ? '${remaining(widget.post!.expiresAt)}（編集しても期限は変わりません）'
                    : '自分 ${_mine ?? '-'}/5 ・ 全体 ${_global ?? '-'}/100 ・ 24時間で消えます（いいね・初回コメントで延長、最大7日）',
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextField(
                    controller: _title,
                    maxLength: 100,
                    decoration: const InputDecoration(labelText: 'タイトル', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final t in _tags) InputChip(label: Text('#$t'), onDeleted: () => setState(() => _tags.remove(t))),
                      if (_tags.length < 5)
                        SizedBox(
                          width: 160,
                          child: TextField(
                            controller: _tagInput,
                            decoration: InputDecoration(
                              hintText: 'タグを追加（${_tags.length}/5）',
                              isDense: true,
                              prefixIcon: const Padding(padding: EdgeInsets.all(10), child: TechMekuIcon(I.tag, size: 16)),
                            ),
                            onSubmitted: (_) => _addTag(),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TabBar(
                    controller: _tabs,
                    labelColor: c.active,
                    indicatorColor: c.active,
                    tabs: const [
                      Tab(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [TechMekuIcon(I.code, size: 16), Text(' 編集')]),
                      ),
                      Tab(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [TechMekuIcon(I.preview, size: 16), Text(' プレビュー')]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_tabs.index == 0)
                    TextField(
                      controller: _body,
                      maxLength: 10000,
                      minLines: 12,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(hintText: 'Markdown で書けます', border: OutlineInputBorder(), alignLabelWithHint: true),
                    )
                  else
                    SizedBox(height: 420, child: WebViewWidget(controller: _preview)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text('画像 ${_images.length}/3', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      TextButton.icon(onPressed: _pickImage, icon: const TechMekuIcon(I.upload, size: 18), label: const Text('画像を追加')),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < _images.length; i++)
                        Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 96,
                                height: 96,
                                child: _images[i].bytes != null
                                    ? Image.memory(_images[i].bytes!, fit: BoxFit.cover)
                                    : Image.network(
                                        Api.instance.imageUrl(_images[i].key!),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => const TechMekuIcon(I.image),
                                      ),
                              ),
                            ),
                            Positioned(left: 4, top: 4, child: Badge2('attachment:${i + 1}', color: Colors.white)),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: IconButton(
                                icon: const TechMekuIcon(I.close, size: 18, color: Colors.white),
                                onPressed: () => setState(() => _images.removeAt(i)),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('本文に ![](attachment:1) のように書くと、その位置に画像が入ります。画像は長辺1280px・500KB以下に圧縮されます。', style: TextStyle(fontSize: 12, color: c.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
