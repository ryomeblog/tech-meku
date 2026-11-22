import '../models/models.dart';
import '../sources/article_source.dart';
import 'sources.dart';
import 'stock.dart';

/// URL からストックに保存（v2.4。設計書 2.18・5.10）
class UrlSave {
  UrlSave._();

  /// 入力（または共有テキスト）から対応サイトの記事を特定する。端末内で判定し、通信しない
  static ArticleRef? resolve(String text) {
    final uri = articleUri(text);
    if (uri == null) return null;
    for (final t in SourceType.external) {
      final ref = Sources.instance.of(t).matchUrl(uri);
      if (ref != null) return ref;
    }
    return null;
  }

  /// プレビュー用に記事 1 件を取得し、保存済みのストックがあれば一緒に返す
  static Future<(ArticleSummary, StockArticle?)> preview(ArticleRef ref) async {
    final s = await Sources.instance.guard(ref.source, () => Sources.instance.of(ref.source).fetchByRef(ref));
    return (s, await StockRepo.instance.byKey(s.source, s.sourceKey));
  }

  /// 個別DL として保存（origin=manual）。一括DL由来なら manual に切り替え、キャッシュにあればストックに戻す
  static Future<StockArticle> save(ArticleSummary s) => StockRepo.instance.downloadManual(s);
}
