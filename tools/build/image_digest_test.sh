#!/usr/bin/env bash
# マニフェストのすべてのイメージが digest で参照され、渡したイメージの digest がすべて使われていることを確かめる。
set -euo pipefail

manifests="$1"
shift

if grep -E '^[[:space:]]*image:' "${manifests}" | grep -vE '@sha256:[0-9a-f]{64}$'; then
  echo "the images above are not referenced by digest" >&2
  exit 1
fi

for digest_file in "$@"; do
  digest=$(tr -d '[:space:]' < "${digest_file}")
  if ! grep -qE "@${digest}\$" "${manifests}"; then
    echo "${digest} (${digest_file}) is not used in ${manifests}" >&2
    exit 1
  fi
done
