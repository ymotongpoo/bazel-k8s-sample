#!/usr/bin/env bash
# 手元の変更をビルドして kind のレジストリに push し、Flux にすぐ取得と適用をさせる。
# 手元のループではコミットをタグにしないので、--config=push は付けない。
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# 1つの手順を実行し、かかった時間を標準エラー出力に書く。
step() {
  local label=$1
  shift
  local start=${EPOCHREALTIME}
  "$@"
  printf '%s: %.1f秒\n' "${label}" "$(bc <<<"${EPOCHREALTIME} - ${start}")" >&2
}

step "ビルドとpush" bazel run //deploy:push_dev
step "Fluxの取得と適用" flux reconcile kustomization shortener-dev -n flux-system --with-source
step "ロールアウト" kubectl -n shortener rollout status deployment/api deployment/worker --timeout=2m
