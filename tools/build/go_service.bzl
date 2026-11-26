"""Go のサービスの実行ファイル、コンテナイメージ、その共通のテストを定義するマクロ。"""

load("@bazel_lib//lib:expand_template.bzl", "expand_template")
load("@bazel_lib//lib:transitions.bzl", "platform_transition_filegroup")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("@container_structure_test//:defs.bzl", "container_structure_test")
load("@rules_go//go:def.bzl", "go_binary")
load("@rules_oci//oci:defs.bzl", "oci_image", "oci_image_index", "oci_load", "oci_push")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("@tar.bzl", "tar")

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

    # 実行ファイルを /usr/local/bin に置いたレイヤー。
    # 置き場所、所有者、モード、更新時刻を mtree で明示し、レイヤーの digest をビルドした時刻に左右させない。
    tar(
        name = name + "_layer",
        srcs = [":" + name],
        mtree = [
            "./usr type=dir uid=0 gid=0 mode=0755 time=1672560000",
            "./usr/local type=dir uid=0 gid=0 mode=0755 time=1672560000",
            "./usr/local/bin type=dir uid=0 gid=0 mode=0755 time=1672560000",
            "./usr/local/bin/{name} type=file uid=0 gid=0 mode=0755 time=1672560000 content=$(execpath :{name})".format(name = name),
        ],
    )

    oci_image(
        name = name + "_image",
        base = base,
        entrypoint = ["/usr/local/bin/" + name],
        tars = [":" + name + "_layer"],
        visibility = visibility,
    )

    # linux/amd64 と linux/arm64 のイメージをまとめたインデックス。
    oci_image_index(
        name = name + "_index",
        images = [":" + name + "_image"],
        platforms = _IMAGE_PLATFORMS,
        visibility = visibility,
    )

    # インデックスに入るのと同じ構成でビルドした、ホストの CPU 向けのイメージ。
    # ホストの構成でビルドしたイメージは、インデックスの中のイメージと digest が一致しない。
    platform_transition_filegroup(
        name = name + "_image_host_cpu",
        srcs = [":" + name + "_image"],
        target_platform = select({
            "@platforms//cpu:aarch64": "//platforms:linux_arm64",
            "@platforms//cpu:x86_64": "//platforms:linux_amd64",
        }),
    )

    # --stamp を付けたときはコミットを、付けないときは unstamped をタグにする。
    expand_template(
        name = name + "_tags",
        out = name + "_tags.txt",
        stamp_substitutions = {"unstamped": "{{STABLE_GIT_COMMIT}}"},
        template = ["unstamped"],
    )

    # bazel run で、インデックスをレジストリに push する。
    oci_push(
        name = name + "_push",
        image = ":" + name + "_index",
        remote_tags = ":" + name + "_tags",
        repository = "{}/{}".format(registry, name),
        visibility = visibility,
    )

    # bazel run で、ホストの CPU 向けのイメージを Docker に読み込む。
    oci_load(
        name = name + "_load",
        image = ":" + name + "_image_host_cpu",
        repo_tags = ["bazel-k8s-sample/{}:latest".format(name)],
    )

    write_file(
        name = name + "_image_test_config",
        out = name + "_image_test.yaml",
        content = [_STRUCTURE_TEST.format(binary = "/usr/local/bin/" + name)],
    )

    # oci_load が Docker に読み込ませる tar を、ファイルとして取り出す。
    native.filegroup(
        name = name + "_image_tarball",
        srcs = [":" + name + "_load"],
        output_group = "tarball",
    )

    # イメージを Docker で起動せずに、tar の中身と設定だけを検査する。
    container_structure_test(
        name = name + "_image_test",
        size = "small",
        configs = [":" + name + "_image_test_config"],
        driver = "tar",
        image = ":" + name + "_image_tarball",
    )

go_service = macro(
    doc = """Go のサービスを定義する。

    name の go_binary と、それを起動して GET /healthz を確かめる name_healthz_test を作る。
    サービスは --addr で待ち受けるアドレスを受け取り、待ち受けたアドレスを
    "listening on ADDR" の形でログに出す必要がある。

    コンテナイメージとして、name_image（ビルドしたプラットフォーム向けのイメージ）、
    name_index（linux/amd64 と linux/arm64 のインデックス）、name_load（Docker への読み込み）、
    name_image_test（イメージの構造のテスト）、name_push（インデックスのレジストリへの push）も作る。
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
