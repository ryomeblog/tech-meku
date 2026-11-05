# 外部 API の検証結果（設計書 5 章の【要検証】）

検証日：2026-11-04。実装は `app/lib/sources/` にある。

## Qiita（公式 API v2）

| 項目 | 結果 |
|---|---|
| `query=tag:A OR tag:B` | 効く。新しい順で返る → おすすめ（新着）は 1 リクエストで複数タグ |
| `query=created:>=YYYY-MM-DD (tag:A OR tag:B)` | **0 件**（括弧が効かない） |
| `query=tag:A created:>=YYYY-MM-DD` | 効く → 人気（一括DL）はタグごとに直近7日を `per_page=100` で取り、端末で `likes_count` 順に上位20件 |
| 本文 | 一覧の `rendered_body`（HTML）をそのまま使う。追加取得なし |
| レート制限 | 認証なし 60 回/時。429 なら Qiita だけ 1 時間停止し「Qiitaは一時的に取得できません」 |

## Zenn（非公式）

| 項目 | 結果 |
|---|---|
| 新着 | `GET /api/articles?topicname={topic}&order=latest&page=N`。`articles`・`next_page` |
| 人気 | `order=weekly` が直近1週間の人気順（`daily`・`liked_count` は新着とほぼ同じ、`alltime` は全期間） |
| 本文 | `GET /api/articles/{slug}` の `article.body_html` |
| カード | 一覧に本文の冒頭はない → タイトル・絵文字・いいね数・トピック |

## note（内部 API）

| 項目 | 結果 |
|---|---|
| 一覧 | `GET /api/v3/hashtags/{tag}/notes?order=new|popular&page=N`。`data.notes`・`data.is_last_page`。1 ページ 50 件 |
| 人気 | `order=popular` は直近7日に限らない → 新着を最大3ページ取り、直近7日を `like_count` 順 |
| 本文 | `GET /api/v3/notes/{key}` の `data.body`（HTML）。アイキャッチは `data.eyecatch` |
| 有料記事 | `price > 0`。本文は無料部分のみ →「有料記事（無料部分のみ）」と表示 |
| URL | `https://note.com/{user.urlname}/n/{key}` |
| 注意 | `type` が `TextNote` 以外（画像・音声など）は除外。空のハッシュタグもある |

## GIGAZINE（RSS ＋ 記事ページ）

検証日：2026-11-05

| 項目 | 結果 |
|---|---|
| 一覧 | `GET https://gigazine.net/news/rss_2.0/`。最新30件。`title`・`link`・`description`（要約＋「続きを読む」）・`dc:subject`（カテゴリ、カンマ区切り）・`dc:date` |
| ページ送り | なし。一覧ページ（`/news/P40/` など）は robots.txt で禁止 |
| タグ・人気 | タグはなくカテゴリだけ（AI、ソフトウェア、ハードウェア、セキュリティ、ゲーム、サイエンス、取材など）。いいね数のような指標はない |
| 本文 | 記事ページ `https://gigazine.net/news/YYYYMMDD-slug/` の `<div class="cntimage">` から `<!-- google_ad_section_end` まで。先頭に `h1.title`・`time`・カテゴリがある |
| 画像 | `i.gzn.jp`。先頭数枚は `src`、残りは遅延読み込みで `data-src` |
| robots.txt | 全クローラー向けに `Crawl-delay: 100`。記事ページ（`/news/日付-名前/`）は禁止されていない |
| 利用規約 | 記事の転載条件を定めたページは見つからない。コミュニティ利用規約では知的財産権は同社に帰属 |
