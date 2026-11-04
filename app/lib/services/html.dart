import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;
import 'package:markdown/markdown.dart' as md;

import '../core/theme.dart';

const _dropTags = {'script', 'style', 'iframe', 'object', 'embed', 'form', 'input', 'button', 'textarea', 'select', 'link', 'meta', 'base', 'frame', 'frameset', 'noscript', 'template', 'svg'};

/// 本文 HTML をサニタイズする（<script>・on* 属性・javascript: URL を除去）
String sanitizeHtml(String html, {String Function(String src)? rewriteImg}) {
  final frag = parser.parseFragment(html);
  void walk(dom.Node node) {
    for (final child in node.nodes.toList()) {
      if (child is dom.Element) {
        final name = child.localName ?? '';
        if (_dropTags.contains(name)) {
          child.remove();
          continue;
        }
        for (final attr in child.attributes.keys.toList()) {
          final a = attr.toString().toLowerCase();
          final v = child.attributes[attr]!.trim().toLowerCase();
          if (a.startsWith('on') || a == 'style' && v.contains('expression') || a == 'srcset') {
            child.attributes.remove(attr);
          } else if ((a == 'href' || a == 'src' || a == 'xlink:href' || a == 'action') && (v.startsWith('javascript:') || v.startsWith('vbscript:') || v.startsWith('data:text'))) {
            child.attributes.remove(attr);
          }
        }
        if (name == 'img') {
          final src = child.attributes['src'] ?? child.attributes['data-src'];
          if (src != null && rewriteImg != null) child.attributes['src'] = rewriteImg(src);
          child.attributes.remove('data-src');
          child.attributes['loading'] = 'lazy';
        }
        walk(child);
      }
    }
  }

  walk(frag);
  return frag.outerHtml;
}

/// 投稿の Markdown を HTML にする。`![](attachment:N)` は画像 URL に置き換える（設計判断 #2）
String markdownToHtml(String body, List<String> imageUrls) {
  final replaced = body.replaceAllMapped(RegExp(r'attachment:(\d)'), (m) {
    final i = int.parse(m.group(1)!) - 1;
    return i >= 0 && i < imageUrls.length ? imageUrls[i] : '';
  });
  return sanitizeHtml(md.markdownToHtml(replaced, extensionSet: md.ExtensionSet.gitHubWeb));
}

String _hex(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// 全文表示のテンプレート（同梱 CSS。JavaScript は使わない）
String articleTemplate({
  required String title,
  required String bodyHtml,
  required TmColors c,
  required double textScale,
  String? meta,
  String? notice,
}) {
  final bg = _hex(c.bg.toARGB32());
  final ink = _hex(c.ink.toARGB32());
  final muted = _hex(c.muted.toARGB32());
  final card = _hex(c.card.toARGB32());
  final line = _hex(c.line.toARGB32());
  final accent = _hex(c.active.toARGB32());
  final warn = _hex(c.warn.toARGB32());
  String esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  return '''<!doctype html><html lang="ja"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src * data: file:; style-src 'unsafe-inline'">
<style>
html{-webkit-text-size-adjust:none}
body{margin:0;padding:16px 16px 96px;background:$bg;color:$ink;font:${(16 * textScale).toStringAsFixed(1)}px/1.8 -apple-system,"Noto Sans JP",sans-serif;word-wrap:break-word;overflow-wrap:anywhere}
h1.title{font-size:1.4em;line-height:1.4;margin:0 0 8px}
.meta{color:$muted;font-size:.8em;margin-bottom:16px}
.notice{border:1px solid $warn;color:$warn;border-radius:8px;padding:8px 12px;font-size:.85em;margin-bottom:16px}
h1,h2,h3,h4{line-height:1.4;margin:1.6em 0 .6em}
h2{font-size:1.25em;border-bottom:1px solid $line;padding-bottom:4px}
h3{font-size:1.1em}
a{color:$accent}
img,video{max-width:100%;height:auto;border-radius:6px}
pre{background:$card;border:1px solid $line;border-radius:8px;padding:12px;overflow-x:auto;font-size:.85em;line-height:1.5}
code{font-family:ui-monospace,Menlo,monospace;background:$card;border-radius:4px;padding:.1em .3em;font-size:.9em}
pre code{background:none;padding:0}
blockquote{margin:1em 0;padding:.2em 1em;border-left:4px solid $line;color:$muted}
table{border-collapse:collapse;display:block;overflow-x:auto}
th,td{border:1px solid $line;padding:6px 10px}
hr{border:none;border-top:1px solid $line}
.code-frame .code-lang{font-size:.75em;color:$muted}
</style></head><body>
<h1 class="title">${esc(title)}</h1>
${meta != null ? '<div class="meta">${esc(meta)}</div>' : ''}
${notice != null ? '<div class="notice">${esc(notice)}</div>' : ''}
$bodyHtml
</body></html>''';
}
