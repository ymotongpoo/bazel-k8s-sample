#!/usr/bin/env bash
# 手元に kind のクラスタとレジストリを立て、Flux を入れる。
# レジストリの設定は kind のドキュメントの「Local Registry」の手順に従う。
set -euo pipefail

cluster=bazel-k8s-sample
reg_name=kind-registry
reg_port=5001
node_image='kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5'
registry_image='registry:3@sha256:82f6ff4a7f982960c8aa51617fea3aabc485df6e55cce80d22deb1de36f1bc3c'

# 1. 手元のレジストリ。ホストからは localhost:5001 で push する。
if [[ "$(docker inspect -f '{{.State.Running}}' "${reg_name}" 2>/dev/null || true)" != true ]]; then
  docker run -d --restart=always -p "127.0.0.1:${reg_port}:5000" --network bridge --name "${reg_name}" "${registry_image}"
fi

# 2. クラスタ。containerd にレジストリの設定のディレクトリを読ませる。
#    ビルドの基盤のサービス（infra/）は NodePort で待ち受け、ホストの 127.0.0.1 につなぐ。
if ! kind get clusters | grep -qx "${cluster}"; then
  kind create cluster --name "${cluster}" --image "${node_image}" --config - <<YAML
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
  - |-
    [plugins."io.containerd.grpc.v1.cri".registry]
      config_path = "/etc/containerd/certs.d"
nodes:
  - role: control-plane
    extraPortMappings:
      # bazel-remote の gRPC
      - containerPort: 30092
        hostPort: 9092
        listenAddress: 127.0.0.1
      # Buildbarn のフロントエンドの gRPC
      - containerPort: 30980
        hostPort: 8980
        listenAddress: 127.0.0.1
YAML
fi

# 3. ノードの中の localhost:5001 は、ノード自身を指す。イメージの pull をレジストリのコンテナに向ける。
for node in $(kind get nodes --name "${cluster}"); do
  docker exec "${node}" mkdir -p "/etc/containerd/certs.d/localhost:${reg_port}"
  printf '[host."http://%s:5000"]\n' "${reg_name}" |
    docker exec -i "${node}" cp /dev/stdin "/etc/containerd/certs.d/localhost:${reg_port}/hosts.toml"
done

# 4. レジストリをクラスタのネットワークにつなぐ。Flux はクラスタの中から kind-registry:5000 で pull する。
if [[ "$(docker inspect -f '{{json .NetworkSettings.Networks.kind}}' "${reg_name}")" == null ]]; then
  docker network connect kind "${reg_name}"
fi

# 5. Flux のコントローラーを入れ、dev のマニフェストを取得して適用させる。
flux install
kubectl apply -f deploy/flux/dev.yaml

# 6. ビルドの基盤のサービス。
kubectl apply -f infra/bazel-remote/bazel-remote.yaml
kubectl -n build rollout status deployment/bazel-remote --timeout=5m
kubectl apply -k infra/buildbarn
kubectl -n buildbarn rollout status statefulset/storage --timeout=10m
kubectl -n buildbarn rollout status deployment/frontend deployment/scheduler-ubuntu22-04 deployment/worker-ubuntu22-04 --timeout=15m
