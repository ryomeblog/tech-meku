import 'package:flutter/material.dart';

import '../../core/settings.dart';
import '../../core/techmeku_icon.dart';
import '../../core/theme.dart';
import '../../services/tags.dart';
import '../common/widgets.dart';

/// 興味タグ選択（S07）。一覧から選択＋自由入力、最大10。初回はスキップ可
class TagSelectPage extends StatefulWidget {
  const TagSelectPage({super.key, this.onboarding = false, this.onDone});
  final bool onboarding;
  final VoidCallback? onDone;

  @override
  State<TagSelectPage> createState() => _TagSelectPageState();
}

class _TagSelectPageState extends State<TagSelectPage> {
  late final List<String> _selected = [...Settings.instance.interestTags];
  final _input = TextEditingController();

  void _toggle(String t) {
    setState(() {
      if (_selected.contains(t)) {
        _selected.remove(t);
      } else if (_selected.length < Settings.maxInterestTags) {
        _selected.add(t);
      } else {
        showSnack(context, '興味タグは10個までです');
      }
    });
  }

  void _addFree() {
    final t = _input.text.trim().replaceAll('#', '');
    if (t.isEmpty) return;
    if (!_selected.contains(t)) _toggle(t);
    _input.clear();
  }

  Future<void> _finish({bool save = true}) async {
    if (save) await Settings.instance.setInterestTags(_selected);
    await Settings.instance.setOnboarded();
    if (widget.onDone != null) {
      widget.onDone!();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TmColors.of(context);
    final free = _selected.where((t) => !presetTags.any((p) => p.label == t)).toList();
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.onboarding,
        leading: widget.onboarding ? null : IconButton(icon: const TechMekuIcon(I.back), onPressed: () => Navigator.pop(context)),
        title: const Text('興味タグ', style: TextStyle(fontSize: 17)),
        actions: [if (widget.onboarding) TextButton(onPressed: () => _finish(save: false), child: const Text('スキップ'))],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.onboarding) ...[const Text('技術を、めくって発見する。', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 6)],
            Text('興味のあるタグを選んでください（${_selected.length}/10）。おすすめの内容と一括DLの絞り込みに使います。タグは端末にだけ保存されます。', style: TextStyle(color: c.muted)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in presetTags)
                  FilterChip(
                    label: Text(t.label),
                    selected: _selected.contains(t.label),
                    onSelected: (_) => _toggle(t.label),
                    avatar: _selected.contains(t.label) ? null : const TechMekuIcon(I.plus, size: 14),
                  ),
                for (final t in free) FilterChip(label: Text(t), selected: true, onSelected: (_) => _toggle(t)),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    decoration: const InputDecoration(
                      hintText: '自由入力（例：Svelte）',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Padding(padding: EdgeInsets.all(12), child: TechMekuIcon(I.tag, size: 16)),
                    ),
                    onSubmitted: (_) => _addFree(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(onPressed: _addFree, icon: const TechMekuIcon(I.plus)),
              ],
            ),
            const SizedBox(height: 8),
            Text('自由入力のタグは、Qiita と note にはそのまま、Zenn には小文字にして使います。未設定の場合は「AI」とランダムな2つのタグを使います。', style: TextStyle(fontSize: 12, color: c.muted)),
          ],
        ),
      ),
      // 決定ボタンは画面下部に固定し、端末のナビゲーションボタンの上に置く
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _finish,
            icon: TechMekuIcon(I.check, color: c.bg, size: 18),
            label: Text(widget.onboarding ? 'はじめる' : '保存'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ),
      ),
    );
  }
}
