#!/usr/bin/env bash
# APIサーバーを起動し、短縮URLの発行とリダイレクト、フロントエンドの配信を確かめる。
set -euo pipefail

api="$1"
log="${TEST_TMPDIR}/api.log"
# ポートはサーバーに選ばせ、ログに出た待ち受けのアドレスを読む。
"${api}" --addr=127.0.0.1:0 2>"${log}" &
pid=$!
trap 'kill "${pid}"' EXIT

addr=""
for _ in $(seq 1 50); do
  addr=$(sed -n -E 's/.*listening on (.*)$/\1/p' "${log}")
  if [[ -n "${addr}" ]]; then
    break
  fi
  sleep 0.1
done
if [[ -z "${addr}" ]]; then
  echo "server did not start" >&2
  cat "${log}" >&2
  exit 1
fi

# protojson の出力は空白の入り方が一定でないので、空白を許して code を取り出す。
code=$(curl -s -X POST -H 'Content-Type: application/json' -d '{"url":"https://bazel.build/"}' \
  "http://${addr}/shorten" | sed -E 's/.*"code": *"([^"]*)".*/\1/')
location=$(curl -s -o /dev/null -w '%{redirect_url}' "http://${addr}/${code}")
if [[ "${location}" != "https://bazel.build/" ]]; then
  echo "unexpected redirect: ${location}" >&2
  exit 1
fi

# 埋め込んだフロントエンドを配信していることを確かめる。
if ! curl -s "http://${addr}/" | grep -q '/ui/app.js'; then
  echo "index.html is not served" >&2
  exit 1
fi
