#!/usr/bin/env bats
# 画面取り込み・OCR・LLM・Hyprland はスタブに差し替え、段落の組み立てと Org への追記を確かめる。

setup() {
  script="$BATS_TEST_DIRNAME/../kindle-ja"
  stub="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$stub"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  export KINDLE_JA_DIR="$BATS_TEST_TMPDIR/out"
  export STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
  mkdir -p "$XDG_RUNTIME_DIR"

  # grim / magick は渡された出力先を作るだけ
  for cmd in grim magick; do
    printf '#!/bin/sh\necho "%s $*" >> "$STUB_LOG"\neval "touch \\"\\${$#}\\""\n' "$cmd" > "$stub/$cmd"
  done
  # tesseract は OCR 結果の代わりに $OCR_TEXT を出す
  printf '#!/bin/sh\necho "tesseract $*" >> "$STUB_LOG"\nprintf "%%s\\n" "$OCR_TEXT"\n' > "$stub/tesseract"
  # curl は URL で振り分ける。OCR サーバーは OCRD_UP=1 のときだけ動いている扱い。
  # LLM には、受け取った JSON を残して固定の訳を返す
  cat > "$stub/curl" <<'EOF'
#!/bin/sh
url= data=
while [ "$#" -gt 0 ]; do
  case $1 in
    -d) data=$2; shift ;;
    http*) url=$1 ;;
  esac
  shift
done
case $url in
  */health) [ "${OCRD_UP:-}" = 1 ] || exit 7; echo '{"status":"ok"}' ;;
  */ocr) [ "${OCRD_UP:-}" = 1 ] || exit 7; echo "ocrd $url" >> "$STUB_LOG"; printf '%s' "$OCRD_JSON" ;;
  *) printf '%s' "$data" > "$STUB_LOG.payload"; printf '{"choices":[{"message":{"content":"訳文です。"}}]}' ;;
esac
EOF
  # systemd は OCR サーバーを起こせない（サービスがない）扱い。起こそうとしたことは記録する
  printf '#!/bin/sh\necho "systemctl $*" >> "$STUB_LOG"\nexit 5\n' > "$stub/systemctl"
  # 表示用の窓はすでにある扱いにして、kitty を起動させない
  printf '#!/bin/sh\necho "[{\\"class\\":\\"kindle-ja\\"}]"\n' > "$stub/hyprctl"
  printf '#!/bin/sh\nexit 0\n' > "$stub/notify-send"
  # setsid は、表示用の kitty と読み上げ（kindle-ja-say）の起動に使う。読み上げなら渡された文章も記録する
  cat > "$stub/setsid" <<'EOF'
#!/bin/sh
echo "setsid $*" >> "$STUB_LOG"
[ "$2" = kindle-ja-say ] && cat > "$STUB_LOG.say"
exit 0
EOF
  # kindle-ja-say は呼ばれた引数を記録するだけ
  printf '#!/bin/sh\necho "say $*" >> "$STUB_LOG"\n' > "$stub/kindle-ja-say"
  printf '#!/bin/sh\necho "10,20 300x400"\n' > "$stub/slurp"
  chmod +x "$stub"/*
  export PATH="$stub:$PATH"
}

ocr_page() {
  OCR_TEXT=$(cat <<'EOF'
THE CAPTAIN

(She looks at the console, and the lights of the station grow dimmer, much

dimmer than before.)

I know every corridor of this place. The reactor hums with a steady, regu-
lar rhythm that I could recognize anywhere.

NAVIGATOR
(Quietly.)
Then we wait.
EOF
)
  export OCR_TEXT
}

@test "段落をつなぎ直して原文と訳を Org に追記する" {
  ocr_page
  run "$script" testbook
  [ "$status" -eq 0 ]

  org="$KINDLE_JA_DIR/testbook.org"
  [ -f "$org" ]
  grep -qx '#+title: testbook' "$org"
  grep -qx '#+begin_quote' "$org"
  grep -qx '訳文です。' "$org"

  # 段落の途中の空行ではつながず、文末の空行と短い行で切る
  grep -qx '(She looks at the console, and the lights of the station grow dimmer, much dimmer than before.)' "$org"
  # 行末ハイフンはつなぐ
  grep -q 'steady, regular rhythm' "$org"
  # 全部大文字の行は独立した段落
  grep -qx 'THE CAPTAIN' "$org"
  grep -qx 'NAVIGATOR' "$org"
  grep -qx '(Quietly.)' "$org"
  grep -qx 'Then we wait.' "$org"
}

@test "保存した範囲がなければ既定の範囲で取り込む" {
  ocr_page
  run "$script"
  [ "$status" -eq 0 ]
  grep -q '^grim -g 148,197 1000x1112 ' "$STUB_LOG"
  [ -f "$KINDLE_JA_DIR/kindle.org" ]
}

@test "--select で選んだ範囲を保存し、次から使う" {
  run "$script" --select
  [ "$status" -eq 0 ]
  [ "$(cat "$XDG_CONFIG_HOME/kindle-ja/geometry")" = '10,20 300x400' ]

  ocr_page
  run "$script"
  [ "$status" -eq 0 ]
  grep -q '^grim -g 10,20 300x400 ' "$STUB_LOG"
}

@test "既定では PLaMo に日本語を指定して訳させる" {
  ocr_page
  run "$script"
  [ "$status" -eq 0 ]
  grep -q '"model": "plamo-3-translate-0.8b"' "$STUB_LOG.payload"
  grep -q '"target_lang": "ja"' "$STUB_LOG.payload"
}

@test "モデル設定ファイルのモデルを LLM に渡す" {
  mkdir -p "$XDG_CONFIG_HOME/kindle-ja"
  echo gemma-4-E4B-it-qat > "$XDG_CONFIG_HOME/kindle-ja/model"
  ocr_page
  run "$script"
  [ "$status" -eq 0 ]
  grep -q '"model": "gemma-4-E4B-it-qat"' "$STUB_LOG.payload"
}

@test "文字が読めなければ何も追記しない" {
  export OCR_TEXT=''
  run "$script" empty
  [ "$status" -eq 0 ]
  [ ! -e "$KINDLE_JA_DIR/empty.org" ]
}

@test "翻訳に失敗したら終了コード 1 で、Org には追記しない" {
  printf '#!/bin/sh\nexit 22\n' > "$stub/curl"
  ocr_page
  run "$script" failed
  [ "$status" -eq 1 ]
  [ ! -e "$KINDLE_JA_DIR/failed.org" ]
}

@test "表示用の窓がなければ kitty の emacs -nw を開く" {
  printf '#!/bin/sh\necho "[]"\n' > "$stub/hyprctl"
  ocr_page
  run "$script" viewer
  [ "$status" -eq 0 ]
  grep -q '^setsid -f kitty --class kindle-ja -e emacs -nw .*viewer.org --eval ' "$STUB_LOG"
}

@test "OCR サーバーが動いていれば、その段落を使い tesseract は使わない" {
  export OCRD_UP=1
  export OCRD_JSON='{"paragraphs":["THE CAPTAIN","(She looks at the console.)","I know every corridor."],"seconds":0.4}'
  run "$script" server
  [ "$status" -eq 0 ]
  grep -q '^ocrd http://127.0.0.1:8093/ocr' "$STUB_LOG"
  if grep -q '^tesseract' "$STUB_LOG"; then false; fi
  org="$KINDLE_JA_DIR/server.org"
  grep -qx 'THE CAPTAIN' "$org"
  grep -qx '(She looks at the console.)' "$org"
  # 段落は空行で区切って LLM に渡す
  grep -q 'THE CAPTAIN\\n\\n(She looks at the console.)\\n\\nI know every corridor.' "$STUB_LOG.payload"
}

@test "OCR サーバーがなければ systemd で起こそうとし、だめなら tesseract で読む" {
  ocr_page
  run "$script" fallback
  [ "$status" -eq 0 ]
  grep -q '^systemctl --user start kindle-ja-ocrd.service' "$STUB_LOG"
  grep -q '^tesseract' "$STUB_LOG"
  grep -qx 'NAVIGATOR' "$KINDLE_JA_DIR/fallback.org"
}

@test "KINDLE_JA_OCR=tesseract なら OCR サーバーを使わない" {
  export OCRD_UP=1 OCRD_JSON='{"paragraphs":["from server"]}' KINDLE_JA_OCR=tesseract
  ocr_page
  run "$script" forced
  [ "$status" -eq 0 ]
  if grep -q '^ocrd' "$STUB_LOG"; then false; fi
  if grep -q '^systemctl' "$STUB_LOG"; then false; fi
  grep -q '^tesseract' "$STUB_LOG"
}

@test "キーを押すと、まず前の読み上げを止める" {
  ocr_page
  run "$script"
  [ "$status" -eq 0 ]
  [ "$(head -n 1 "$STUB_LOG")" = 'say --stop' ]
}

@test "--stop は読み上げを止めるだけで、画面を取り込まない" {
  run "$script" --stop
  [ "$status" -eq 0 ]
  grep -qx 'say --stop' "$STUB_LOG"
  if grep -q '^grim' "$STUB_LOG"; then false; fi
}

@test "声の設定があれば、訳を読み上げる" {
  mkdir -p "$XDG_CONFIG_HOME/kindle-ja"
  echo '3 1.18' > "$XDG_CONFIG_HOME/kindle-ja/voice"
  ocr_page
  run "$script" voice
  [ "$status" -eq 0 ]
  grep -qx 'setsid -f kindle-ja-say 3 1.18' "$STUB_LOG"
  grep -qx '訳文です。' "$STUB_LOG.say"
}

@test "声の設定がなければ、読み上げない" {
  ocr_page
  run "$script" silent
  [ "$status" -eq 0 ]
  if grep -q '^setsid -f kindle-ja-say' "$STUB_LOG"; then false; fi
}

@test "KINDLE_JA_VOICE=off なら、声の設定があっても読み上げない" {
  mkdir -p "$XDG_CONFIG_HOME/kindle-ja"
  echo '3 1.18' > "$XDG_CONFIG_HOME/kindle-ja/voice"
  export KINDLE_JA_VOICE=off
  ocr_page
  run "$script" off
  [ "$status" -eq 0 ]
  if grep -q '^setsid -f kindle-ja-say' "$STUB_LOG"; then false; fi
}

@test "温度 0 で訳させる（PLaMo の訳を毎回同じにする）" {
  ocr_page
  run "$script"
  [ "$status" -eq 0 ]
  grep -q '"temperature": 0,' "$STUB_LOG.payload"
}

@test "KINDLE_JA_GEOMETRY があれば、保存した範囲より優先する" {
  mkdir -p "$XDG_CONFIG_HOME/kindle-ja"
  echo '10,20 300x400' > "$XDG_CONFIG_HOME/kindle-ja/geometry"
  export KINDLE_JA_GEOMETRY='1,2 30x40'
  ocr_page
  run "$script"
  [ "$status" -eq 0 ]
  grep -q '^grim -g 1,2 30x40 ' "$STUB_LOG"
  [ "$(cat "$XDG_CONFIG_HOME/kindle-ja/geometry")" = '10,20 300x400' ]
}
