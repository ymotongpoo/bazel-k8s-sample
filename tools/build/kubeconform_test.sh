#!/usr/bin/env bash
# レンダリングしたマニフェストを、ビルドの入力として渡した JSON スキーマで検証する。
set -euo pipefail

kubeconform="$1"
manifests="$2"
shift 2

schemas="${TEST_TMPDIR}/schemas"
mkdir -p "${schemas}"
cp "$@" "${schemas}/"

"${kubeconform}" -strict -summary \
  -schema-location "${schemas}/{{.ResourceKind}}{{.KindSuffix}}.json" \
  "${manifests}"
