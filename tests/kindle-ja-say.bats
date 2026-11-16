#!/usr/bin/env bats
# VOICEVOX と再生はスタブに差し替え、文の分け方・合成の順番・止め方を確かめる。

setup() {
  script="$BATS_TEST_DIRNAME/../kindle-ja-say"
  stub="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$stub"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
  mkdir -p "$XDG_RUNTIME_DIR"
  # audio_query は渡された文と速さの欄を JSON で返し、synthesis は受け取った JSON をそのまま「音」として書く
  cat > "$stub/curl" <<'EOF'
#!/bin/sh
text= out= data= url=
while [ "$#" -gt 0 ]; do
  case $1 in
    --data-urlencode) text=${2#text=}; shift ;;
    --data) data=${2#@}; shift ;;
    -o) out=$2; shift ;;
    http*) url=$1 ;;
  esac
  shift
done
case $url in
  */audio_query*) jq -n --arg t "$text" --arg u "$url" '{text: $t, url: $u, speedScale: 1}' ;;
  */synthesis*) cp "$data" "$out" ;;
esac
EOF
  # 再生は、「音」の中身（JSON）を記録するだけ
  printf '#!/bin/sh\njq -c "{text, speedScale, url}" "$1" >> "$STUB_LOG"\n' > "$stub/player"
  chmod +x "$stub"/*
  export PATH="$stub:$PATH"
  export KINDLE_JA_PLAYER="$stub/player"
}

@test "文に分けて、順に合成して流す" {
  run sh -c "printf '%s\n%s\n' 'アリスは座っていた。「つまらない！」と思った。' '白いウサギが走ってきた？' | '$script' 3 1.18"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$STUB_LOG")" -eq 3 ]
  [ "$(sed -n 1p "$STUB_LOG" | jq -r .text)" = 'アリスは座っていた。' ]
  [ "$(sed -n 2p "$STUB_LOG" | jq -r .text)" = '「つまらない！」と思った。' ]
  [ "$(sed -n 3p "$STUB_LOG" | jq -r .text)" = '白いウサギが走ってきた？' ]
  # 話者と速さ
  sed -n 1p "$STUB_LOG" | jq -e '.speedScale == 1.18 and (.url | endswith("speaker=3"))'
  # 終わったら PID のファイルと作業用のディレクトリを消す
  [ ! -e "$XDG_RUNTIME_DIR/kindle-ja/say.pid" ]
  [ -z "$(ls "$XDG_RUNTIME_DIR/kindle-ja")" ]
}

@test "速さを省くと 1.0" {
  run sh -c "echo 'ひとこと。' | '$script' 2"
  [ "$status" -eq 0 ]
  jq -e '.speedScale == 1.0' "$STUB_LOG"
}

@test "--stop は、PID のファイルが別のプロセスを指していたら止めない" {
  sleep 30 &
  other=$!
  mkdir -p "$XDG_RUNTIME_DIR/kindle-ja"
  echo "$other" > "$XDG_RUNTIME_DIR/kindle-ja/say.pid"
  run "$script" --stop
  [ "$status" -eq 0 ]
  kill -0 "$other"
  kill "$other"
  [ ! -e "$XDG_RUNTIME_DIR/kindle-ja/say.pid" ]
}

@test "--stop は、読み上げていなくても成功する" {
  run "$script" --stop
  [ "$status" -eq 0 ]
}

@test "話者がなければ使い方を出して終了コード 2" {
  run "$script"
  [ "$status" -eq 2 ]
}
