#!/usr/bin/env bash
# --stamp を付けたビルドに埋め込む値を出力する。STABLE_ で始まる値が変わると、それを使うアクションは実行し直される。
set -euo pipefail

echo "STABLE_GIT_COMMIT $(git rev-parse HEAD)"
