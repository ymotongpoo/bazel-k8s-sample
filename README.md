# bazel-k8s-sample

短縮URLサービスを題材に、[Kubernetes](https://kubernetes.io/ja/)で動かすのに必要なものをすべて[Bazel](https://bazel.build/)でビルドするリポジトリです。
現在は構築中です。

## 構成

次のものをBazelでビルドします。

- Goのサービス（`services/`）とTypeScriptのフロントエンド（`web/`）
- 言語間で共有する[Protocol Buffers](https://protobuf.dev/)のスキーマ（`proto/`）
- 複数のCPUアーキテクチャ向けのコンテナイメージと、イメージをdigestで参照するKubernetesのマニフェスト（`deploy/`）

Bazelが扱うのはOCIレジストリへのpushまでです。
クラスタへの適用は[Flux](https://fluxcd.io/)に任せます。

## 前提とするバージョン

Bazelのバージョンは`.bazelversion`、依存するルールのバージョンは`MODULE.bazel`で指定します。
Bazel 10.0 LTSを使う予定です。
