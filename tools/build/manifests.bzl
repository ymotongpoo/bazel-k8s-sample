"""レンダリングしたマニフェストを Flux が取得できる OCI アーティファクトにして push するマクロ。"""

load("@bazel_lib//lib:expand_template.bzl", "expand_template")
load("@rules_oci//oci:defs.bzl", "oci_image", "oci_push")
load("@tar.bzl", "tar")
load(":kustomize.bzl", "repository_file")

def _manifests_artifact_impl(name, visibility, manifests, repository, tags):
    # Flux の OCIRepository が展開できる tar+gzip のレイヤーにする。
    tar(
        name = name + "_layer",
        srcs = [manifests],
        compress = "gzip",
        mtree = ["./manifests.yaml type=file uid=0 gid=0 mode=0644 time=1672560000 content=$(execpath {})".format(manifests)],
    )

    expand_template(
        name = name + "_annotations",
        out = name + "_annotations.txt",
        stamp_substitutions = {"unstamped": "{{STABLE_GIT_COMMIT}}"},
        template = ["org.opencontainers.image.revision=unstamped"],
    )

    # マニフェストだけを入れた OCI アーティファクト。コンテナとして実行するものではないが、
    # rules_oci はイメージの形でしか作れないので、OS と CPU には仮の値を入れる。
    oci_image(
        name = name,
        annotations = ":" + name + "_annotations",
        architecture = "amd64",
        os = "linux",
        tars = [":" + name + "_layer"],
        visibility = visibility,
    )

    # --stamp を付けたときはコミットを、付けないときは unstamped をタグに含める。
    expand_template(
        name = name + "_tags",
        out = name + "_tags.txt",
        stamp_substitutions = {"unstamped": "{{STABLE_GIT_COMMIT}}"},
        template = tags + ["unstamped"],
    )

    repository_file(
        name = name + "_repository",
        repository = repository,
    )

    oci_push(
        name = name + "_push",
        image = ":" + name,
        remote_tags = ":" + name + "_tags",
        repository_file = ":" + name + "_repository",
        visibility = visibility,
    )

manifests_artifact = macro(
    doc = """manifests を1つのレイヤーにした OCI アーティファクト name と、それを push する name_push を作る。

    push 先は //tools/build:registry と //tools/build:repository_prefix と repository から決める。
    タグは tags と、--stamp を付けたときのコミット。
    """,
    implementation = _manifests_artifact_impl,
    attrs = {
        "manifests": attr.label(
            doc = "kustomize_build がレンダリングしたマニフェスト。",
            mandatory = True,
            configurable = False,
        ),
        "repository": attr.string(
            doc = "接頭辞の後ろに付けるリポジトリの名前。",
            mandatory = True,
            configurable = False,
        ),
        "tags": attr.string_list(
            doc = "コミットのほかに付けるタグ。",
            configurable = False,
        ),
    },
)
