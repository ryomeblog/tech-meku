import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/techmeku_icon.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../models/models.dart';

typedef I = TechMekuIconName;

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
}

Future<bool> confirmDialog(BuildContext context, {required String title, String? body, String ok = 'OK', bool danger = false, I icon = I.info}) async {
  final c = TmColors.of(context);
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: TechMekuIcon(icon, size: 32, color: danger ? c.warn : c.active),
      title: Text(title, style: const TextStyle(fontSize: 17)),
      content: body == null ? null : Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: c.warn) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<void> infoDialog(BuildContext context, {required String title, String? body, I icon = I.info, bool warn = false}) {
  final c = TmColors.of(context);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: TechMekuIcon(icon, size: 32, color: warn ? c.warn : c.active),
      title: Text(title, style: const TextStyle(fontSize: 17)),
      content: body == null ? null : Text(body),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ),
  );
}

/// 通報理由（設計判断 #5）
const reportReasons = {'spam': 'スパム', 'abuse': '誹謗中傷', 'sexual': '性的なコンテンツ', 'illegal': '違法なコンテンツ', 'other': 'その他'};

Future<String?> pickReportReason(BuildContext context) => showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(leading: TechMekuIcon(I.flag), title: Text('通報の理由', style: TextStyle(fontWeight: FontWeight.bold))),
          for (final e in reportReasons.entries) ListTile(title: Text(e.value), onTap: () => Navigator.pop(ctx, e.key)),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text('通報すると、あなたには直ちに表示されなくなります。3人から通報されると全体から非表示になり、管理者が確認します。', style: TextStyle(fontSize: 12)),
          ),
        ]),
      ),
    );

class Badge2 extends StatelessWidget {
  const Badge2(this.text, {super.key, this.color, this.icon});
  final String text;
  final Color? color;
  final I? icon;

  @override
  Widget build(BuildContext context) {
    final c = TmColors.of(context);
    final col = color ?? c.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: col), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[TechMekuIcon(icon!, size: 13, color: col), const SizedBox(width: 3)],
        Text(text, style: TextStyle(fontSize: 11, color: col, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// 右側の縦並びアクション（2.9）。タップ領域は 44dp 以上
class RailAction {
  const RailAction(this.icon, this.label, this.onTap, {this.active = false, this.count});
  final I icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final int? count;
}

class ActionRail extends StatelessWidget {
  const ActionRail(this.actions, {super.key});
  final List<RailAction> actions;

  @override
  Widget build(BuildContext context) {
    final c = TmColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final a in actions)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              width: 56,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Material(
                  color: c.railBg,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: a.onTap,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(child: TechMekuIcon(a.icon, active: a.active, muted: a.onTap == null, size: 24)),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(a.count != null ? '${a.count}' : a.label, style: TextStyle(fontSize: 10, color: a.active ? c.active : c.ink), maxLines: 1),
              ]),
            ),
          ),
      ],
    );
  }
}

/// 要約カード（タイトル・冒頭・画像・サイト・著者・タグ）
class ArticleCard extends StatelessWidget {
  const ArticleCard({
    super.key,
    required this.summary,
    required this.rail,
    required this.onOpen,
    this.localThumb,
    this.badges = const [],
    this.footer,
  });

  final ArticleSummary summary;
  final Widget rail;
  final VoidCallback onOpen;
  final String? localThumb;
  final List<Widget> badges;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = TmColors.of(context);
    final s = summary;
    Widget? image;
    if (localThumb != null && File(localThumb!).existsSync()) {
      image = Image.file(File(localThumb!), fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox());
    } else if (s.thumbnailUrl != null) {
      image = Image.network(s.thumbnailUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox());
    }
    return Stack(children: [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 76, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(s.source.label, style: TextStyle(color: c.active, fontWeight: FontWeight.bold, fontSize: 13)),
                if (s.author != null) Flexible(child: Text(' ・ ${s.author}', style: TextStyle(color: c.muted, fontSize: 13), overflow: TextOverflow.ellipsis)),
                if (s.publishedAt != null) Text(' ・ ${relativeTime(s.publishedAt!)}', style: TextStyle(color: c.muted, fontSize: 13)),
              ]),
              const SizedBox(height: 10),
              if (s.emoji != null) Text(s.emoji!, style: const TextStyle(fontSize: 44)),
              Text(s.title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold, height: 1.4), maxLines: 4, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 10),
              if (badges.isNotEmpty) ...[Wrap(spacing: 6, runSpacing: 6, children: badges), const SizedBox(height: 10)],
              if (image != null)
                Flexible(
                  flex: 3,
                  child: ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: double.infinity, child: image)),
                ),
              if (image != null) const SizedBox(height: 10),
              if (s.summary != null && s.summary!.isNotEmpty)
                Flexible(
                  flex: 2,
                  child: Text(s.summary!, style: TextStyle(color: c.ink.withValues(alpha: 0.85), height: 1.6), overflow: TextOverflow.fade),
                ),
              const Spacer(),
              if (s.tags.isNotEmpty)
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final t in s.tags.take(5))
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      TechMekuIcon(I.tag, size: 13, muted: true),
                      Text(' $t', style: TextStyle(color: c.muted, fontSize: 12)),
                    ]),
                ]),
              const SizedBox(height: 8),
              ?footer,
              Row(children: [
                TechMekuIcon(I.book_open, size: 14, muted: true),
                Text(' タップで全文', style: TextStyle(color: c.muted, fontSize: 12)),
                if (s.likes > 0) ...[const SizedBox(width: 12), TechMekuIcon(I.heart, size: 14, muted: true), Text(' ${s.likes}', style: TextStyle(color: c.muted, fontSize: 12))],
              ]),
            ]),
          ),
        ),
      ),
      // アクションはタイトルの横の高さから並べる（親指が届きやすく、記事と対応が分かる位置）
      Positioned(right: 8, top: 48, child: rail),
    ]);
  }
}

/// ストック末尾などの状態カード（S05）
class StatusCard extends StatelessWidget {
  const StatusCard({super.key, required this.icon, required this.title, this.body, this.action, this.loading = false});
  final I icon;
  final String title;
  final String? body;
  final Widget? action;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = TmColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (loading) SizedBox(width: 44, height: 44, child: CircularProgressIndicator(color: c.active)) else TechMekuIcon(icon, size: 48, active: true),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          if (body != null) ...[const SizedBox(height: 8), Text(body!, style: TextStyle(color: c.muted), textAlign: TextAlign.center)],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text, this.action});
  final I icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => StatusCard(icon: icon, title: text, action: action);
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(text, style: TextStyle(color: TmColors.of(context).active, fontWeight: FontWeight.bold, fontSize: 13)),
      );
}
