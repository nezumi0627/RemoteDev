# RemoteDev

iOS 26 **Liquid Glass** デザインのチャットクライアント。[OpenCode Zen](https://opencode.ai) を介して **DeepSeek V4 Flash** と会話し、画像を生成します。PC の Claude Code と WiFi 経由で同期できます。

GitHub Actions で署名無し IPA を自動ビルドし、LiveContainer / SideStore / AltStore からインストールできます。

## 機能

- **チャット**: OpenCode Go と SSE ストリーミング会話（Telegram 風ポップ背景）。**コピー / リプライ / 編集 / 再送信 / 再生成**、メッセージ下に**モデル名と回答速度**を表示
- **画像添付**: 写真を選択して送信（そのターンのみ **mimo** が画像を読み取る。乱用防止のため画像があるときだけ）
- **画像生成**: Pollinations（無料・キー不要）で生成・写真ライブラリへ保存
- **PC同期**: Claude Code の会話を**引き継ぎ**、**進捗**を確認、**スキル**と**MCP サーバ**を閲覧。**QR を読み取るだけでペアリング**して次回以降は自動接続
- **設定**: API キー / ベース URL / モデル / PC 接続 + **API キー動作テスト**ボタン

### モデル

- チャット: `deepseek-v4-flash`（デフォルト。チャット上部のメニューから `deepseek-v4-pro` / `glm-5.2` / `kimi-k3` 等に切替可）
- 画像読取: `mimo-v2.5`（画像を添付したターンだけ自動で使用）
- 画像生成: `flux`（Pollinations、設定で変更可）
- API ベース URL: `https://opencode.ai/zen/go/v1`（OpenAI 互換 /chat/completions。Go は text のみで画像出力非対応のため、生成は Pollinations）

## PC コンパニオン（会話の引き継ぎ・進捗・スキル・MCP）

iOS アプリの **PC同期** タブから、PC 上で動く Claude Code の状態を確認できます。

```bash
cd pc-server
python server.py        # 起動（Python 3 のみ、追加インストール不要）
```

起動すると **ペアリング QR（pair.png）が開きます**。iOS の **PC同期** タブで QR を読み取るだけで自動接続され、次回以降は手動設定なしで接続します（IP:ポートは端末に保存されます）。QR が読めない場合や手動で設定する場合は、iOS の **設定 > PC コンパニオン** に `IP:ポート` を入力してください。同じ WiFi に接続する必要があります。

提供エンドポイント（`http://<PC-IP>:8000/api/...`）:
- `conversations` — Claude Code の会話一覧
- `transcript?id=<path>` — 会話の中身（iOS から「引き継ぐ」でチャットに読み込み）
- `progress` — 現在進行中のセッションの最新状況
- `skills` / `skill?name=<dir>` — `~/.claude/skills` のスキル
- `mcp` — MCP サーバ設定一覧

> 注: `~/.claude/projects/*/*.jsonl`（Claude Code のセッション記録）を読み取ります。GUI の Claude Desktop アプリの会話 DB は対象外です。

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

- [x] OpenCode Zen API への実接続（ストリーミングチャット + 画像生成）
- [x] Claude Code の会話引き継ぎ / 進捗 / スキル / MCP 同期（PC コンパニオン）
- [ ] エージェント駆動（iOS から PC の Claude Code にプロンプト送信）
- [ ] API キーの Keychain 保存

## 構成

```
.github/workflows/build-unsigned-ipa.yml   # 署名無し IPA ビルド (最適化版)
remote-dev-app/                             # Xcode プロジェクト
  RemoteDev.xcodeproj/
  RemoteDev/                                # Swift ソース
pc-server/                                  # PC コンパニオン (Python 標準ライブラリのみ)
docs/                                       # GitHub Pages (apps.json, index.html)
scripts/update_apps_json.py                 # apps.json 更新スクリプト
```
