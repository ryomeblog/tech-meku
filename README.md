<p align="center">
  <img src="app/assets/brand/techmeku_icon_192.png" width="96" alt="TechMeku">
</p>

<h1 align="center">TechMeku（テクメク）</h1>

<p align="center"><b>技術を、めくって発見する。</b></p>

Qiita・Zenn・note の技術記事を端末に保存し、オフラインでも上下スワイプで次々に読める Android アプリです（Flutter 製）。
興味タグに合った新着記事を「おすすめ」で流し読みでき、アプリ内で記事を投稿することもできます。投稿は 24 時間で消えますが、いいね・コメントで公開期間が延びます。

> [!NOTE]
> 現在は **開発中（テスト段階）** です。Google Play での配布はまだ行っていません。

## 主な機能

- **ホーム 3 タブ**：おすすめ ／ ストック ／ みんなの投稿。起動時にオフラインならストックを開きます
- **一括DL**：興味タグに沿って記事をまとめて端末に保存します（入れ替え方式）。未閲覧が残り 5 件になると自動で補充します
- **閲覧状態**：未閲覧 ／ 閲覧済 ／ 既読（全文を開いた）の 3 段階で管理します
- **投稿**：24 時間で消える短期公開です。いいね・コメントで延長でき、通報とモデレーションも備えています
- **プロフィール**：自分で保存した記事（ストック）と、いいねした記事

## 構成

| 項目 | 内容 |
|---|---|
| 対象 OS | Android |
| クライアント | Flutter |
| サーバー | Cloudflare Workers + D1 + R2 + Cron Triggers + Access（無料枠のみで運用） |
| 認証 | Google ログイン（メールアドレス・氏名は保存しません） |

外部記事は端末から直接取得し、サーバーには保存しません。サーバーが扱うのは投稿・いいね・コメント・通報・認証だけです。

## インフラ構成

![TechMeku インフラ構成図](doc/infrastructure.drawio.png)

| 場所 | 役割 |
|---|---|
| 利用者の Android 端末 | アプリ本体。Qiita・Zenn・note から記事を**端末が直接**取得し、本文・画像をアプリ専用ストレージ、ストック・キャッシュ・いいね一覧を SQLite、興味タグ・設定を shared_preferences に保存する。1日1回の自動DLは WorkManager |
| 外部の記事サイト | Qiita API v2（公式・認証なし 60回/時）、Zenn・note の API（非公式）。サイトごとのアダプタで取得し、壊れたサイトだけ止められる |
| Google | Google ログイン。アプリが受け取った ID トークンを Workers が公開鍵（JWKS）で検証する |
| Cloudflare Workers（`techmeku-api`） | Hono 製の API。認証、みんなの投稿・いいね・コメント・通報、投稿画像の配信、管理ページ |
| Cloudflare D1（`techmeku-db`） | ユーザー（Google の ID は HMAC でハッシュ化）・投稿・いいね・コメント・通報 |
| Cloudflare R2（`techmeku-images`） | 投稿画像。非公開で、公開中の投稿の画像だけ Workers 経由で配信する |
| Cron Triggers | 毎時、期限切れの投稿・コメント・画像を物理削除する |
| Cloudflare Access | 管理ページ `/admin` を管理者だけに公開する（未設定の間は常に 403） |

データの流れは次の4つです。

1. **記事の取得**：端末 → 各サイト。取得した外部記事はサーバーに送りません
2. **ログイン**：Google の ID トークンを Workers が検証し、セッション JWT（30日）を発行します
3. **投稿系**：みんなの投稿（24時間、いいね・初回コメントで最大7日まで延長）、コメント、通報
4. **管理**：Cloudflare Access で守った `/admin` から通報対応・アカウント停止

メールアドレス・氏名・プロフィール画像は、サーバーにもアプリにも保存しません。

構成図は draw.io のデータを埋め込んだ PNG です。[draw.io](https://app.diagrams.net/) で `doc/infrastructure.drawio.png` を開くと、そのまま編集できます。

## リポジトリ構成

```
.
├── app/                      # Flutter アプリ（Android）
│   ├── lib/
│   │   ├── core/             # 設定値・テーマ・アイコン・端末DB・アプリ設定
│   │   ├── models/           # データモデル
│   │   ├── sources/          # Qiita / Zenn / note の取得アダプタ
│   │   ├── services/         # ストック・一括DL（入れ替え）・サーバーAPI・ログイン・定期DL
│   │   └── ui/               # 画面（S01〜S16）
│   ├── assets/               # アプリアイコン（brand）と UI アイコン（icons）
│   └── test/                 # ユニットテスト
├── server/                   # Cloudflare Workers（Hono + D1 + R2）
│   ├── src/                  # API・管理ページ・Cron
│   ├── migrations/           # D1 スキーマ
│   └── test/e2e.mjs          # API の E2E テスト（ローカル）
└── doc/
    ├── design.md             # 設計書
    ├── wireframes.html       # 全画面のワイヤーフレーム
    ├── infrastructure.drawio.png  # インフラ構成図（draw.io で編集可）
    ├── api-verification.md   # 外部 API の検証結果
    ├── terms.md / privacy.md # 利用規約・プライバシーポリシー（ドラフト）
    └── icon/                 # アイコン一覧と画面ごとの対応表
```

## 開発

### アプリ（`app/`）

必要なもの：Flutter SDK、Android SDK（Android Studio）、Android 端末またはエミュレーター。

```sh
cd app
flutter pub get
flutter test                 # ユニットテスト
flutter run                  # 本番サーバー（techmeku-api.ryome-blog.workers.dev）につなぐ
flutter run --dart-define=API_BASE=http://10.0.2.2:8787   # エミュレーターからローカルの wrangler dev につなぐ
```

Google ログインは、Google Cloud の OAuth クライアント（Android・Web）にパッケージ名 `com.ryomeblog.techmeku` とビルドに使う署名の SHA-1 が登録されている必要があります。

### サーバー（`server/`）

必要なもの：Node.js、Wrangler、Cloudflare アカウント。

```sh
cd server
npm install
wrangler d1 migrations apply techmeku-db --local
wrangler dev --test-scheduled      # 別ターミナルで npm test（E2E テスト）
wrangler deploy                    # 本番へ
```

シークレット（`SERVER_SECRET` / `SESSION_SECRET` / `IP_SALT_SECRET`）は `wrangler secret put` で登録します。ローカルでは `server/.dev.vars`（コミットしない）に書きます。

管理ページ（`/admin`）は Cloudflare Access で保護します。`wrangler.jsonc` の `ACCESS_TEAM_DOMAIN` と `ACCESS_AUD` を設定するまでは常に 403 を返します。

## ドキュメント

- [設計書](doc/design.md)：仕様と実装設計。1〜3 章が確定した仕様、4〜9 章が実装設計です
- [ワイヤーフレーム](doc/wireframes.html)：ブラウザで開いてください（アイコンは `app/assets/` を参照するため、クローンしてから開きます）
- [インフラ構成図](doc/infrastructure.drawio.png)：draw.io で開くと編集できます
- [外部 API の検証結果](doc/api-verification.md)
- [アイコン対応表](doc/icon/ICON_USAGE.md)

## ライセンス

[MIT License](LICENSE)

アプリで表示する外部記事の著作権は、それぞれの執筆者に帰属します。
