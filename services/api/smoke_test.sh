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

code=$(curl -s -X POST -d url=https://bazel.build/ "http://127.0.0.1:${port}/shorten")
location=$(curl -s -o /dev/null -w '%{redirect_url}' "http://127.0.0.1:${port}/${code}")
if [[ "${location}" != "https://bazel.build/" ]]; then
  echo "unexpected redirect: ${location}" >&2
  exit 1
fi
