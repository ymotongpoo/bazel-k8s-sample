#!/usr/bin/env bash
# サービスの実行ファイルを起動し、GET /healthz が ok を返すことを確かめる。
set -euo pipefail

binary="$1"
log="${TEST_TMPDIR}/service.log"
"${binary}" --addr=127.0.0.1:0 2>"${log}" &
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
  echo "service did not start" >&2
  cat "${log}" >&2
  exit 1
fi

body=$(curl -s "http://${addr}/healthz")
if [[ "${body}" != "ok" ]]; then
  echo "unexpected /healthz response: ${body}" >&2
  exit 1
fi
