import 'package:flutter/material.dart';

import '../../core/techmeku_icon.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/batch.dart';
import '../common/widgets.dart';

/// 一括DLの進捗・結果（S06）
class BatchSheet extends StatelessWidget {
  const BatchSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => const BatchSheet(),
      );

  @override
  Widget build(BuildContext context) {
    final c = TmColors.of(context);
    final b = BatchRunner.instance;
    return ListenableBuilder(
      listenable: b,
      builder: (context, _) {
        final r = b.lastResult;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                TechMekuIcon(b.running ? I.loader : I.download, active: true),
                const SizedBox(width: 8),
                Text(b.running ? '一括DL中（${b.done}/${b.total}）' : '一括DL', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: const TechMekuIcon(I.close), onPressed: () => Navigator.pop(context)),
              ]),
              const SizedBox(height: 8),
              for (final p in b.progress.values) _SiteRow(p),
              const SizedBox(height: 12),
              if (!b.running && r != null) ...[
                if (r.canceled)
                  Text('中止しました。入れ替え（削除・キャッシュ移動）は行っていません。', style: TextStyle(color: c.muted))
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(10)),
                    child: Wrap(spacing: 16, runSpacing: 6, children: [
                      Text('新規 ${r.newCount}件'),
                      Text('残した ${r.keptCount}件'),
                      Text('キャッシュへ ${r.cachedCount}件'),
                      Text('入れ替えで削除 ${r.deletedCount}件'),
                    ]),
                  ),
                if (r.overLimit)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(children: [
                      TechMekuIcon(I.warning, color: c.warn, size: 18),
                      const SizedBox(width: 6),
                      Expanded(child: Text('保存容量の上限を超えています。設定から整理してください。', style: TextStyle(color: c.warn))),
                    ]),
                  ),
              ],
              const SizedBox(height: 12),
              if (b.running)
                OutlinedButton.icon(
                  onPressed: b.trigger == BatchTrigger.manual ? b.cancel : null,
                  icon: const TechMekuIcon(I.close, size: 18),
                  label: Text(b.trigger == BatchTrigger.manual ? '中止' : '自動取得中'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                )
              else
                FilledButton.icon(
                  onPressed: () => BatchRunner.instance.run(BatchTrigger.manual),
                  icon: TechMekuIcon(I.refresh, size: 18, color: c.bg),
                  label: const Text('一括DLを実行'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                ),
              const SizedBox(height: 6),
              Text('興味タグ内の直近7日の人気記事に入れ替えます。個別DL・いいね済み・投稿記事は残ります。', style: TextStyle(fontSize: 12, color: c.muted)),
            ]),
          ),
        );
      },
    );
  }
}

class _SiteRow extends StatelessWidget {
  const _SiteRow(this.p);
  final SiteProgress p;

  @override
  Widget build(BuildContext context) {
    final c = TmColors.of(context);
    final ratio = p.total == 0 ? (p.finished ? 1.0 : null) : p.done / p.total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(p.source.label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          if (p.error != null)
            Flexible(child: Text(p.error!, style: TextStyle(color: c.warn, fontSize: 12), overflow: TextOverflow.ellipsis))
          else if (p.finished)
            Row(children: [TechMekuIcon(I.check_circle, size: 16, color: c.ok), Text(' ${p.done}/${p.total}', style: TextStyle(color: c.ok))])
          else
            Text('${p.done}/${p.total}', style: TextStyle(color: c.muted)),
        ]),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: p.error != null ? 0 : ratio, color: p.error != null ? c.warn : c.active, backgroundColor: c.card),
      ]),
    );
  }
}
