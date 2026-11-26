#!/usr/bin/env bash
# 手元の bazel-remote の mTLS に使う CA、サーバー、クライアントの証明書を tools/dev/certs/ に作り、
# サーバーの証明書と鍵とクライアントを確かめる CA を、kind のクラスタの Secret にする。
# 鍵はリポジトリにコミットしない（.gitignore で *.pem と *.key を除外している）。
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
dir=tools/dev/certs
mkdir -p "${dir}"
cd "${dir}"

if [[ ! -f ca.key ]]; then
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 \
    -subj "/CN=bazel-k8s-sample local cache CA" -keyout ca.key -out ca.pem
fi

# サーバーの証明書。ホストからは localhost:9092 で、クラスタの中からは Service の名前で接続する。
openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
  -subj "/CN=bazel-remote" -keyout server.key -out server.csr
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial -days 30 -out server.pem \
  -extfile <(printf 'subjectAltName=DNS:localhost,IP:127.0.0.1,DNS:bazel-remote.build.svc\n')

# キャッシュに書き込んでよいビルド（main への push の CI など）に渡すクライアントの証明書。
openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
  -subj "/CN=trusted-ci" -keyout client.key -out client.csr
openssl x509 -req -in client.csr -CA ca.pem -CAkey ca.key -CAcreateserial -days 30 -out client.pem \
  -extfile <(printf 'extendedKeyUsage=clientAuth\n')

rm -f server.csr client.csr ca.srl
kubectl create namespace build --dry-run=client -o yaml | kubectl apply -f -
kubectl -n build create secret generic bazel-remote-tls \
  --from-file=ca.pem --from-file=server.pem --from-file=server.key \
  --dry-run=client -o yaml | kubectl apply -f -
