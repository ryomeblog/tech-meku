import 'dart:math';

import '../core/settings.dart';
import '../sources/article_source.dart';

/// 興味タグの一覧（doc/design.md 5.2、設計判断 #11）。サイトごとの名前を持つ
const presetTags = <Tag>[
  Tag('AI', zenn: 'ai'),
  Tag('LLM', zenn: 'llm'),
  Tag('Python', zenn: 'python'),
  Tag('JavaScript', zenn: 'javascript'),
  Tag('TypeScript', zenn: 'typescript'),
  Tag('React', zenn: 'react'),
  Tag('Next.js', zenn: 'nextjs'),
  Tag('Flutter', zenn: 'flutter'),
  Tag('Kotlin', zenn: 'kotlin'),
  Tag('Swift', zenn: 'swift'),
  Tag('Go', zenn: 'go'),
  Tag('Rust', zenn: 'rust'),
  Tag('AWS', zenn: 'aws'),
  Tag('Google Cloud', qiita: 'GoogleCloud', zenn: 'googlecloud', note: 'GoogleCloud'),
  Tag('Azure', zenn: 'azure'),
  Tag('Docker', zenn: 'docker'),
  Tag('Kubernetes', zenn: 'kubernetes'),
  Tag('セキュリティ', zenn: 'security'),
  Tag('Linux', zenn: 'linux'),
  Tag('Git', zenn: 'git'),
  Tag('Godot', zenn: 'godot'),
  Tag('Unity', zenn: 'unity'),
  Tag('個人開発'),
  Tag('初心者'),
];

Tag tagFor(String label) => presetTags.firstWhere((t) => t.label == label, orElse: () => Tag.free(label));

class TagService {
  TagService._();
  static final TagService instance = TagService._();

  bool _pickedThisLaunch = false;

  /// 起動ごとに「AI＋一覧からランダムに2つ」を選び直して保存する（2.2）
  Future<void> onLaunch() async {
    if (_pickedThisLaunch) return;
    _pickedThisLaunch = true;
    final pool = presetTags.where((t) => t.label != 'AI').toList()..shuffle(Random());
    await Settings.instance.setRandomTags(['AI', pool[0].label, pool[1].label]);
  }

  bool get usingRandom => Settings.instance.interestTags.isEmpty;

  /// 現在のタグ（興味タグ、未設定なら直前の起動で選ばれたランダムタグ）
  List<Tag> current() {
    final s = Settings.instance;
    final labels = s.interestTags.isNotEmpty ? s.interestTags : (s.randomTags.isNotEmpty ? s.randomTags : const ['AI']);
    return labels.map(tagFor).toList();
  }
}
