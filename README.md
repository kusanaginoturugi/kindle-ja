# kindle-ja

Kindle Cloud Reader で読んでいる英語の本を、ページごとにローカル LLM で日本語に訳して Emacs で読むためのスクリプト。`SUPER + Y` で、画面の決まった範囲を取り込み、OCR し、訳して、Org ファイルに追記する。

Kindle Cloud Reader の本文はブラウザの DOM にテキストとして入っていない（ページ内検索でも本文の単語がヒットしない）。そのため、ページのテキストを拾って訳すブラウザ拡張の翻訳機能では訳せない。そこで画面に表示されたものを OCR する。

## 動作

1. `grim` で画面の決まった範囲を取り込み、`magick` でグレースケール・2 倍に拡大する
2. `tesseract`（英語）で OCR し、行末のハイフンをつなぎ、行を段落にまとめる
3. llama.cpp の OpenAI 互換 API（`127.0.0.1:8080/v1/chat/completions`）に送って日本語に訳す
4. `~/Documents/kindle-ja/<本の名前>.org` に、見出し（日時）、原文の quote ブロック、訳の順で追記する
5. 表示用の窓（kitty、クラス `kindle-ja`）がなければ、`emacs -nw` で Org ファイルを開く

表示用の Emacs は読み取り専用で、`auto-revert-mode` で追記を読み直す。読み直すたびに原文の quote ブロックを畳み、いちばん新しい見出しを窓の先頭に置くので、見出しのすぐ下から訳を読める。原文を見たいときは `#+begin_quote` の行で `TAB` を押すと開く。日本語は `visual-line-mode` と `word-wrap-by-category` で窓の幅に合わせて折り返す。

訳している間にもう一度押しても、二重には動かない（通知が出るだけ）。

## 段落の組み立て

tesseract は段落の途中にも空行を入れたり、段落の間に空行を入れなかったりするので、次の規則で段落を組み直す。

- 短い行（両端揃えの段落の最終行）のあとで切る
- 空行は、直前が文末記号（`.` `!` `?` `:` `)` `”` `’` `…` など）で終わっているときだけ段落の切れ目にする
- 全部大文字の行（戯曲の話者名や見出し）は 1 行で 1 段落にする
- 行末が `-` で次の行が小文字で始まるときは、ハイフンを取ってつなぐ

## 必要なもの

- Hyprland（Wayland）、`grim`、`slurp`、`hyprctl`
- `tesseract` と `tesseract-data-eng`、ImageMagick（`magick`）
- `jq`、`curl`、`notify-send`
- `kitty`、`emacs`（`emacs-nox` で可）
- OpenAI 互換 API を持つローカル LLM サーバー（llama.cpp の `llama-server` など）

Arch Linux なら次で入る。

```sh
sudo pacman -S --needed grim slurp tesseract tesseract-data-eng imagemagick jq curl libnotify kitty emacs-nox
```

## インストール

```sh
./deploy            # ~/.local/bin に入れる
./deploy ~/bin      # 入れる場所を指定する
```

Hyprland（Lua 設定）のキー割り当て例。

```lua
hl.bind(main_mod .. " + Y", hl.dsp.exec_cmd("kindle-ja"), { description = "Kindle の範囲を OCR して訳す" })
hl.bind(main_mod .. " + SHIFT + Y", hl.dsp.exec_cmd("kindle-ja --select"), { description = "kindle-ja の取り込み範囲を選び直す" })
```

## 使い方

```sh
kindle-ja                # 決まった範囲を取り込んで訳す
kindle-ja 本の名前       # その名前の Org ファイルに追記する
kindle-ja --select       # 取り込む範囲を slurp で選び直して保存する（訳はしない）
```

ふだんはキー割り当てから引数なしで使う。Kindle でページを送り、`SUPER + Y` を押して、訳が出たら次のページへ進む。

## 設定

設定は `${XDG_CONFIG_HOME:-~/.config}/kindle-ja/` に 1 行ずつのファイルで置く。

| ファイル | 内容 | ないとき |
| --- | --- | --- |
| `geometry` | 取り込む範囲（`grim -g` の形式、例 `148,197 1000x1112`） | `148,197 1000x1112` |
| `book` | 追記する Org ファイルの名前 | `kindle` |
| `model` | 翻訳に使うモデル ID（`/v1/models` に出るもの） | `gemma-4-E4B-it-qat` |

範囲の既定値は、2560x1440 の画面の左半分に Firefox を置いて Kindle Cloud Reader を開いたときの本文の位置（左右のページ送りボタンは外してある）。ウィンドウの位置や文字の大きさを変えたら、`kindle-ja --select`（`SUPER + SHIFT + Y`）で選び直す。

環境変数でも変えられる。

| 変数 | 内容 |
| --- | --- |
| `KINDLE_JA_LLM_MODEL` | モデル ID。`model` ファイルより優先する |
| `KINDLE_JA_LLM_URL` | API の URL。既定は `http://127.0.0.1:8080/v1/chat/completions` |
| `KINDLE_JA_DIR` | Org ファイルを置くディレクトリ。既定は `~/Documents/kindle-ja` |

## 速さ

1 ページ（1000x1112 の範囲、約 260 語）で、全体は約 7.5 秒。

| 処理 | 時間 |
| --- | --- |
| 拡大（magick） | 約 0.2 秒 |
| OCR（tesseract、CPU 16 スレッド） | 約 1.0 秒 |
| 翻訳（`gemma-4-E4B-it-qat`） | 約 6 秒 |

ほとんどは翻訳の時間。tesseract は CPU で動き、GPU は使わない。拡大しないと OCR は 0.2 秒ほど速くなるが、`I` を `1` と読み違えることがあったので拡大している。

`gemma-4-12b-it-qat-imatrix` は訳がやや良いが、`gemma-4-E4B-it-qat` と同時には VRAM に載らない（音声入力などで E4B を使っていると、12B の読み込みが失敗する）。そのため既定は E4B にしている。

## テスト

```sh
make test   # shellcheck と bats
```

画面取り込み・OCR・LLM・Hyprland はスタブに差し替えて、段落の組み立て、Org への追記、範囲とモデルの設定、失敗時の動きを確かめる。

## 注意

- 自分で買った本を、自分の画面で読むための道具。訳した Org ファイルには本文の原文と訳が残るので、人に渡したり公開したりしない。
- DRM の解除や、本全体の自動取り込みはしない。1 回のキー操作で 1 画面だけを取り込む。
- 訳はローカル LLM によるもので、誤訳や訳抜けがあり得る。原文は quote ブロックで確かめられる。
