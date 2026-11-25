#!/usr/bin/env bash
# APIサーバーを起動し、短縮URLの発行とリダイレクトを確かめる。
set -euo pipefail

api="$1"
port=$((20000 + RANDOM % 10000))
"${api}" --addr="127.0.0.1:${port}" &
pid=$!
trap 'kill "${pid}"' EXIT

# サーバーが応答するまで待つ。
for _ in $(seq 1 50); do
  if curl -s -o /dev/null "http://127.0.0.1:${port}/"; then
    break
  fi
  sleep 0.1
done

# protojson の出力は空白の入り方が一定でないので、空白を許して code を取り出す。
code=$(curl -s -X POST -H 'Content-Type: application/json' -d '{"url":"https://bazel.build/"}' \
  "http://127.0.0.1:${port}/shorten" | sed -E 's/.*"code": *"([^"]*)".*/\1/')
location=$(curl -s -o /dev/null -w '%{redirect_url}' "http://127.0.0.1:${port}/${code}")
if [[ "${location}" != "https://bazel.build/" ]]; then
  echo "unexpected redirect: ${location}" >&2
  exit 1
fi

# 埋め込んだフロントエンドを配信していることを確かめる。
if ! curl -s "http://127.0.0.1:${port}/" | grep -q '/ui/app.js'; then
  echo "index.html is not served" >&2
  exit 1
fi
