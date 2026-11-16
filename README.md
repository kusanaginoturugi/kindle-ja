# kindle-ja

Kindle Cloud Reader で読んでいる英語の本を、ページごとにローカル LLM で日本語に訳して Emacs で読むためのスクリプト。`SUPER + Y` で、画面の決まった範囲を取り込み、OCR し、訳して、Org ファイルに追記する。

Kindle Cloud Reader の本文はブラウザの DOM にテキストとして入っていない（ページ内検索でも本文の単語がヒットしない）。そのため、ページのテキストを拾って訳すブラウザ拡張の翻訳機能では訳せない。そこで画面に表示されたものを OCR する。

## 経緯

1. Eliezer Yudkowsky と Nate Soares の *If Anyone Builds It, Everyone Dies* を読もうとした。セールの情報を見て探すと、英語版が安く出ていた。日本語版は検索に出てこなかったので、英語版と分かったうえで買った。
2. ふだん Web ページの翻訳に使っているブラウザ拡張（[offline-browser-translate](https://github.com/kusanaginoturugi/offline-browser-translate) のフォーク、Local LLM Translator）を Kindle Cloud Reader で使ってみた。何も訳されなかった。ページ内検索で本文の単語を探してもヒットしないので、本文は DOM のテキストになっていない。拡張をどう直しても訳せない。しかも、よく見ると買ったのは、同じ題名を借りた別の短い一幕劇だった。
3. DRM を外して EPUB にする方向には行かず、画面に見えているものをそのまま使うことにした。1 回のキー操作で 1 画面を取り込み、OCR してローカル LLM で訳し、Emacs で読む。こうしてできたのがこのスクリプト。
4. 一幕劇で試すと、戯曲の話者名やト書きが崩れたので、段落の組み立てを直した。最初は会話モデルの Gemma 4 E4B で訳していて、1 画面 6 秒ほど、内容はつかめる程度の自然さだった。
5. あとから、翻訳専用の PLaMo 3 Translate 0.8B（同じブラウザ拡張で使っていたモデル）にすればよかったと気づいて、既定にした。1 画面 2 秒ほどになり、時間の大半は OCR になった。
6. 時間の大半が OCR になったので、OCR も GPU で動かすことにした。PaddleOCR 本体と、同じ PaddleOCR のモデル（PP-OCRv6）を onnxruntime で動かす RapidOCR を比べ、環境の軽い RapidOCR を常駐させる OCR サーバー（`kindle-ja-ocrd`）にした。1 画面 1 秒ほどになった。
7. ここまで軽くなったので、訳を VOICEVOX で読み上げられるようにした（`kindle-ja-say`）。
8. それでも本命の本は、結局日本語版の紙の本を買った（あとで探したら日本語版があった）。話題の本なので、読み終わったら回し読みしたい。日本の Kindle の本は人に貸せないし、買っても実際は読む権利を借りているだけなのに、値段は紙の本と変わらない。それに、一冊を通して読むには、ローカル LLM の訳はまだ人の訳に及ばない。このスクリプトは、日本語版がない本や、とりあえず中身を知りたい本に使う。

## 動作

1. `grim` で画面の決まった範囲を取り込む
2. OCR サーバー（`kindle-ja-ocrd`、RapidOCR を GPU で常駐）に画像を渡し、段落ごとの文字を受け取る。サーバーが動いていなければ systemd で起こす。それでも使えなければ、`magick` で 2 倍に拡大して `tesseract`（CPU）で読む
3. llama.cpp の OpenAI 互換 API（`127.0.0.1:8080/v1/chat/completions`）に送って日本語に訳す
4. `~/Documents/kindle-ja/<本の名前>.org` に、見出し（日時）、原文の quote ブロック、訳の順で追記する
5. 表示用の窓（kitty、クラス `kindle-ja`）がなければ、`emacs -nw` で Org ファイルを開く

表示用の Emacs は読み取り専用で、`auto-revert-mode` で追記を読み直す。読み直すたびに原文の quote ブロックを畳み、いちばん新しい見出しを窓の先頭に置くので、見出しのすぐ下から訳を読める。原文を見たいときは `#+begin_quote` の行で `TAB` を押すと開く。日本語は `visual-line-mode` と `word-wrap-by-category` で窓の幅に合わせて折り返す。

訳している間にもう一度押しても、二重には動かない（通知が出るだけ）。

### 読み上げ（kindle-ja-say）

`~/.config/kindle-ja/voice` に VOICEVOX の話者 ID と速さ（例 `3 1.18`、ずんだもんを 1.18 倍で）を書くと、訳を書き足したあとで読み上げる。
訳を「。」で文に分け（「！」「？」は空白が続くときだけ）、1 文目を流しているあいだに次の文を合成する。VOICEVOX ENGINE が CPU 版でも、合成は再生の 5 倍ほど速く、キーを押してから 1 文目が鳴るまで 1.4 秒ほど（Ryzen 7 3700X）。
次のページで `SUPER + Y` を押すと、前のページの読み上げはすぐ止まる。`kindle-ja --stop` でも止められる。再生は `pw-play`（PipeWire）。

### Emacs 以外のエディタで読む

訳は普通のテキストファイル（Org 形式）に足していくだけなので、ファイルの変更を読み直せるエディタなら、Emacs でなくても読める（Vim / Neovim の `autoread`、VS Code の自動再読み込み、`tail -f` など）。
Emacs に合わせているのは、表示用の窓を開くコマンド（kindle-ja の中の `kitty … emacs -nw`）と、原文を畳んで新しい見出しを窓の先頭に出す Emacs Lisp だけ。
ほかのエディタで使いたいときは、この 2 か所を、自分のコーディングエージェントに頼んで書き換えてもらうとよい。

## OCR サーバー（kindle-ja-ocrd）

RapidOCR（PaddleOCR の PP-OCRv6 small を onnxruntime-gpu で動かす）を、`127.0.0.1:8093` で常駐させる小さな HTTP サーバー。
起動にモデルの読み込みと CUDA の初期化で数秒かかるので、キーを押すたびには起動しない。kindle-ja が必要なときに `systemctl --user start kindle-ja-ocrd` で起こし、10 分使われなければ自分で終わって VRAM を返す。使う VRAM は 1GB ほど。

- `GET /health`：`{"status": "ok"}`
- `POST /ocr`：本文に画像（PNG など）を送ると、`{"paragraphs": [...], "seconds": 0.4}` を返す

画像は中で 2 倍に拡大してから読む。Kindle の文字は 1 行の高さが 25px ほどしかなく、等倍のままだと `!` を `l` と読むことがあった。

段落は行の位置から組み立てる。Kindle は段落の間を、段落の中の行間より少し広く空ける（2 倍に拡大した画面で 65〜67 に対して 74〜83）。行の中心どうしの間隔を小さい順に並べ、初めて 6% 以上跳ねたところを段落の切れ目のしきい値にする。跳ねるところがない（1 行の段落ばかり、または段落が 1 つだけの）ページは、間隔が行の高さの 1.45 倍より広ければ全部を切れ目にする。行末のハイフンは、次の行が小文字で始まるときだけ取ってつなぐ。

## 段落の組み立て（tesseract で読むとき）

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
- 読み上げるなら：VOICEVOX ENGINE（`127.0.0.1:50021`）と `pw-play`（PipeWire）
- OCR サーバーを使うなら：Python 3、NVIDIA の GPU（ドライバは CUDA 13 に対応したもの。CUDA と cuDNN のライブラリは pip で入る）

Arch Linux なら次で入る。

```sh
sudo pacman -S --needed grim slurp tesseract tesseract-data-eng imagemagick jq curl libnotify kitty emacs-nox
```

## インストール

```sh
./setup-ocrd        # OCR サーバーの環境を ~/.local/share/kindle-ja/venv に作る（約 2.7GB、初回だけ）
./deploy            # kindle-ja と kindle-ja-ocrd を ~/.local/bin に入れ、kindle-ja-ocrd.service を置く
./deploy ~/bin      # 入れる場所を指定する
```

`setup-ocrd` は RapidOCR 3.10.0 と `onnxruntime-gpu[cuda,cudnn]` 1.31.1 を入れ、モデルを取ってきて、CUDA が使えるか確かめる。
RapidOCR は CPU 版の onnxruntime を引っぱってくるので、入れたあとで GPU 版に入れ替えている。`setup-ocrd` をしなければ、kindle-ja は tesseract で読む。

Hyprland（Lua 設定）のキー割り当て例。

```lua
hl.bind(main_mod .. " + Y", hl.dsp.exec_cmd("kindle-ja"), { description = "Kindle の範囲を OCR して訳す" })
hl.bind(main_mod .. " + SHIFT + Y", hl.dsp.exec_cmd("kindle-ja --select"), { description = "kindle-ja の取り込み範囲を選び直す" })
hl.bind(main_mod .. " + CTRL + Y", hl.dsp.exec_cmd("kindle-ja --stop"), { description = "kindle-ja の読み上げを止める" })
```

## 使い方

```sh
kindle-ja                # 決まった範囲を取り込んで訳す
kindle-ja 本の名前       # その名前の Org ファイルに追記する
kindle-ja --select       # 取り込む範囲を slurp で選び直して保存する（訳はしない）
kindle-ja --stop         # 読み上げを止める
```

ふだんはキー割り当てから引数なしで使う。Kindle でページを送り、`SUPER + Y` を押して、訳が出たら次のページへ進む。

## 設定

設定は `${XDG_CONFIG_HOME:-~/.config}/kindle-ja/` に 1 行ずつのファイルで置く。

| ファイル | 内容 | ないとき |
| --- | --- | --- |
| `geometry` | 取り込む範囲（`grim -g` の形式、例 `148,197 1000x1112`） | `148,197 1000x1112` |
| `book` | 追記する Org ファイルの名前 | `kindle` |
| `model` | 翻訳に使うモデル ID（`/v1/models` に出るもの） | `plamo-3-translate-0.8b` |
| `voice` | 読み上げる VOICEVOX の話者 ID と速さ（例 `3 1.18`） | 読み上げない |

範囲の既定値は、2560x1440 の画面の左半分に Firefox を置いて Kindle Cloud Reader を開いたときの本文の位置（左右のページ送りボタンは外してある）。ウィンドウの位置や文字の大きさを変えたら、`kindle-ja --select`（`SUPER + SHIFT + Y`）で選び直す。

環境変数でも変えられる。

| 変数 | 内容 |
| --- | --- |
| `KINDLE_JA_LLM_MODEL` | モデル ID。`model` ファイルより優先する |
| `KINDLE_JA_GEOMETRY` | 取り込む範囲。`geometry` ファイルより優先し、ファイルは書き換えない |
| `KINDLE_JA_LLM_URL` | API の URL。既定は `http://127.0.0.1:8080/v1/chat/completions` |
| `KINDLE_JA_DIR` | Org ファイルを置くディレクトリ。既定は `~/Documents/kindle-ja` |
| `KINDLE_JA_OCR` | `tesseract` にすると、OCR サーバーを使わず tesseract で読む。既定は `server` |
| `KINDLE_JA_OCR_URL` | OCR サーバーの URL。既定は `http://127.0.0.1:8093` |
| `KINDLE_JA_VOICE` | 読み上げの話者 ID と速さ。`voice` ファイルより優先する。`off` で読み上げない |
| `KINDLE_JA_VOICEVOX_URL` | VOICEVOX ENGINE の URL。既定は `http://127.0.0.1:50021` |
| `KINDLE_JA_PLAYER` | 再生に使うコマンド。既定は `pw-play` |

OCR サーバー（`kindle-ja-ocrd`）の環境変数は、`KINDLE_JA_OCRD_PORT`（既定 8093）、`KINDLE_JA_OCRD_IDLE`（使われないまま終わるまでの秒数、既定 600、0 で終わらない）、`KINDLE_JA_OCRD_CPU`（1 で GPU を使わない）。

## 速さ

*Alice's Adventures in Wonderland*（保護期間満了、Project Gutenberg の本文）の第 1 章冒頭 253 語を 1 ページの画像にして、モデルを変えて測った。
Ryzen 7 3700X、RTX 3060（VRAM 12GB）、llama.cpp v0.9.0。モデルを読み込んだあとの 3 回の値。

| モデル | 1 ページ全体 | うち翻訳 | VRAM |
| --- | --- | --- | --- |
| `plamo-3-translate-0.8b`（既定） | 約 1.95 秒 | 約 0.65 秒 | E4B と同時に載る |
| `gemma-4-E4B-it-qat` | 約 5.6 秒 | 約 4.3 秒 | 音声入力用に常駐 |
| `gemma-4-12b-it-qat-imatrix` | 約 10.7 秒 | 約 9.4 秒 | E4B と同時には載らない |

ここまでの OCR は tesseract（CPU 16 スレッド、2 倍に拡大）で、拡大と OCR でどのモデルでも約 1.3 秒。PLaMo（翻訳専用の 0.8B）にすると、時間の大半は OCR になる。

そこで OCR を GPU にした。同じ Kindle の画面（1000x1112）を読ませ、2 回目以降の時間と、tesseract（2 倍に拡大）と単語が食い違った数を比べた。

| OCR | 渡す画像 | 1 ページ | 食い違い |
| --- | --- | --- | --- |
| tesseract（CPU） | 2 倍 | 約 0.9 秒（拡大に 0.2〜0.4 秒） | 基準 |
| RapidOCR（PP-OCRv6 small、GPU）← kindle-ja-ocrd | 2 倍 | 約 0.57 秒 | 0 |
| RapidOCR（同、GPU） | 等倍 | 約 0.43 秒 | 10（`!` → `l` など） |
| RapidOCR（PP-OCRv6 medium、GPU） | 2 倍 | 約 0.81 秒 | 0 |
| PaddleOCR 3.7 本体（PP-OCRv6 medium、GPU） | 等倍 | 約 0.49 秒 | 0 |

PaddleOCR 本体は拡大しなくても正しく読めたが、PaddlePaddle が Python 3.14 向けに配られておらず、Python 3.12 と合わせて約 10GB になる。RapidOCR はシステムの Python のまま約 2.7GB で入り、2 倍に拡大すれば同じ結果になるので、こちらにした。cuDNN の畳み込みの探し方は `HEURISTIC` にしている（既定の `EXHAUSTIVE` は、画像の大きさが変わるたびに 1 秒以上かけて探し直す）。

OCR サーバー ＋ PLaMo で、1 ページ全体は約 1.0 秒（OCR サーバーの起動を含む最初の 1 枚は約 5.4 秒）。

訳の出来は、同じページでそれぞれ癖があった。

- PLaMo：「Oh dear! Oh dear!」の繰り返しまで訳すが、川の土手の bank を「銀行」と訳し、waistcoat が「ウェストコート」のまま。
- E4B：読めるが、誤字（「うんざかり」）や、ぎこちない文がある。
- 12B：いちばん自然だが、「Oh dear!」の繰り返しが 1 回に減った。12B は E4B と同時に VRAM に載らないので、音声入力などで E4B を使っていると、読み込みに失敗する。

どれも中身をつかむには十分だが、一冊を通して読むには人の訳に及ばない。PLaMo は、chat template が翻訳先を `chat_template_kwargs.target_lang` で受け取り、system メッセージを無視する。kindle-ja は `target_lang` に `ja` を付けて送り、会話モデル向けの system の指示も一緒に送る。

## テスト

```sh
make test   # shellcheck、bats、Python の unittest
```

bats では、画面取り込み・OCR・LLM・Hyprland・systemd・VOICEVOX・再生をスタブに差し替えて、段落の組み立て、Org への追記、範囲とモデルの設定、OCR サーバーと tesseract の切り替え、読み上げの文の分け方と止め方、失敗時の動きを確かめる。
Python の unittest（`tests/test_ocrd.py`）では、OCR の枠を手で作って、kindle-ja-ocrd の段落の組み立てを確かめる（RapidOCR は要らない）。

## 注意

- 自分で買った本を、自分の画面で読むための道具。訳した Org ファイルには本文の原文と訳が残るので、人に渡したり公開したりしない。
- DRM の解除や、本全体の自動取り込みはしない。1 回のキー操作で 1 画面だけを取り込む。
- 訳はローカル LLM によるもので、誤訳や訳抜けがあり得る。原文は quote ブロックで確かめられる。
