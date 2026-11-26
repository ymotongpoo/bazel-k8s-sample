"""Go のサービスの実行ファイル、コンテナイメージ、その共通のテストを定義するマクロ。"""

load("@bazel_lib//lib:expand_template.bzl", "expand_template")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("@rules_go//go:def.bzl", "go_binary")
load("@rules_img//img:image.bzl", "image_index", "image_manifest")
load("@rules_img//img:layer.bzl", "file_metadata", "image_layer")
load("@rules_img//img:load.bzl", "image_load")
load("@rules_img//img:push.bzl", "image_push")
load("@rules_img//img:test.bzl", "image_structure_test")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

# イメージをビルドするプラットフォーム。
_IMAGE_PLATFORMS = [
    "//platforms:linux_amd64",
    "//platforms:linux_arm64",
]

# イメージの構造のテストの設定。{binary} を実行ファイルのパスに置き換える。
_STRUCTURE_TEST = """\
schemaVersion: 2.0.0
metadataTest:
  entrypoint: ["{binary}"]
  user: "65532"
fileExistenceTests:
  - name: 実行ファイル
    path: {binary}
    shouldExist: true
  - name: シェルを含まない
    path: /bin/sh
    shouldExist: false
"""

def _go_service_impl(name, visibility, embed, base, registry, _healthz_test):
    go_binary(
        name = name,
        embed = embed,
        visibility = visibility,
    )

    # 実行ファイルを起動して GET /healthz を確かめる。
    sh_test(
        name = name + "_healthz_test",
        size = "small",
        srcs = [_healthz_test],
        args = ["$(rootpath :{})".format(name)],
        data = [":" + name],
    )

    binary = "/usr/local/bin/" + name

    # 実行ファイルを /usr/local/bin に置いたレイヤー。
    image_layer(
        name = name + "_layer",
        srcs = {binary: ":" + name},
        default_metadata = file_metadata(
            gid = 0,
            mode = "0755",
            uid = 0,
        ),
    )

    image_manifest(
        name = name + "_image",
        base = base,
        entrypoint = [binary],
        layers = [":" + name + "_layer"],
        visibility = visibility,
    )

    # linux/amd64 と linux/arm64 のイメージをまとめたインデックス。
    image_index(
        name = name + "_index",
        manifests = [":" + name + "_image"],
        platforms = _IMAGE_PLATFORMS,
        visibility = visibility,
    )

    # インデックスの digest を書いたファイル。マニフェストに埋め込む。
    native.filegroup(
        name = name + "_index.digest",
        srcs = [":" + name + "_index"],
        output_group = "digest",
        visibility = visibility,
    )

    # --stamp を付けたときはコミットを、付けないときは unstamped をタグにする。
    expand_template(
        name = name + "_tags",
        out = name + "_tags.txt",
        stamp_substitutions = {"unstamped": "{{STABLE_GIT_COMMIT}}"},
        template = ["unstamped"],
    )

    # bazel run で、インデックスをレジストリに push する。
    image_push(
        name = name + "_push",
        image = ":" + name + "_index",
        registry = registry.split("/", 1)[0],
        repository = "{}/{}".format(registry.split("/", 1)[1], name),
        tag_file = ":" + name + "_tags",
        visibility = visibility,
    )

    # インデックスに入るのと同じプラットフォームでビルドした、ホストの CPU 向けのイメージ。
    image_manifest(
        name = name + "_image_host_cpu",
        base = base,
        entrypoint = [binary],
        layers = [":" + name + "_layer"],
        platform = select({
            "@platforms//cpu:aarch64": "//platforms:linux_arm64",
            "@platforms//cpu:x86_64": "//platforms:linux_amd64",
        }),
    )

    # bazel run で、ホストの CPU 向けのイメージを Docker に読み込む。
    image_load(
        name = name + "_load",
        image = ":" + name + "_image_host_cpu",
        tag = "bazel-k8s-sample/{}:latest".format(name),
    )

    write_file(
        name = name + "_image_test_config",
        out = name + "_image_test.yaml",
        content = [_STRUCTURE_TEST.format(binary = binary)],
    )

    # インデックスの各プラットフォームのイメージを、レイヤーの中身を取得せずに、設定と mtree で検査する。
    image_structure_test(
        name = name + "_image_test",
        size = "small",
        configs = [":" + name + "_image_test_config"],
        image = ":" + name + "_index",
    )

go_service = macro(
    doc = """Go のサービスを定義する。

    name の go_binary と、それを起動して GET /healthz を確かめる name_healthz_test を作る。
    サービスは --addr で待ち受けるアドレスを受け取り、待ち受けたアドレスを
    "listening on ADDR" の形でログに出す必要がある。

    コンテナイメージとして、name_image（ビルドしたプラットフォーム向けのイメージ）、
    name_index（linux/amd64 と linux/arm64 のインデックス）、name_index.digest（その digest）、
    name_load（Docker への読み込み）、name_image_test（イメージの構造のテスト）、
    name_push（インデックスのレジストリへの push）も作る。
    """,
    implementation = _go_service_impl,
    attrs = {
        "embed": attr.label_list(
            doc = "サービスの main パッケージの go_library。",
            mandatory = True,
            configurable = False,
        ),
        "base": attr.label(
            doc = "イメージのベース。",
            default = "@distroless_static",
            configurable = False,
        ),
        "registry": attr.string(
            doc = "イメージを push するレジストリとリポジトリの接頭辞。リポジトリは registry/name になる。",
            default = "localhost:5001/bazel-k8s-sample",
            configurable = False,
        ),
        "_healthz_test": attr.label(
            default = "//tools/build:healthz_test.sh",
            configurable = False,
        ),
    },
)
