import 'package:flutter/foundation.dart';

import '../core/settings.dart';
import '../core/util.dart';
import '../models/models.dart';
import '../sources/article_source.dart';
import '../sources/note.dart';
import '../sources/qiita.dart';
import '../sources/zenn.dart';

/// アダプタの一覧と、サイト単位の失敗・一時停止の管理
class Sources {
  Sources._();
  static final Sources instance = Sources._();

  final Map<SourceType, ArticleSource> _all = {
    SourceType.qiita: QiitaSource(),
    SourceType.zenn: ZennSource(),
    SourceType.note: NoteSource(),
  };

  ArticleSource of(SourceType t) => _all[t]!;

  @visibleForTesting
  void override(SourceType t, ArticleSource s) => _all[t] = s;

  /// 連続失敗がこの回数以上なら「仕様変更の可能性」と表示する
  static const failThreshold = 3;

  bool qiitaPaused() => Settings.instance.qiitaPausedUntil > nowMs();

  /// 失敗したらサイト単位で記録し、利用者向けの文言にして投げ直す
  Future<T> guard<T>(SourceType t, Future<T> Function() f) async {
    if (t == SourceType.qiita && qiitaPaused()) {
      throw SourceException('Qiitaは一時的に取得できません', rateLimited: true);
    }
    try {
      final r = await f();
      if (Settings.instance.failures(t) != 0) await Settings.instance.setFailures(t, 0);
      return r;
    } on SourceException catch (e) {
      if (e.rateLimited && t == SourceType.qiita) {
        await Settings.instance.setQiitaPausedUntil(nowMs() + hourMs);
        throw SourceException('Qiitaは一時的に取得できません', rateLimited: true);
      }
      final n = Settings.instance.failures(t) + 1;
      await Settings.instance.setFailures(t, n);
      if (n >= failThreshold) throw SourceException('${t.label}：取得できません（仕様変更の可能性）');
      throw SourceException('${t.label}：${e.message}');
    } catch (e) {
      final n = Settings.instance.failures(t) + 1;
      await Settings.instance.setFailures(t, n);
      throw SourceException(n >= failThreshold ? '${t.label}：取得できません（仕様変更の可能性）' : '${t.label}：取得に失敗しました');
    }
  }
}
