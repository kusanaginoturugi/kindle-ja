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
  printf '#!/bin/sh\nprintf "%%s\\n" "$OCR_TEXT"\n' > "$stub/tesseract"
  # curl は受け取った JSON を残し、固定の訳を返す
  cat > "$stub/curl" <<'EOF'
#!/bin/sh
while [ "$#" -gt 0 ]; do
  [ "$1" = -d ] && printf '%s' "$2" > "$STUB_LOG.payload"
  shift
done
printf '{"choices":[{"message":{"content":"訳文です。"}}]}'
EOF
  # 表示用の窓はすでにある扱いにして、kitty を起動させない
  printf '#!/bin/sh\necho "[{\\"class\\":\\"kindle-ja\\"}]"\n' > "$stub/hyprctl"
  printf '#!/bin/sh\nexit 0\n' > "$stub/notify-send"
  printf '#!/bin/sh\necho "kitty $*" >> "$STUB_LOG"\n' > "$stub/setsid"
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
  grep -q '^kitty -f kitty --class kindle-ja -e emacs -nw .*viewer.org --eval ' "$STUB_LOG"
}
