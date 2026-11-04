<p align="center">
  <img src="assets/brand/techmeku_icon_192.png" width="96" alt="TechMeku">
</p>

<h1 align="center">TechMeku（テクメク）</h1>

<p align="center"><b>技術を、めくって発見する。</b></p>

Qiita・Zenn・note の技術記事を端末に保存し、オフラインでも上下スワイプで次々に読める Android アプリです（Flutter 製）。
興味タグに合った新着記事を「おすすめ」で流し読みでき、アプリ内で記事を投稿することもできます。投稿は 24 時間で消えますが、いいね・コメントで公開期間が延びます。

> [!NOTE]
> 現在は **設計段階** です。このリポジトリには設計書、ワイヤーフレーム、アイコン素材が入っています。アプリ本体の実装はこれからです。

## 主な機能

- **ホーム 3 タブ**：おすすめ ／ ストック ／ みんなの投稿。起動時にオフラインならストックを開きます
- **一括DL**：興味タグに沿って記事をまとめて端末に保存します（入れ替え方式）。未閲覧が残り 5 件になると自動で補充します
- **閲覧状態**：未閲覧 ／ 閲覧済 ／ 既読（全文を開いた）の 3 段階で管理します
- **投稿**：24 時間で消える短期公開です。いいね・コメントで延長でき、通報とモデレーションも備えています
- **プロフィール**：自分で保存した記事（ストック）と、いいねした記事

## 構成

| 項目 | 内容 |
|---|---|
| 対象 OS | Android（Google Play で公開予定） |
| クライアント | Flutter |
| サーバー | Cloudflare Workers + D1 + R2 + Cron Triggers + Access（無料枠のみで運用） |
| 認証 | Google ログイン（メールアドレス・氏名は保存しません） |

外部記事は端末から直接取得し、サーバーには保存しません。サーバーが扱うのは投稿・いいね・コメント・通報・認証だけです。

## リポジトリ構成

```
.
├── doc/
│   ├── design.md          # 設計書（仕様・アーキテクチャ・データ設計・実装ステップ）
│   ├── wireframes.html    # 全画面のワイヤーフレーム（S01〜S16, A01）
│   └── icon/              # アイコン一覧のプレビューと画面ごとの対応表
├── assets/
│   ├── brand/             # アプリアイコン（PNG）
│   └── icons/             # UI アイコン（SVG 62 種 × default / active / muted）
├── lib/
│   ├── techmeku_icon.dart         # TechMekuIcon ウィジェット
│   └── example_action_rail.dart   # カード右側のアクションボタン列の実装例
├── icon_manifest.json             # アイコン名・用途・ファイルパスの一覧
└── pubspec_assets_snippet.yaml    # pubspec.yaml に追加する設定
```

## ドキュメント

- [設計書](doc/design.md)：仕様と実装設計。1〜3 章が確定した仕様、4〜9 章が実装設計です
- [ワイヤーフレーム](doc/wireframes.html)：ブラウザで開いてください。アイコンは `assets/` 以下のファイルを参照しているため、リポジトリをクローンしてから開く必要があります
- [アイコン対応表](doc/icon/ICON_USAGE.md)：画面ごとに使うアイコンと、Flutter への導入方法

## アイコンの使い方（Flutter）

`pubspec.yaml` に次を追加します。

```yaml
dependencies:
  flutter_svg: ^2.0.0
flutter:
  assets:
    - assets/icons/default/
    - assets/icons/active/
    - assets/icons/muted/
    - assets/brand/
```

```dart
TechMekuIcon(name: TechMekuIconName.heart, active: liked, size: 24)
```

## ライセンス

[MIT License](LICENSE)

アプリで表示する外部記事の著作権は、それぞれの執筆者に帰属します。
