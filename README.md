# RemoteDev

iOS 26 **Liquid Glass** デザインのチャットクライアント。OpenCode Go を介して **DeepSeek V4 Flash** と会話することを目指すテストアプリ。

GitHub Actions で署名無し IPA を自動ビルドし、LiveContainer / SideStore / AltStore からインストールできます。

## 現在の機能（テスト版）

- 純正メッセージアプリ風の会話リスト + チャットスレッド（Liquid Glass の吹き出し）
- モデル: DeepSeek V4 Flash（デフォルト）
- API キー設定画面（端末内のみに保存）
- 返信はテスト用の仮応答。実 API 接続は次フェーズ

## インストール

### LiveContainer

LiveContainer のソース追加画面で以下を登録:

```text
livecontainer://source?url=aHR0cHM6Ly9uZXp1bWkwNjI3LmdpdGh1Yi5pby9SZW1vdGVEZXYvYXBwcy5qc29u
```

### SideStore / AltStore

```text
https://nezumi0627.github.io/RemoteDev/apps.json
```

リリースごとに GitHub Releases から直接 IPA をダウンロードすることもできます。

## GitHub Pages の設定（初回のみ）

1. リポジトリの Settings → Pages を開く
2. **Deploy from a branch** を選択
3. Branch: `main`、ディレクトリ: `/docs` を指定して保存

## 新しいビルドを出す方法

`remote-dev-app/Version.xcconfig` の `MARKETING_VERSION` か `CURRENT_PROJECT_VERSION` を変更して push するだけ。バージョンが変わったときのみ macOS ランナーが起動します（未変更ならスキップ）。手動実行は Actions タブの **workflow_dispatch** から。

## セキュリティ

- **API キーはリポジトリにコミットしないこと。** アプリは設定画面で入力したキーを端末の `UserDefaults` にのみ保存します。
- チャットなど第三者に見える場所にキーを貼ると漏洩します。貼ってしまった場合は OpenCode Go 側でキーを失効・再発行してください。

## ロードマップ

- [ ] OpenCode Go API への実接続（設定画面のキーを使用）
- [ ] エージェント駆動（Claude Desktop 風のタスク実行表示）
- [ ] 将来: PC 側の OpenCode との会話同期

## 構成

```
.github/workflows/build-unsigned-ipa.yml   # 署名無し IPA ビルド (最適化版)
remote-dev-app/                             # Xcode プロジェクト
  RemoteDev.xcodeproj/
  RemoteDev/                                # Swift ソース
docs/                                       # GitHub Pages (apps.json, index.html)
scripts/update_apps_json.py                 # apps.json 更新スクリプト
```
