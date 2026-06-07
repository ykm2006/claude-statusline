# Claude Code Statusline

Claude Code のステータスラインにコンテキスト使用量・バーンレート・推定残り時間などをリアルタイム表示するスクリプト。

Based on: [Claude Code で常時コンテキスト使用量を把握できるようにしてみた (DevelopersIO)](https://dev.classmethod.jp/articles/less-than-greater-than-claude-code/)

## 表示例

```
🤖 Opus 4.8 │ 📊 112.0k/200.0k █████░░░░░ 56% 🟡 Caution │ ⬇2.1k ⚡108.3k ⬆1.5k │ 💡残88.0k │ ⏳~35min │ 🔄0回
🔥 3.2k/min │ 🕐 Daily:290.4k  🗓 Weekly:290.4k  📊 Monthly:290.4k
```

### 表示項目

| 項目 | 説明 |
|------|------|
| 🤖 モデル名 | 使用中のモデル |
| 📊 使用量/上限 | コンテキストウィンドウの使用状況 + プログレスバー |
| ゾーン | 🟢 Good (0-50%) / 🟡 Caution (50-70%) / 🟠 Warning (70-90%) / 🔴 Critical (90%+) |
| ⬇ In | 直近APIコールの新規入力トークン(キャッシュ外) |
| ⚡ Cache | 直近APIコールのキャッシュ読み取りトークン |
| ⬆ Out | 直近APIコールの出力トークン |
| 💡 残り | 残りトークン数 |
| ⏳ ETA | バーンレートからの推定枯渇時間 |
| 🔄 圧縮回数 | セッション内のコンテキスト圧縮回数 |
| 🔥 バーンレート | 1分あたりのトークン消費速度(セッション内の実消費の積算から算出) |
| Daily/Weekly/Monthly | 累積消費量(セッションをまたいで積算) |

> **Note**: Claude Code **v2.1.132以降**が必要です。v2.1.132で `context_window.total_input_tokens` の意味が「セッション累積」から「現在のコンテキスト占有量」に変わったため、本スクリプトは占有量の増分を積算する方式で消費量を追跡しています。

## 対応環境

| 環境 | 状態 |
|------|------|
| macOS | ✅ |
| Linux | ✅ |
| Windows (Git Bash) | ✅ |
| WSL | ✅ |

## 前提条件

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) がインストール済み
- `jq` コマンドが利用可能

### jq のインストール

```bash
# macOS
brew install jq

# Ubuntu / Debian
sudo apt install jq

# Windows
winget install jqlang.jq
# Git Bash から使うには ~/bin にコピーが必要な場合がある:
mkdir -p ~/bin
cp "/c/Users/<USERNAME>/AppData/Local/Microsoft/WinGet/Packages/jqlang.jq_Microsoft.Winget.Source_8wekyb3d8bbwe/jq.exe" ~/bin/jq.exe
```

## インストール

### 自動 (推奨)

```bash
git clone https://github.com/<your-username>/claude-statusline.git
cd claude-statusline
bash install.sh
```

### 手動

1. `statusline.sh` を `~/.claude/statusline.sh` にコピー

```bash
cp statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

2. `~/.claude/settings.json` に以下を追加

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh"
  }
}
```

3. Claude Code を再起動

## Windows (Git Bash) での注意点

- `settings.json` の command は `"bash ~/.claude/statusline.sh"` とする。Mac版の記事にある `"cat | bash ~/.claude/statusline.sh"` だと stdin が渡らない
- winget でインストールした jq が Git Bash の PATH に乗らない場合がある。その場合は `~/bin/` にコピーしておけばスクリプト内で自動的にPATHに追加される

## 生成されるファイル

`~/.claude/` 以下に状態管理ファイルが作成される:

| ファイル | 用途 |
|----------|------|
| `.sl_session.json` | セッション開始時刻と累積消費トークン (`ts`, `cum`) |
| `.sl_last_state.json` | 直前レンダー時の状態 (`sid`, `tok`, `ts`) |
| `.sl_compress.json` | 圧縮回数カウント (`sid`, `count`) |
| `.sl_usage_log.csv` | セッション毎の消費量履歴 (90日で自動削除) |

## テスト

```bash
bash test-statusline.sh
```

一時ディレクトリを `HOME` に見立てて、セッション開始→増加→コンパクション→新セッションの一連の流れを検証する(実際の `~/.claude` には影響しない)。

## アンインストール

```bash
rm ~/.claude/statusline.sh
rm ~/.claude/.sl_session.json ~/.claude/.sl_last_state.json
rm ~/.claude/.sl_compress.json ~/.claude/.sl_usage_log.csv
```

`~/.claude/settings.json` から `"statusLine"` のエントリを削除する。

## License

MIT
