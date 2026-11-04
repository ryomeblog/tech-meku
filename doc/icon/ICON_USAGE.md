# TechMeku アイコン素材・画面対応表

合計 **62種類 × 3色 = 186個の独立SVG**。背景は透明。ベクター画像のため解像度を問わず利用できます。

## デザイントークン

- 背景: `#0B0F14`
- カード: `#111827`
- default: `#E5E7EB`（通常）
- active: `#06B6D4`（選択中）
- muted: `#9CA3AF`（非強調）
- 警告やエラーの色はFlutter側のバッジ等で指定してください。

## 画面別アイコン

| 画面 | 使用アイコン（ファイル名） |
|---|---|
| S01 おすすめ | `heart.svg`, `heart_filled.svg`, `download.svg`, `check_circle.svg`, `share.svg`, `external_link.svg`, `tag.svg`, `filter.svg`, `search.svg`, `more.svg` |
| S02 ストック | `heart.svg`, `heart_filled.svg`, `check_circle.svg`, `share.svg`, `external_link.svg`, `download.svg`, `wifi_off.svg`, `refresh.svg`, `filter.svg` |
| S03 みんなの投稿 | `heart.svg`, `heart_filled.svg`, `comment.svg`, `download.svg`, `share.svg`, `flag.svg`, `clock.svg`, `more.svg` |
| S04 記事全文 | `back.svg`, `close.svg`, `book_open.svg`, `download.svg`, `heart.svg`, `share.svg`, `external_link.svg`, `sliders.svg` |
| S05 ストック末尾 | `loader.svg`, `wifi_off.svg`, `cloud_off.svg`, `refresh.svg` |
| S06 一括DL | `download.svg`, `loader.svg`, `check_circle.svg`, `warning.svg`, `database.svg`, `close.svg` |
| S07 興味タグ選択 | `tag.svg`, `plus.svg`, `minus.svg`, `check.svg`, `search.svg`, `close.svg` |
| S08 プロフィール/ストック | `user.svg`, `library.svg`, `bookmark.svg`, `download.svg`, `edit.svg`, `chevron_right.svg` |
| S09 自分の投稿 | `file_text.svg`, `plus_square.svg`, `edit.svg`, `trash.svg`, `clock.svg`, `heart.svg`, `comment.svg` |
| S10 プロフィール/いいね | `user.svg`, `heart.svg`, `heart_filled.svg`, `bookmark.svg`, `external_link.svg`, `clock.svg` |
| S11 投稿エディタ | `edit.svg`, `image.svg`, `upload.svg`, `code.svg`, `preview.svg`, `check.svg`, `close.svg`, `tag.svg` |
| S12 コメントシート | `comment.svg`, `send.svg`, `trash.svg`, `flag.svg`, `close.svg` |
| S13 ログイン | `log_in.svg`, `lock.svg`, `shield.svg`, `back.svg` |
| S14 設定 | `settings.svg`, `tag.svg`, `download.svg`, `refresh.svg`, `wifi.svg`, `database.svg`, `sliders.svg`, `user.svg`, `log_out.svg` |
| S15 DLしたもの | `database.svg`, `library.svg`, `filter.svg`, `trash.svg`, `external_link.svg`, `chevron_right.svg` |
| S16 ダイアログ | `info.svg`, `warning.svg`, `check.svg`, `close.svg`, `alert_octagon.svg` |
| A01 管理Web | `shield.svg`, `flag.svg`, `trash.svg`, `rotate_ccw.svg`, `user_x.svg`, `search.svg`, `filter.svg` |
| 共通 / 下部ナビ | `home.svg`, `file_text.svg`, `plus_square.svg`, `user.svg`, `settings.svg`, `layers.svg`, `bookmark.svg`, `users.svg` |

## 重要な実装注意

- **右側アクションレールを残す**：S01〜S03でいいね / コメント（投稿のみ） / DL / 共有 / 元記事（外部記事のみ） / 通報（投稿のみ）。
- SVG内に丸背景を含めていません。ボタンの44dp以上のタップ領域と背景はFlutter側のContainer/InkWellで作成してください。
- `heart_filled.svg`（選択時）、`bookmark_filled.svg`（保存時）は塗りあり。
- Qiita/Zenn/noteのブランドロゴはライセンスとブランドガイドラインに配慮し本セットに含めません。出典はサイト名テキストで表示可能です。
- ステータスバー/Wi-FiのOSアイコンはシステムに任せてください。
- FlutterのMaterial Iconsに置き換える必要はありません。すべて独立SVGです。

## Flutter導入

1. `assets/icons` と `assets/brand` を Flutter プロジェクトにコピー
2. `pubspec.yaml` に `flutter_svg` と `assets/icons/` を登録
3. `lib/techmeku_icon.dart` をコピーし `TechMekuIcon` を使用

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
TechMekuIcon(name: TechMekuIconName.download, size: 28)
```

バージョン指定は使用するFlutter SDKとの互換性に合わせて調整してください。

## 一覧

| ファイル名 | 用途 |
|---|---|
| `home.svg` | 下部ナビ：ホーム |
| `file_text.svg` | 下部ナビ：自分の投稿 |
| `plus_square.svg` | 下部ナビ：新規投稿 |
| `user.svg` | 下部ナビ：プロフィール |
| `settings.svg` | 下部ナビ：設定 |
| `layers.svg` | おすすめタブ |
| `bookmark.svg` | ストック/未保存 |
| `bookmark_filled.svg` | ストック/保存済 |
| `users.svg` | みんなの投稿タブ |
| `heart.svg` | 右側：いいね（未選択） |
| `heart_filled.svg` | 右側：いいね（選択済） |
| `comment.svg` | 右側：コメント |
| `download.svg` | 右側：記事DL/一括DL |
| `check_circle.svg` | 右側：保存済/完了 |
| `share.svg` | 右側：共有 |
| `external_link.svg` | 右側：元記事 |
| `flag.svg` | 右側：通報 |
| `search.svg` | 上部：検索 |
| `more.svg` | 共通：その他 |
| `back.svg` | 共通：戻る |
| `close.svg` | 共通：閉じる |
| `check.svg` | 共通：決定/適用 |
| `edit.svg` | 投稿管理：編集 |
| `trash.svg` | 投稿管理：削除 |
| `filter.svg` | 一覧：絞り込み |
| `sliders.svg` | 設定：表示・取得の条件 |
| `calendar.svg` | 記事：投稿日 |
| `tag.svg` | 記事：タグ |
| `eye.svg` | 記事：閲覧済 |
| `eye_off.svg` | 記事：未閲覧 |
| `book_open.svg` | 記事：全文既読 |
| `library.svg` | プロフィール：自分のストック |
| `database.svg` | DLしたもの/保存容量 |
| `refresh.svg` | 自動DL/再試行 |
| `wifi.svg` | オンライン |
| `wifi_off.svg` | オフライン |
| `loader.svg` | 取得中 |
| `info.svg` | 情報 |
| `warning.svg` | 警告/容量超過 |
| `clock.svg` | 投稿：残り公開時間 |
| `plus.svg` | タグ追加/新規 |
| `minus.svg` | タグ解除 |
| `chevron_down.svg` | ドロップダウン |
| `chevron_right.svg` | 一覧：詳細へ |
| `upload.svg` | 投稿：画像添付 |
| `image.svg` | 投稿：添付画像/記事画像 |
| `code.svg` | 投稿：Markdown/コード |
| `preview.svg` | 投稿：プレビュー |
| `send.svg` | コメント送信 |
| `log_in.svg` | ログイン |
| `log_out.svg` | ログアウト |
| `shield.svg` | 管理：認証/安全 |
| `user_x.svg` | 管理：アカウント停止 |
| `rotate_ccw.svg` | 管理：復帰 |
| `lock.svg` | 管理/ログイン：保護 |
| `smartphone.svg` | 端末保存の状態 |
| `cloud_off.svg` | オフライン状態カード |
| `alert_octagon.svg` | 通報対応/エラー |
| `help.svg` | ヘルプ/詳細説明 |
| `list.svg` | 投稿一覧/管理一覧 |
| `arrow_up.svg` | 上スワイプ案内 |
| `file_check.svg` | 投稿確認・保存済ファイル |
