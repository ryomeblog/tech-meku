# TechMeku（テクメク）設計書 v2.2

- キャッチコピー：**技術を、めくって発見する。**
- 対象：Claude Code への実装引き継ぎ
- 作成：2026-11-03（v1）／ 改訂：2026-11-04（v2・v2.1・v2.2 アイコン）
- 関連ファイル：`wireframes.html`（全画面のワイヤーフレーム）、`TechMeku_IconKit`（アプリアイコン・UIアイコン一式。8.5・8.6参照）

---

## 0. このドキュメントの読み方（Claude Code向け）

- **1〜3章** が仕様（ユーザー確定事項）。ここを変えるときは必ずユーザーに確認する。
- **4〜9章** が実装設計。技術的な細部は実装都合で調整してよいが、1〜3章の仕様は崩さない。
- 「**【要検証】**」は外部サービスの非公式仕様に依存する箇所。実装前に実際にリクエストを送り、レスポンス形式を確認してからコードを書くこと。
- 「**【設計判断】**」はユーザーに直接確認していない細部。違和感があればユーザーに確認する（一覧は11章）。

### 0.1 v2 の主な変更点

| 変更 | 内容 |
|---|---|
| 名称 | ArticleSwipe（仮）→ **TechMeku**。アイコン確定 |
| ホーム | 「おすすめ／ストック／みんなの投稿」の3タブ。起動時は **おすすめ**（オフラインなら ストック） |
| 興味タグ | 新設。おすすめの内容と一括DLの絞り込みに使う |
| 一括DL | **入れ替え方式**に変更。Qiita は最大20件 |
| ストック補充 | 未閲覧が残り5件になったら **自動で一括取得** |
| 閲覧状態 | 「未閲覧／閲覧済（カード表示）／既読（全文を開いた）」の3段階 |
| キャッシュ | 入れ替えで外れた閲覧済・既読記事は **タイトル＋URLのみ** を24時間保持 |
| ナビ | ボトムナビは **ホーム／自分の投稿／＋新規投稿／プロフィール／設定**（v2.1）。プロフィールは **ストック（自分で保存した記事）といいね** のみ |
| 全DL一覧 | 設定の中の「DLしたもの」に移動 |
| 不採用 | AI要点、関連技術（GitHub等） |
| アイコン（v2.2） | TechMeku Icon Kit（SVG 62種×3色）を採用。画面ごとの対応は 8.6 |

---

## 1. アプリ概要

Qiita・Zenn・note の技術記事を端末に保存し、オフラインでも TikTok のような上下スワイプで次々読めるスマホアプリ。
興味タグに沿った新着記事を「おすすめ」で流し読みでき、アプリ内で記事を投稿することもできる（投稿は24時間で消え、いいね・コメントで延長）。

| 項目 | 内容 |
|---|---|
| アプリ名 | **TechMeku（テクメク）**（Tech＋めくる） |
| 対象OS | **Android のみ**（Flutter製。将来 iOS 対応の余地は残す） |
| 公開 | **Google Play で公開する**（UGC ポリシー対応が必要） |
| クライアント | Flutter |
| サーバー | Cloudflare（Workers + D1 + R2 + Cron Triggers + Access）、**無料枠のみで運用** |
| 認証 | Google ログイン（Workers で ID トークン検証。メール・氏名は保存しない） |
| アイコン | `assets/brand/techmeku_icon_*.png`（紺の角丸背景に、記事カードでできたシアンの「T」）。UIアイコンは TechMeku Icon Kit |

---

## 2. 確定仕様

### 2.1 ホームの構成

| 項目 | 仕様 |
|---|---|
| タブ | 上部タブ：**おすすめ ／ ストック ／ みんなの投稿**（この順） |
| 起動時 | **おすすめ** を開く。**起動時にオフラインなら自動でストック**を開く |
| 操作 | どのタブも上下スワイプで次の記事へ。カードタップで全文 |
| 表示 | **要約カード**（タイトル・冒頭・画像・サイト・著者・タグ）→ タップで全文 |
| 右側アクション | 縦並びのアイコン＋短いラベル。タップ領域は 44dp 以上。アクション操作がスワイプ判定に干渉しないこと |

### 2.2 おすすめタブ

| 項目 | 仕様 |
|---|---|
| 内容 | **興味タグの新着記事**（Qiita・Zenn・note のうち ON のサイト） |
| 並び | タグごとに各サイトの新着を取得し、**混ぜて投稿日時の新しい順**。下へ進むと続きを読み込む |
| DL済みの記事 | 流すが「保存済」と表示 |
| 全文 | タップで **その場で取得して表示。保存はしない**。残したいときだけ「DL」 |
| オンライン専用 | オフライン時は「オフラインです。ストックをご覧ください」 |
| 興味タグ未設定時 | **「AI」＋タグ一覧からランダムに2つ**。**起動ごとに選び直す** |

### 2.3 興味タグ

| 項目 | 仕様 |
|---|---|
| 選び方 | **初回起動で一覧から選択＋自由入力**（スキップ可）。設定・プロフィールから変更 |
| 上限 | 最大 **10 個** |
| 保存先 | 端末のみ（サーバーには送らない） |
| 効く範囲 | **おすすめの内容**と**一括DLの絞り込み**（2.4） |
| note | v1 の「note のハッシュタグ」設定は廃止し、興味タグを note のハッシュタグとして使う |

### 2.4 一括DL（外部記事の取得）

| 項目 | 仕様 |
|---|---|
| 対象サイト | Qiita / Zenn / note（設定でサイトごとに ON/OFF） |
| 取得経路 | **端末から各サイトへ直接取得**。サーバーには外部記事を一切置かない |
| 選び方 | **興味タグ内の直近7日間のいいね上位**。タグ未設定時は「AI＋ランダム2つ」（2.2 と同じタグ）で絞る |
| 件数 | **サイトごとに設定件数（全タグ合計）**。設定は 10/30/50（初期50）。**Qiita は最大20件**（設定が10なら10、30・50なら20） |
| 実行のきっかけ | ①手動の「一括DL」ボタン ②定期自動（1日1回、設定「Wi-Fi時のみ」に従う） ③**ストックの未閲覧が残り5件になったとき（2.6）** |
| 方式 | **入れ替え**（2.5） |
| 個別DL | おすすめ・ストック・投稿のカード／全文から 1 記事ずつ DL できる |
| 保存先 | キャッシュ領域ではなくアプリのストレージ（OS に消されない領域）。本文と画像を保存 |
| 容量上限 | 初期 **3GB**（設定で変更可）。**超えたら警告を出すが DL は続行** |
| 確認 | 入れ替えで消す前の確認は **しない**。完了後に件数を表示（例：新規42件・入れ替えで削除38件） |

### 2.5 入れ替えのルール

一括DL（手動・定期・自動補充のすべて）は「前回までの一括DL分を新しい人気記事セットに入れ替える」。

1. 新しく取得する記事セットを決め、まだ持っていない記事を DL する。
2. **新しいセットに含まれる既存記事は残す**（再DLしない）。
3. 新しいセットに含まれない **一括DL由来の記事** は次のとおり処理する：

| 記事の状態 | 処理 |
|---|---|
| **個別DLした記事**／**いいねした記事**／**投稿記事** | **残す**（入れ替え対象外） |
| 未閲覧 | 削除 |
| 閲覧済・既読 | 本文・画像を削除し、**キャッシュ（タイトル＋URLのみ）へ移す** |
| 自動補充のきっかけになった「残りの未閲覧」 | **すぐには消さない**。見終わった（カードを表示した）時点でキャッシュへ移す |

- 一部のサイトの取得に失敗しても **全部入れ替える**（失敗したサイトの古い一括DL分も上の表どおり処理される）。
- 【設計判断】手動の一括DLを「中止」した場合は、入れ替え（削除・キャッシュ移動）を行わない。

### 2.6 ストックの自動補充

- ストックフィードで **未閲覧の最後から5番目のカードを表示した時点**（＝そのカードの後ろの未閲覧が4件になった時点）で、自動で一括取得（入れ替え）を開始する。
- 未閲覧がもともと5件未満なら、ストックを開いて最初のカードを表示した時点で開始する【設計判断】。
- **通信の種類に関わらず実行**（モバイル通信でも行う。設定「Wi-Fi時のみ」は定期自動DLだけに効く）。
- 新しい記事は、残りの未閲覧の **後ろに続けて** 追加される（スワイプが途切れない）。
- 取得中・オフラインで最後までスワイプしたら、**最後に状態カード**を表示：
  - 取得中：「新しい記事を取得中（30/90）」— 届いた記事から順に後ろへ追加
  - オフライン：「オフラインです。接続すると取得します」— 接続したら自動で開始
- 【設計判断】自動補充で新規が0件だった場合、30分間は再実行しない（同じ取得の繰り返しを防ぐ）。

### 2.7 閲覧状態と並び順

| 状態 | 定義 |
|---|---|
| 未閲覧 | まだカードを表示していない |
| 閲覧済 | カードを表示した（全文は開いていない） |
| 既読 | 全文を開いた |

- ストックの並び：**未閲覧 → 閲覧済 → 既読**、それぞれ **DLが新しい順**。サイトで絞り込み可。
- ストックフィードに流すのは、ストレージにある記事すべて（一括DL分・個別DL分・投稿記事）。キャッシュは流さない。

### 2.8 キャッシュ

- 中身は **タイトル＋URL（＋サイト名）のみ**。本文・画像は持たない。
- **24時間で削除**。さらに、次の入れ替えでキャッシュに新しい記事が追加されるときは、**それまでのキャッシュは削除**する（キャッシュには常に直近1回分だけが残る）。
- 見られる場所：**設定の「DLしたもの」一覧に「キャッシュ」表示**で並ぶ。フィードには出さない。
- 開くと、**アプリ内でオンライン取得して全文表示**（おすすめと同じ）。「DL」で自分のストックに戻せる。

### 2.9 アクション（カード右側の縦並びボタン）

| アクション | おすすめ（未DLの外部記事） | ストック（外部記事） | みんなの投稿 |
|---|---|---|---|
| いいね | ○ 端末に保存 | ○ 端末に保存 | ○ サーバーに記録＋公開延長 |
| コメント | × | × | ○ |
| DL | ○（済なら「保存済」） | 「保存済」表示 | ○ |
| 共有 | ○ 記事URL | ○ 記事URL | ○【設計判断】タイトル＋冒頭のテキスト |
| 元記事 | ○ ブラウザで開く | ○ ブラウザで開く | ×（元記事がない） |
| 通報 | × | × | ○（自分の投稿なら「編集・削除」） |

### 2.10 いいね

- いいねすると端末の「いいね一覧」に登録（**プロフィールのいいねタブ**で見る）。
- **参照先**：ストレージにDL済みなら **ストックの記事**（オフラインで開ける）、なければ外部記事は **URL**、投稿記事は **投稿ID**。ストックから消えれば自動で URL／投稿参照に戻る。
- いいねした一括DL記事は入れ替えで消えない（2.5）。いいねを外せば、次の入れ替えから通常どおり扱う。
- 投稿記事が公開終了し、DL もしていなければ「公開終了」とタイトルだけ残る。
- 外部記事へのいいねで本文の自動DLはしない。Qiita 等の本体には反映しない。

### 2.11 プロフィール

| 項目 | 仕様 |
|---|---|
| ヘッダー | ニックネーム、興味タグ（編集ボタン）。未ログインなら「ログイン」ボタン |
| タブ | **ストック**（自分で個別DLした記事・投稿記事のDL）／**いいね**（いいねしたもの全部：外部記事と投稿） の2つだけ |
| 未ログイン | ストック・いいねとも使える（端末内のデータのため） |

### 2.12 投稿

| 項目 | 仕様 |
|---|---|
| 入口 | ボトムナビの「＋新規投稿」→ 投稿エディタ（上部に 自分 n/5・全体 n/100 を表示）【設計判断】 |
| 自分の投稿 | ボトムナビの「自分の投稿」画面：公開中 n/5、全体 n/100、各投稿の残り時間・いいね数・コメント数、編集・削除、「＋新しく投稿する」。未ログインならログインを案内 |
| ログイン | 投稿・いいね（投稿記事）・コメント・通報には **ログイン必須**。閲覧・DL・外部記事のいいねは未ログインで可 |
| 形式 | タイトル ＋ Markdown 本文 ＋ タグ。プレビュー付き |
| 上限 | タイトル 100 字、本文 **10,000 字**、タグ 5 個、**画像 3 枚** |
| 1人の上限 | **ログインアカウント単位で、同時に公開中の投稿は最大 5 件** |
| 全体の上限 | **公開中は全体で最大 100 件**。満杯時は **エラー表示して拒否**し、「次に空く予定時刻」を表示 |
| 公開期間 | 投稿から 24 時間 |
| 編集 | タイトル・本文・タグ・画像すべて編集可。**期限は変わらない**。「編集済み」表示 |
| 削除 | 自分の投稿はいつでも削除可 |
| 期限切れ | **期限を過ぎた瞬間に表示から消す**。**1時間ごとの定期処理で物理削除**。期限切れ後に復活しない |
| DLした投稿 | サーバーから消えた後も **端末に残る**（入れ替え対象外）。「公開終了」バッジ |
| 画面での説明 | 投稿カードと投稿画面に「残り時間」と「いいね・初回コメントで延長（最大7日）」を表示 |

### 2.13 公開延長ルール

- **いいね**：いいねした時点から 24 時間後まで延長。
  - 1人 1 投稿につき 1 回。**自分の投稿にはいいねできない**。
  - **取り消し可**。取り消しても延長分は戻さない。**再いいねしても再延長しない**（いいね数は戻る）。
- **コメント**：コメントした時点から 24 時間後まで延長。
  - **1人 1 投稿につき初回のコメントのみ**延長。**自分の投稿へのコメントは延長しない**。消して書き直しても再延長しない。
- **上限**：投稿日時から **最大 7 日**。
  ```
  new_expires_at = max(current_expires_at, min(now + 24h, created_at + 7d))
  ```

### 2.14 コメント

- 投稿記事のみ。1 投稿 **50 件まで**、1 件 **200 字まで**。
- 自分のコメントは **削除のみ可**。**投稿者は自分の投稿についたコメントを削除できる**。
- 投稿が消えるとコメントも消える。

### 2.15 通報・モデレーション（Google Play 対応）

- 投稿とコメントを通報できる（ログイン必須、1人1対象につき1回）。通報した本人には **即座に非表示**。
- **3人から通報されたら自動で全体から非表示**。
- 管理者は **管理用Webページ**（Cloudflare Access で保護）で確認し、削除または復帰する。
- 管理者は **アカウント停止**ができる。停止中は投稿・いいね・コメント・通報が不可。**退会しても再登録できない**。
- **ブロック機能はなし**。
- 【設計判断】初回投稿前に利用規約への同意を求める。設定に利用規約・プライバシーポリシーへのリンク。

### 2.16 アカウント・個人情報

- Google ログイン。サーバーは **Google のユーザー固有ID（sub）をハッシュ化した値だけ**を保存。
- **メールアドレス・氏名・プロフィール画像は保存しない（ログにも出さない）**。
- 表示名は **ニックネーム**（初回は自動生成、変更可）。
- **複数アカウント対策**：同一 IP からの新規作成は **1 日 3 件まで**。IP はハッシュ化して当日分だけ保持。
- **退会**：投稿・コメント・いいねを **すべて即削除**（延長済みの期限は戻さない）。停止記録だけ残す。
- 興味タグ・ストック・いいね一覧は端末にだけあり、サーバーには送らない。

### 2.17 設定画面

| グループ | 項目 |
|---|---|
| 興味タグ | 興味タグの編集（最大10個） |
| DL | 取得件数（10/30/50、初期50。Qiitaは最大20と併記）、サイトごとの ON/OFF、定期自動DL ON/OFF、Wi-Fi 時のみ（定期自動DLだけに効く） |
| ストレージ | 使用量、容量上限（1/3/5/10GB、初期3GB）、**DLしたもの一覧**（全件。キャッシュも「キャッシュ」表示で含む。削除可）、全削除 |
| 表示 | テーマ（システム/ライト/ダーク）、文字サイズ |
| アカウント | ログイン／ログアウト、ニックネーム変更、アカウント削除 |
| その他【設計判断】 | 利用規約、プライバシーポリシー、ライセンス、バージョン |

---

## 3. 画面一覧（詳細は wireframes.html）

v2 で番号を振り直した。

| ID | 画面 | 主な要素 |
|---|---|---|
| S01 | ホーム：おすすめ | 興味タグ切替チップ、新着カード、右側アクション（いいね・DL・共有・元記事） |
| S02 | ホーム：ストック | 「オフラインで読めます」表示、件数・容量・前回更新、一括DL、サイト絞り込み |
| S03 | ホーム：みんなの投稿 | 残り時間と延長ルールの表示、いいね数・コメント数、通報 |
| S04 | 記事全文 | ローカル（ストック）／オンライン取得（おすすめ・キャッシュ）の両方 |
| S05 | ストック末尾の状態カード | 取得中／オフライン |
| S06 | 一括DLの進捗・結果 | サイトごとの進捗、入れ替え結果（新規・残した・キャッシュ・削除） |
| S07 | 興味タグ選択 | 初回起動・設定・プロフィールから。一覧＋自由入力、最大10 |
| S08 | プロフィール：ストック | 自分で保存した記事 |
| S09 | 自分の投稿（ボトムナビ） | n/5、n/100、残り時間、編集・削除 |
| S10 | プロフィール：いいね | 参照先バッジ（端末に保存済み／Web／公開中／公開終了） |
| S11 | 投稿エディタ | タイトル、タグ、本文（編集/プレビュー）、画像3枚、上限表示 |
| S12 | コメントシート | 一覧、入力欄（200字）、削除、通報 |
| S13 | ログイン | Google でログイン、保存しない情報の説明 |
| S14 | 設定 | 2.17 の項目 |
| S15 | DLしたもの一覧（設定内） | 全件、キャッシュ表示、絞り込み、削除 |
| S16 | ダイアログ類 | 全体100件満杯、5件上限、容量超過、通報、停止中など |
| A01 | 管理用Webページ | 通報一覧、非表示、削除・復帰、アカウント停止 |

ボトムナビ：**ホーム ／ 自分の投稿 ／ ＋新規投稿 ／ プロフィール ／ 設定**

---

## 4. 全体アーキテクチャ

```
[Android アプリ (Flutter)]
   │  ① 外部記事の一覧・本文の取得（端末から直接）
   ├──────────────▶ Qiita API v2 / Zenn 非公式API / note 非公式API
   │
   │  ② 投稿・いいね・コメント・通報・認証
   └──────────────▶ [Cloudflare Workers (API)]
                        ├─ D1 (投稿・ユーザー・いいね・コメント・通報)
                        ├─ R2 (投稿画像)
                        └─ Cron Trigger (毎時: 期限切れの物理削除)

[管理者のブラウザ] ──▶ Cloudflare Access ──▶ Workers /admin/*
```

### 4.1 無料枠との照合（2026-11 時点で確認）

| サービス | 無料枠 | 本アプリの想定 |
|---|---|---|
| Workers | 1 日 10 万リクエスト、CPU 10ms/リクエスト | 十分。重い処理（画像圧縮・Markdown変換）は端末側 |
| D1 | 1 日 500 万行読み取り／10 万行書き込み、5GB | 公開中は最大100件で余裕。**2026-09-01 から超過時は当日エラー**のためインデックス必須 |
| R2 | 10GB、書き込み系 100 万回/月、読み取り系 1,000 万回/月、転送無料 | 100件×3枚×最大500KB ≒ 150MB |
| Cloudflare Access | 無料プランで少人数利用可 | 管理者のみ |

おすすめ・一括DLの外部記事取得は端末から直接行うため、Cloudflare の無料枠は消費しない。

---

## 5. 外部記事の取得設計（端末側）

### 5.1 共通インターフェース

サイトごとに差し替え可能なアダプタにする（非公式APIが壊れたときに、そのサイトだけ止められるように）。

```dart
abstract class ArticleSource {
  SourceType get type; // qiita / zenn / note

  /// おすすめ用：タグの新着（投稿日時の新しい順）。cursor でページング
  Future<Page<ArticleSummary>> fetchLatest({required List<Tag> tags, String? cursor});

  /// 一括DL用：タグ内で直近7日のいいね上位
  Future<List<ArticleSummary>> fetchPopular({required List<Tag> tags, required int limit});

  /// 本文HTMLと画像URL一覧
  Future<ArticleContent> fetchContent(ArticleSummary summary);
}
```

- 失敗時：そのサイトだけエラー表示し、他サイトは続行する。
- 連続で失敗した場合は「取得できません（仕様変更の可能性）」と表示する。

### 5.2 興味タグとサイトごとのタグ名

- 一覧のタグは、サイトごとの名前を持つ（例：Qiita `AI` ／ Zenn `ai` ／ note `AI`）。
- 自由入力のタグは、Qiita と note にはそのまま、Zenn には小文字化して使う。
- 一覧（初期案。実装時に各サイトで存在を確認）【設計判断】：
  `AI` `LLM` `Python` `JavaScript` `TypeScript` `React` `Next.js` `Flutter` `Kotlin` `Swift` `Go` `Rust` `AWS` `Google Cloud` `Azure` `Docker` `Kubernetes` `セキュリティ` `Linux` `Git` `Godot` `Unity` `個人開発` `初心者`
- 未設定時のランダム2つは、この一覧から「AI」以外を選ぶ。選んだタグは `shared_preferences` に保存し、**定期自動DL（バックグラウンド）は直前の起動で選ばれたタグを使う**【設計判断】。

### 5.3 Qiita（公式 API v2）

- おすすめ（新着）：`GET /api/v2/items?query=tag:A OR tag:B ...&per_page=20&page=N`（新しい順で返る）
  - 【要検証】`OR` でのタグ複数指定が効くか。効かなければタグごとに取得して混ぜる。
- 一括DL（人気）：`query=created:>=YYYY-MM-DD (tag:A OR tag:B ...)` で直近7日分を取得し、端末で `likes_count` 順に並べ上位 **最大20件**。
  - 【要検証】括弧と `likes:>=N` の指定が使えるか。使えれば取得回数を減らせる。
- 一覧レスポンスに `rendered_body`（HTML）と `likes_count` が含まれるため、本文の追加取得は不要。
- **レート制限：認証なしは 1 時間 60 回**。おすすめと一括DLで共有する。**キャッシュやトークン入力などの対策は入れない（ユーザー決定）**。429 の場合は Qiita だけ一時停止し「Qiitaは一時的に取得できません」と表示。

### 5.4 Zenn【要検証】

- おすすめ（新着）：`GET https://zenn.dev/api/articles?topicname={topic}&order=latest&page=N`（タグごと）
- 一括DL（人気）：タグごとに週間の人気順（`order` の値を実際に確認）、または直近7日分を取って `liked_count` 順。全タグ合計で上位 N 件。
- 本文：`GET https://zenn.dev/api/articles/{slug}` の `body_html`（想定）。
- 一覧には本文の冒頭がないため、おすすめのカードはタイトル・絵文字・いいね数・トピックで構成する。

### 5.5 note【要検証】

- ハッシュタグの記事一覧（人気順・新着順）を返す内部 API を使う。**実際のエンドポイントはブラウザの通信を見て確認する**。
- 本文：記事詳細 API の本文 HTML（想定）。
- **有料記事は無料部分だけ**。カードと全文に「有料記事（無料部分のみ）」と表示。
- 2026-09 以降、一部ハッシュタグは「キーワードページ」に置き換わっている。空の結果も想定する。

### 5.6 おすすめの読み込み

1. 現在のタグ（興味タグ、未設定なら AI＋ランダム2つ）と ON のサイトで `fetchLatest` を並列に呼ぶ。
2. 結果を混ぜて投稿日時の新しい順に並べ、URL で重複を除く。
3. 末尾から5枚目を表示したら次のページを読み込む【設計判断：ストックと同じ位置】。
4. DL済み（ストレージにある）記事には「保存済」を表示。
5. 全文はタップ時に `fetchContent` で取得し、メモリ上で表示（ストレージに保存しない）。画像は元のURLから直接表示。

### 5.7 一括DL（入れ替え）の流れ

```
1. 実行のきっかけ（manual / scheduled / swipe）を記録し、batch_runs に行を作る
2. タグを決める（興味タグ、未設定なら AI＋ランダム2つ）
3. サイトごとに fetchPopular（Qiita は min(設定件数, 20)、他は設定件数）
4. 新しいセット = 全サイトの結果。既にストレージにある記事はそのまま残す
5. 持っていない記事を DL：
   - 本文 HTML をサニタイズ（<script>・on* 属性を除去）
   - 画像をダウンロードして src をローカルパスに書き換え（失敗した画像だけ代替表示）
   - articles/{id}/index.html と articles/{id}/img/* に保存
   - 保存するたびにストック末尾へ追加（swipe のときは残りの未閲覧の後ろ）
6. 入れ替え（2.5 の表）
   - 保護（残す）：origin=manual、source=app、いいね済み
   - 未閲覧 → 削除
   - 閲覧済・既読 → 本文と画像を削除し、cache_entries に移す（その前に既存のキャッシュを全削除）
   - swipe のきっかけになった残りの未閲覧 → pending_evict=1。閲覧した時点でキャッシュへ
7. 結果（新規・残した・キャッシュへ・削除）を記録して表示
```

- 並列数はサイトごとに 2、合計 4 程度。
- 「中止」したら 6 を行わない【設計判断】。
- 容量上限を超えたら警告を出すが続行。

### 5.8 定期自動DL

- `workmanager` で 1 日 1 回。設定「Wi-Fi時のみ」が ON なら `NetworkType.unmetered`。
- 処理は 5.7 と同じ（trigger=scheduled）。
- あわせて、期限切れのキャッシュ（24時間）を削除する。

### 5.9 キャッシュの削除タイミング

- 次の入れ替えでキャッシュに新しい記事を追加する直前（既存を全削除）。
- `expires_at`（移動から24時間）を過ぎたもの：アプリ起動時・設定の「DLしたもの」表示時・定期自動DL時に削除。表示時は期限切れを出さない。

---

## 6. 端末側データ設計

### 6.1 保存場所

- 本文・画像：`getApplicationSupportDirectory()/articles/{id}/...`（キャッシュ領域は使わない）。
- メタデータ：SQLite（`drift` 推奨）。
- 設定・興味タグ・ランダムタグ：`shared_preferences`。
- セッショントークン：`flutter_secure_storage`。

### 6.2 テーブル

```sql
-- ストック（ストレージにある記事。外部記事と投稿記事）
CREATE TABLE stock_articles (
  id              TEXT PRIMARY KEY,         -- UUID
  source          TEXT NOT NULL,            -- 'qiita' | 'zenn' | 'note' | 'app'
  source_key      TEXT NOT NULL,            -- 外部: 正規化URL / app: 投稿ID
  url             TEXT,                     -- 外部記事のURL（appはNULL）
  origin          TEXT NOT NULL,            -- 'batch'（一括DL） | 'manual'（個別DL）
  batch_run_id    TEXT,                     -- origin='batch' のとき
  title           TEXT NOT NULL,
  author          TEXT,
  tags_json       TEXT,
  summary         TEXT,                     -- カード用の冒頭(200字程度)
  thumbnail_path  TEXT,
  dir_path        TEXT NOT NULL,            -- articles/{id}
  size_bytes      INTEGER NOT NULL,
  likes_at_fetch  INTEGER,
  is_paid_partial INTEGER DEFAULT 0,        -- note有料記事の無料部分のみ
  published_at    INTEGER,
  downloaded_at   INTEGER NOT NULL,
  viewed_at       INTEGER,                  -- カードを表示した（閲覧済）
  read_at         INTEGER,                  -- 全文を開いた（既読）
  pending_evict   INTEGER DEFAULT 0,        -- 閲覧したらキャッシュへ移す
  app_expires_at  INTEGER,                  -- app投稿のみ：DL時点の期限（表示用）
  UNIQUE (source, source_key)
);

-- キャッシュ（タイトル＋URLのみ。直近1回の入れ替え分、24時間）
CREATE TABLE cache_entries (
  id          TEXT PRIMARY KEY,
  source      TEXT NOT NULL,
  source_key  TEXT NOT NULL,
  url         TEXT NOT NULL,
  title       TEXT NOT NULL,
  cached_at   INTEGER NOT NULL,
  expires_at  INTEGER NOT NULL,             -- cached_at + 24h
  UNIQUE (source, source_key)
);

-- いいね一覧（端末ローカル）
CREATE TABLE liked_items (
  id          TEXT PRIMARY KEY,
  kind        TEXT NOT NULL,                -- 'external' | 'app_post'
  source      TEXT NOT NULL,
  source_key  TEXT NOT NULL,
  url         TEXT,
  title       TEXT NOT NULL,
  liked_at    INTEGER NOT NULL,
  UNIQUE (source, source_key)
);

-- 一括DLの実行記録
CREATE TABLE batch_runs (
  id           TEXT PRIMARY KEY,
  trigger      TEXT NOT NULL,               -- 'manual' | 'scheduled' | 'swipe'
  tags_json    TEXT NOT NULL,
  started_at   INTEGER NOT NULL,
  finished_at  INTEGER,
  status       TEXT NOT NULL,               -- 'running' | 'done' | 'canceled'
  new_count    INTEGER DEFAULT 0,
  kept_count   INTEGER DEFAULT 0,
  cached_count INTEGER DEFAULT 0,
  deleted_count INTEGER DEFAULT 0,
  errors_json  TEXT                         -- サイトごとの失敗理由
);
```

### 6.3 ストックフィードの並びと自動補充

```sql
SELECT * FROM stock_articles
ORDER BY
  CASE WHEN viewed_at IS NULL THEN 0 WHEN read_at IS NULL THEN 1 ELSE 2 END,
  downloaded_at DESC;
```

- フィードはセッション中は並びを固定し、新しく DL した記事は末尾に足す（途中で並びが変わらないように）。
- カードを表示したら `viewed_at` を記録。`pending_evict=1` ならキャッシュへ移す（本文・画像を削除）。
- 表示したカードの後ろの未閲覧が 4 件以下になったら、一括DL（trigger=swipe）を開始（実行中・30分以内に新規0件だった場合を除く）。

### 6.4 いいね一覧の参照先の解決（表示時に毎回判定）

```
liked_items と stock_articles を (source, source_key) で結合
  ├─ ストックにある           → 「端末に保存済み」：ローカルの全文を開く
  ├─ 外部記事でストックにない → 「Web」：アプリ内でオンライン取得して表示（元記事ボタンでブラウザ）
  └─ 投稿でストックにない     → オンライン時に GET /posts/:id
        ├─ 取得できた         → 「公開中」
        └─ 404               → 「公開終了」：タイトルだけ表示
```

- いいね済みの記事は入れ替えで消えないため、キャッシュ化されることはない。

### 6.5 URL の正規化

- クエリ文字列・フラグメントを除去し、末尾スラッシュを統一したものを `source_key` にする。

---

## 7. サーバー設計（Cloudflare）

### 7.1 構成

- Workers（TypeScript + Hono 推奨）
- D1：`techmeku-db`
- R2：`techmeku-images`（非公開バケット。画像は Workers 経由で配信）
- Cron Trigger：`0 * * * *`（毎時）
- Cloudflare Access：`/admin/*` を保護

### 7.2 D1 スキーマ

```sql
CREATE TABLE users (
  id          TEXT PRIMARY KEY,
  sub_hash    TEXT NOT NULL UNIQUE,         -- HMAC-SHA256(Google sub, SERVER_SECRET)
  nickname    TEXT NOT NULL,                -- 1〜20字
  created_at  INTEGER NOT NULL
);

CREATE TABLE bans (                         -- 退会しても残す
  sub_hash    TEXT PRIMARY KEY,
  reason      TEXT,
  created_at  INTEGER NOT NULL
);

CREATE TABLE posts (
  id            TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL,
  title         TEXT NOT NULL,
  body_md       TEXT NOT NULL,
  tags_json     TEXT NOT NULL,
  images_json   TEXT NOT NULL,              -- R2キーの配列（最大3）
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL,
  edited        INTEGER NOT NULL DEFAULT 0,
  expires_at    INTEGER NOT NULL,
  like_count    INTEGER NOT NULL DEFAULT 0,
  comment_count INTEGER NOT NULL DEFAULT 0,
  report_count  INTEGER NOT NULL DEFAULT 0,
  status        TEXT NOT NULL DEFAULT 'active'  -- 'active' | 'hidden'
);
CREATE INDEX idx_posts_expires ON posts(expires_at);
CREATE INDEX idx_posts_user ON posts(user_id, expires_at);
CREATE INDEX idx_posts_created ON posts(created_at);

CREATE TABLE likes (
  post_id     TEXT NOT NULL,
  user_id     TEXT NOT NULL,
  active      INTEGER NOT NULL,             -- 1=いいね中 0=取り消し済み
  created_at  INTEGER NOT NULL,
  PRIMARY KEY (post_id, user_id)            -- 行がある＝延長済み
);

CREATE TABLE comments (
  id            TEXT PRIMARY KEY,
  post_id       TEXT NOT NULL,
  user_id       TEXT NOT NULL,
  body          TEXT NOT NULL,
  created_at    INTEGER NOT NULL,
  report_count  INTEGER NOT NULL DEFAULT 0,
  status        TEXT NOT NULL DEFAULT 'active'
);
CREATE INDEX idx_comments_post ON comments(post_id, created_at);

CREATE TABLE comment_extends (
  post_id  TEXT NOT NULL,
  user_id  TEXT NOT NULL,
  PRIMARY KEY (post_id, user_id)
);

CREATE TABLE reports (
  id           TEXT PRIMARY KEY,
  target_type  TEXT NOT NULL,               -- 'post' | 'comment'
  target_id    TEXT NOT NULL,
  post_id      TEXT NOT NULL,
  reporter_id  TEXT NOT NULL,
  reason       TEXT NOT NULL,               -- 'spam' | 'abuse' | 'sexual' | 'illegal' | 'other'
  created_at   INTEGER NOT NULL,
  UNIQUE (target_type, target_id, reporter_id)
);

CREATE TABLE signup_ip_counts (
  ip_hash  TEXT NOT NULL,
  day      TEXT NOT NULL,                   -- 'YYYY-MM-DD' (UTC)
  count    INTEGER NOT NULL,
  PRIMARY KEY (ip_hash, day)
);
```

- 「公開中」：`status = 'active' AND expires_at > now`。
- 上限判定（5件・100件）は `expires_at > now` の件数（hidden も期限までは枠を使う）。**期限が過ぎた時点で枠が空く**。
- 同時投稿で上限を超えないよう、件数チェックと INSERT を 1 文にする：
  ```sql
  INSERT INTO posts (...)
  SELECT ... WHERE
    (SELECT COUNT(*) FROM posts WHERE expires_at > ?now) < 100
    AND (SELECT COUNT(*) FROM posts WHERE user_id = ?uid AND expires_at > ?now) < 5;
  -- 変更行数が0なら、どちらの上限かを判定してエラーを返す
  ```

### 7.3 認証

1. アプリ：`google_sign_in`（または Credential Manager）で ID トークンを取得（audience は Web クライアントID）。
2. `POST /auth/google { idToken }`
3. Workers：Google の JWKS で署名を検証し、`iss` / `aud` / `exp` を確認。JWKS はキャッシュ。
4. `sub_hash = HMAC-SHA256(sub, SERVER_SECRET)`。
5. `bans` にあれば 403 `BANNED`。
6. 新規なら `signup_ip_counts` を確認し、当日 3 件以上で 429 `SIGNUP_LIMIT`。ニックネームは `ユーザー`＋ランダム4桁。
7. アプリ用セッショントークン：HS256 の JWT `{ uid, exp: 30日 }`。
8. **ID トークン中の email / name / picture は読まない・保存しない・ログに出さない。**

- 書き込み系 API では毎回 `users` の存在と `bans` を確認する。

### 7.4 API 一覧

共通：JSON。認証は `Authorization: Bearer <session>`。エラーは `{ "error": { "code": "...", "message": "..." } }`。

| メソッド | パス | 認証 | 内容 |
|---|---|---|---|
| POST | `/auth/google` | – | ログイン |
| GET | `/me` | 要 | `{ id, nickname, activePostCount }` |
| PATCH | `/me` | 要 | ニックネーム変更 |
| DELETE | `/me` | 要 | 退会（投稿・コメント・いいね・画像を即削除） |
| GET | `/status` | – | `{ activeCount, limit: 100, nextFreeAt }` |
| GET | `/posts` | 任意 | 公開中の一覧（新着順、冒頭のみ、最大100件）。ログイン時は `likedByMe` 付き。通報済みは本人に返さない |
| GET | `/posts/mine` | 要 | 自分の公開中投稿 |
| GET | `/posts/:id` | 任意 | 本文込み。公開終了なら 404 |
| POST | `/posts` | 要 | multipart（JSON＋画像最大3枚）。上限超過は 409 |
| PATCH | `/posts/:id` | 要・本人 | 編集（期限は変えない、`edited=1`） |
| DELETE | `/posts/:id` | 要・本人 | 削除（R2画像も） |
| POST | `/posts/:id/like` | 要 | いいね（初回のみ延長） |
| DELETE | `/posts/:id/like` | 要 | 取り消し（延長は戻さない） |
| GET | `/posts/:id/comments` | 任意 | 一覧（古い順） |
| POST | `/posts/:id/comments` | 要 | 投稿（50件・200字。初回のみ延長） |
| DELETE | `/comments/:id` | 要 | 本人または投稿者のみ |
| POST | `/reports` | 要 | `{ targetType, targetId, reason }` |
| GET | `/images/:key` | – | R2 から配信。公開終了なら 404 |

主なエラーコード：

| code | HTTP | 意味 | アプリ表示 |
|---|---|---|---|
| `POST_LIMIT_USER` | 409 | 自分の公開中が5件 | 「公開中の投稿が5件あります。最短で HH:MM 後に投稿できます」 |
| `POST_LIMIT_GLOBAL` | 409 | 全体100件 | 「現在満員です。次に空く予定：HH:MM」 |
| `COMMENT_LIMIT` | 409 | コメント50件 | 「この投稿はコメント上限に達しました」 |
| `SELF_LIKE` | 400 | 自分の投稿へのいいね | ボタンを無効化しておく |
| `POST_GONE` | 404 | 公開終了・削除済み | 「この投稿は公開終了しました」 |
| `BANNED` | 403 | 停止中 | 「このアカウントは利用停止されています」 |
| `SIGNUP_LIMIT` | 429 | IPごとの作成上限 | 「本日はこれ以上アカウントを作成できません」 |
| `VALIDATION` | 400 | 文字数・枚数超過など | 項目ごとに表示 |

### 7.5 延長処理

```ts
const DAY = 24 * 60 * 60 * 1000;
function extend(post, now) {
  const cap = post.created_at + 7 * DAY;
  return Math.max(post.expires_at, Math.min(now + DAY, cap));
}
```

- いいね：`likes` に行がなければ INSERT して延長。`active=0` の行があれば `active=1` に戻すだけ。
- コメント：投稿者本人でなく、`comment_extends` に行がなければ INSERT して延長。
- 公開終了の投稿への操作は `POST_GONE`。

### 7.6 通報処理

- `reports` に INSERT（重複は無視）→ `report_count += 1` → 3 以上で `status='hidden'`。
- 通報者本人には通報済みの対象を返さない。

### 7.7 Cron（毎時）

1. `expires_at <= now` の投稿を取得。
2. R2 の画像を削除。
3. `comments` / `likes` / `comment_extends` / `reports` を削除 → `posts` を削除。
4. `signup_ip_counts` の前日以前を削除。

### 7.8 画像

- 端末側で長辺 1280px・JPEG/WebP・1 枚 500KB 以下に圧縮してからアップロード。
- サーバー側でも Content-Type とサイズを検証。
- 本文中は `![](attachment:1)`〜`attachment:3` で参照【設計判断】。表示時に `/images/:key` へ置換。

### 7.9 管理用Webページ（/admin）

- Cloudflare Access で保護。Workers 側でも `Cf-Access-Jwt-Assertion` を検証。
- 通報一覧、非表示の投稿・コメント、削除・復帰、アカウント停止と解除。素の HTML＋少量の JS。

### 7.10 シークレット・環境変数

| 名前 | 用途 |
|---|---|
| `GOOGLE_CLIENT_ID` | ID トークンの aud 検証 |
| `SERVER_SECRET` | sub のハッシュ化 |
| `SESSION_SECRET` | セッション JWT の署名 |
| `IP_SALT_SECRET` | IP ハッシュ用ソルト |
| `ACCESS_AUD` / `ACCESS_TEAM_DOMAIN` | Cloudflare Access の JWT 検証 |

---

## 8. Flutter 設計

### 8.1 主なパッケージ（推奨）

| 用途 | パッケージ |
|---|---|
| 状態管理 | `flutter_riverpod` |
| ルーティング | `go_router` |
| ローカルDB | `drift` |
| HTTP | `dio` |
| 全文表示 | `webview_flutter`（同梱 CSS・コードハイライト） |
| Markdown→HTML | `markdown` |
| 定期DL | `workmanager` |
| 通信状態 | `connectivity_plus` |
| ログイン | `google_sign_in` |
| 秘密情報 | `flutter_secure_storage` |
| 共有・外部ブラウザ | `share_plus` / `url_launcher` |
| SVGアイコン | `flutter_svg`（Icon Kit 用） |
| 画像選択・圧縮 | `image_picker` / `flutter_image_compress` |
| パス | `path_provider` |
| アイコン生成 | `flutter_launcher_icons` |

### 8.2 ディレクトリ構成（例）

```
app/
  assets/brand/   (techmeku_icon_original/1024/512/192.png)  ← Icon Kit からコピー
  assets/icons/   (default/ active/ muted/ の SVG)          ← Icon Kit からコピー
  lib/
    main.dart
    core/        (api_client, db, storage, connectivity, theme, techmeku_icon.dart)
    features/
      home/      (recommend_feed, stock_feed, posts_feed, article_card, action_rail, status_card)
      reader/    (article_viewer, html_template, online_loader)
      download/  (sources/qiita, sources/zenn, sources/note, batch_runner, replacer, scheduler)
      tags/      (interest_tags, preset_tags, random_tags)
      profile/   (profile, my_stock, liked_list, reference_resolver)
      posts/     (my_posts, editor, comments, report)
      auth/      (google_login, session)
      settings/  (settings, downloaded_list)
server/
  src/ index.ts auth.ts posts.ts likes.ts comments.ts reports.ts images.ts admin.ts cron.ts
  migrations/0001_init.sql
  wrangler.toml
docs/
  design.md  wireframes.html  ICON_USAGE.md  ICON_PREVIEW.png
```

### 8.3 フィード実装メモ

- `PageView(scrollDirection: Axis.vertical)` で 1 画面 1 カード。3タブは横の `TabBarView`。
- カード内はスクロールさせない（全文はタップで S04）。
- 右側アクションは 44dp 以上。アクションのタップがページ送りに奪われないようにする。
- 前後 2 枚を先読み（サムネイル）。

### 8.4 全文表示

- ストック：保存済み `index.html` を同梱 CSS で表示。
- おすすめ・キャッシュ・いいね（Web）：`fetchContent` の HTML をサニタイズして同じテンプレートで表示（保存しない）。
- 投稿記事：`body_md` → `markdown` で HTML 化。
- リンクは外部ブラウザで開く。WebView の JavaScript は無効（ハイライトは保存時に適用、または同梱 JS のみ）。

### 8.5 アプリアイコン・ブランド

- 素材：`assets/brand/techmeku_icon_original.png` / `_1024` / `_512` / `_192`（Icon Kit 同梱）。ランチャーアイコンは `flutter_launcher_icons` で `_1024` から生成。
- 原画は紺の角丸背景込み。Android のアダプティブアイコンにすると角丸が二重になるため、**前景（Tのマーク）と背景色（紺）に分けて作り直す**【設計判断】。分けられない場合はレガシーアイコンのみで出す。
- Qiita / Zenn / note のロゴは使わない（ライセンス配慮）。出典はサイト名のテキストで表示する。

### 8.6 UIアイコン（TechMeku Icon Kit）

- 62種 × 3色（default / active / muted）の SVG。24×24、背景透明、丸背景なし。
- 導入：`assets/icons/` と `assets/brand/` をコピー → `pubspec.yaml` に `flutter_svg` とアセットを登録 → `lib/techmeku_icon.dart` の `TechMekuIcon` を使う。右側アクションは `lib/example_action_rail.dart` を土台にする。
- タップ領域（44dp 以上）と丸背景は Flutter 側の `InkWell` / `Container` で作る。ステータスバー・Wi-Fi などの OS アイコンはシステムに任せる。
- 塗りあり：`heart_filled`（いいね済み）、`bookmark_filled`（保存済み）。

**デザイントークン**

| 用途 | ダーク（Icon Kit の値） | ライト【設計判断】 |
|---|---|---|
| 背景 | `#0B0F14` | `#FFFFFF` |
| カード | `#111827` | `#F3F4F6` |
| 通常（default） | `#E5E7EB` | `#111827` |
| 選択中（active） | `#06B6D4` | `#0891B2`（白背景でのコントラスト確保） |
| 非強調（muted） | `#9CA3AF` | `#6B7280` |
| 警告・エラー | Flutter 側のバッジで指定 | 同左 |

- **注意**：Icon Kit の SVG は色が固定（ダーク背景向け）。設定でライトテーマを選べるため、`TechMekuIcon` を **default の SVG を読み込み、`ColorFilter.mode(テーマ色, BlendMode.srcIn)` で着色する方式**に変更する【設計判断】。active / muted のファイルはダークテーマの見本として残す。

**画面とアイコンの対応（ICON_USAGE.md を v2.2 の仕様に合わせて整理）**

| 画面 | アイコン |
|---|---|
| ボトムナビ | ホーム `home` ／ 自分の投稿 `file_text` ／ 新規投稿 `plus_square` ／ プロフィール `user` ／ 設定 `settings` |
| ホームのタブ | おすすめ `layers` ／ ストック `bookmark` ／ みんなの投稿 `users` |
| 右側アクション | いいね `heart`→`heart_filled` ／ コメント `comment`（投稿のみ） ／ DL `download`→保存済 `check_circle` ／ 共有 `share` ／ 元記事 `external_link`（外部記事のみ） ／ 通報 `flag`（投稿のみ） |
| S01 おすすめ | 上記＋タグ切替 `tag`、スワイプ案内 `arrow_up` |
| S02 ストック | 上記＋一括DL `download`、オフラインで読める表示 `smartphone` |
| S03 みんなの投稿 | 上記＋残り時間 `clock`、自分の投稿のメニュー `more` |
| S04 全文 | 戻る `back`、表示設定 `sliders`、下部に いいね・DL・共有・元記事（投稿は コメント） |
| S05 状態カード | 取得中 `loader`、オフライン `cloud_off`、再試行 `refresh` |
| S06 一括DL | `download` `loader` `check_circle` `warning` `refresh` `database` `close` |
| S07 興味タグ | `tag` `check` `plus` `minus` `close` |
| S08 プロフィール：ストック | アバター `user`、編集 `edit`、タブ `library` |
| S09 自分の投稿 | `file_text` `plus_square` `edit` `trash` `clock` `heart` `comment` |
| S10 プロフィール：いいね | タブ `heart_filled`、行 `chevron_right`、公開終了 `clock` |
| S11 エディタ | `close` `edit` `check` `tag` `code`（編集） `preview` `image` `upload` |
| S12 コメント | `comment` `send` `more` `flag` `trash` `close` |
| S13 ログイン | `back` `log_in` `shield` |
| S14 設定 | `settings` `tag` `download` `refresh` `wifi` `database` `sliders` `user` `log_out` |
| S15 DLしたもの | `database` `back` `trash` `external_link`（キャッシュ） `filter` |
| S16 ダイアログ | `info` `warning` `flag` `alert_octagon` `check` `close` |
| A01 管理 | `shield` `flag` `trash` `rotate_ccw` `user_x` `search` `filter` |

- Icon Kit の対応表にある S01 の `search`（検索）は、アプリ内検索の機能が仕様にないため **アプリでは使わない**（管理ページの検索のみ）。
- `eye` / `eye_off` / `book_open`（閲覧済・未閲覧・既読）は、S15 の状態表示に使ってよい。

---

## 9. 実装ステップ（推奨順）

1. **外部記事取得の検証**：Qiita / Zenn / note の API を実際に叩き、5章の【要検証】を確定（レスポンス例を `docs/api-samples/` に保存）。
2. Flutter 雛形＋ローカル DB＋ストレージ保存。Icon Kit の導入（8.5・8.6）とテーマ。
3. Qiita の一括DL → ストックフィード（S02）→ 全文表示（S04）。
4. 入れ替え（5.7）、閲覧状態、自動補充（6.3）、状態カード（S05）、キャッシュ（5.9）。
5. Zenn・note アダプタ、画像保存、容量警告、定期自動DL。
6. 興味タグ（S07）とおすすめ（S01）。
7. プロフィール（S08・S10）・いいねの参照先解決・設定の DLしたもの一覧（S15）。
8. Workers ＋ D1 ＋ R2、Google 認証。
9. 投稿 CRUD・上限判定・延長・Cron、みんなの投稿（S03）・自分の投稿（S09）・エディタ（S11）・コメント（S12）。
10. 通報・管理ページ・停止・退会。設定（S14）、利用規約、Play 公開準備。

### 9.1 テストすべき境界条件

- 未閲覧 6 件のストックで 2 枚スワイプ → 2 枚目の表示で自動補充が始まる。
- 自動補充中も残り 4 件は消えず、表示した後にキャッシュへ移る。
- 入れ替えで、個別DL・いいね済み・投稿記事が残る。未閲覧は消え、閲覧済・既読はキャッシュになる。
- 新しいセットに含まれる既存記事は再DLされず、閲覧状態も保たれる。
- note の取得に失敗しても、note の古い一括DL分も入れ替えられる。
- キャッシュは 24 時間で消える。次の入れ替えで、前回のキャッシュはすべて消える。
- 起動時にオフライン → ストックタブが開く。
- 興味タグ未設定 → 起動ごとに「AI＋2つ」が変わり、定期自動DLは直前の起動のタグを使う。
- Qiita の一括DL は設定 50 でも 20 件まで。
- 公開中 99 件で 2 人が同時に投稿 → 1 件だけ成功。
- 自分の投稿 5 件のうち 1 件の期限が切れた直後（Cron 前）に投稿できる。
- いいね → 取り消し → 再いいねで期限が延びない。
- 投稿から 6 日 23 時間後のいいね → 期限は 7 日で止まる。
- 自分の投稿へのコメントで延長されない。
- 外部記事にいいね → DL → いいね一覧が「端末に保存済み」→ ストックから削除 → 「Web」に戻る。
- 停止されたユーザーが退会 → 同じ Google アカウントで再登録できない。

---

## 10. リスク・注意事項

- **Zenn / note の非公式 API** は予告なく変わる。アダプタ単位で無効化でき、アプリ全体が落ちないようにする。
- **著作権・利用規約**：端末で取得してサーバーに置かないことだけで適法性が保証されるわけではない。各サイトの規約と画像保存の条件は実装前と公開前に確認する。ストア掲載文に「記事の著作権は各執筆者に帰属」と明記する。
- **Qiita のレート制限（認証なし 60回/時）**：おすすめ・一括DL・自動補充で共有し、対策は入れない（ユーザー決定）。上限に達すると Qiita だけ一時的に取得できなくなる。
- **モバイル通信**：自動補充は通信の種類に関わらず実行するため、画像込みで数百MBの通信になることがある。初回実行時に一度だけ案内を出すことを推奨【設計判断】。
- **D1 無料枠の超過は当日中エラー**：一覧 API は本文を返さない、インデックスを張る。
- **Google Play の UGC ポリシー**：利用規約への同意、通報、違反ユーザーへの対処（停止）を備えている。審査時は最新のポリシーを確認する。
- **名称**：TechMeku は簡易検索では同名アプリが見当たらなかったが、商標は未確認。技術ニュースサイト「Techmeme」と響きが近い。公開前に商標・ストア名・ドメインを確認する。

---

## 11. 設計判断の一覧（ユーザー未確認・変更可）

| # | 内容 |
|---|---|
| 1 | 投稿記事の共有は「タイトル＋本文冒頭」のテキスト |
| 2 | 投稿本文の画像は `![](attachment:N)` で配置 |
| 3 | 初回投稿前に利用規約への同意。設定に規約・ポリシー・ライセンス |
| 4 | オフライン時、投稿記事へのいいね・コメントは無効化（送信待ちにしない） |
| 5 | 通報理由は 5 種類（スパム・誹謗中傷・性的・違法・その他） |
| 6 | ニックネームの初期値は「ユーザー＋ランダム4桁」、1〜20 字。セッション 30 日 |
| 7 | 手動の一括DLを中止したら入れ替えをしない |
| 8 | 未閲覧が最初から5件未満なら、ストックの最初のカード表示で自動補充 |
| 9 | 自動補充で新規0件なら30分は再実行しない |
| 10 | 定期自動DLは直前の起動で選ばれたランダムタグを使う |
| 11 | 興味タグの一覧（5.2 の24個） |
| 12 | おすすめの続きの読み込みは末尾から5枚目で開始 |
| 13 | ＋新規投稿は投稿エディタを直接開き、上部に n/5・n/100 を表示 |
| 14 | アダプティブアイコン用に前景と背景を分ける |
| 15 | 自動補充の初回にモバイル通信量の案内を一度出す |
| 16 | ライトテーマのトークンと、アイコンをテーマ色で着色する方式（8.6） |

---

## 12. ChatGPT案の取り込み記録

ChatGPT の改訂案（2026-11-04）は **内容だけ** を取り込み、見た目は v1 のワイヤーフレームの方針を維持した。

| ChatGPT案 | 扱い |
|---|---|
| 名称 TechMeku・キャッチコピー | 採用 |
| おすすめタブ | 採用（内容は「興味タグの新着記事」にユーザーが変更） |
| 興味タグ | 採用（おすすめ＋一括DLの絞り込み、最大10個） |
| ストックカードの「オフラインで読めます」・件数・容量・前回更新の表示 | 採用（S02） |
| 投稿カード・投稿画面での残り時間と延長ルールの説明 | 採用（S03・S11） |
| 一括DLのサイト別の進捗・部分失敗の表示 | 採用（S06。v1 から継続） |
| 右側縦並びアクション・44dp以上・スワイプと干渉しない | 採用（2.1・8.3） |
| 著作権は「サーバーに置かない」だけでは保証されない | 採用（10章） |
| AI要点タブ | **不採用** |
| 関連技術（GitHub等） | **不採用** |
| 濃紺グラデーションの見た目 | 不採用（ワイヤーフレームは v1 の方針。ブランド色はアイコンから採る） |
