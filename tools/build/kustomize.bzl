"""Kustomize のマニフェストをレンダリングして検証するルールとマクロ。"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

def repository_prefix(ctx):
    """//tools/build:registry と //tools/build:repository_prefix から、イメージのリポジトリの接頭辞を返す。"""
    return "{}/{}".format(
        ctx.attr._registry[BuildSettingInfo].value,
        ctx.attr._repository_prefix[BuildSettingInfo].value,
    )

REGISTRY_ATTRS = {
    "_registry": attr.label(default = "//tools/build:registry"),
    "_repository_prefix": attr.label(default = "//tools/build:repository_prefix"),
}

def _kustomize_image_digests_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + "/kustomization.yaml")

    args = ctx.actions.args()
    args.add("-out", out)
    args.add("-repository_prefix", repository_prefix(ctx))
    digests = []
    for name, target in ctx.attr.images.items():
        files = target.files.to_list()
        if len(files) != 1:
            fail("images[{}] must be a single digest file, got {}".format(name, files))
        digests.append(files[0])
        args.add("{}={}".format(name, files[0].path))

    ctx.actions.run(
        executable = ctx.executable._tool,
        arguments = [args],
        inputs = digests,
        outputs = [out],
        mnemonic = "KustomizeImageDigests",
        progress_message = "Writing image digests for %{label}",
    )
    return [DefaultInfo(files = depset([out]))]

kustomize_image_digests = rule(
    doc = """イメージの digest を images に書いた Kustomize の Component を出力する。

    出力は NAME/kustomization.yaml で、overlay の components からこのディレクトリを参照する。
    newName は、//tools/build:registry と //tools/build:repository_prefix の値から決める。
    """,
    implementation = _kustomize_image_digests_impl,
    attrs = REGISTRY_ATTRS | {
        "images": attr.string_keyed_label_dict(
            doc = "マニフェストの中のイメージの名前から、その digest を書いたファイルへの対応。",
            allow_files = True,
            mandatory = True,
        ),
        "_tool": attr.label(
            default = "//tools/build/kustomize_images",
            executable = True,
            cfg = "exec",
        ),
    },
)

def _repository_file_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".txt")
    ctx.actions.write(out, "{}/{}\n".format(repository_prefix(ctx), ctx.attr.repository))
    return [DefaultInfo(files = depset([out]))]

repository_file = rule(
    doc = "イメージやアーティファクトを push するリポジトリを、レジストリのビルドの設定から決めてファイルに書く。",
    implementation = _repository_file_impl,
    attrs = REGISTRY_ATTRS | {
        "repository": attr.string(
            doc = "接頭辞の後ろに付けるリポジトリの名前。",
            mandatory = True,
        ),
    },
)

# kubeconform に渡す Kubernetes の JSON スキーマ。マニフェストに新しい種類のリソースを足したら、ここにも足す。
_K8S_SCHEMAS = [
    "@k8s_schema_deployment_apps_v1//file",
    "@k8s_schema_namespace_v1//file",
    "@k8s_schema_service_v1//file",
]

def _kustomize_build_impl(name, visibility, srcs, overlay, image_digests, _kustomize, _kubeconform, _kubeconform_test, _image_digest_test, _schemas):
    # kustomize は base、overlay、生成した Component を1つのディレクトリの木の中で読む。
    # サンドボックスは入力をシンボリックリンクで置くが、kustomize はシンボリックリンクの
    # kustomization.yaml を読まないので、実体を一時ディレクトリにコピーしてからレンダリングする。
    native.genrule(
        name = name,
        srcs = srcs,
        outs = [name + ".yaml"],
        cmd = """
work=$$(mktemp -d)
for f in $(SRCS); do
  rel=$${{f#$(BINDIR)/}}
  rel=$${{rel#{package}/}}
  mkdir -p "$$work/$$(dirname "$$rel")"
  cp -L "$$f" "$$work/$$rel"
done
$(execpath {kustomize}) build "$$work/{overlay}" > $@
rm -rf "$$work"
""".format(package = native.package_name(), kustomize = _kustomize, overlay = overlay),
        tools = [_kustomize],
        visibility = visibility,
    )

    sh_test(
        name = name + "_kubeconform_test",
        size = "small",
        srcs = [_kubeconform_test],
        args = [
            "$(rootpath {})".format(_kubeconform),
            "$(rootpath :{})".format(name),
        ] + ["$(rootpath {})".format(s) for s in _schemas],
        data = [_kubeconform, ":" + name] + _schemas,
    )

    sh_test(
        name = name + "_image_digest_test",
        size = "small",
        srcs = [_image_digest_test],
        args = ["$(rootpath :{})".format(name)] + ["$(rootpath {})".format(d) for d in image_digests],
        data = [":" + name] + image_digests,
    )

kustomize_build = macro(
    doc = """overlay を kustomize build でレンダリングし、NAME.yaml を出力する。

    レンダリングした結果を kubeconform で検証する NAME_kubeconform_test と、
    すべてのイメージが digest で参照されていることを確かめる NAME_image_digest_test も作る。
    """,
    implementation = _kustomize_build_impl,
    attrs = {
        "srcs": attr.label_list(
            doc = "base、overlay、Component の kustomization.yaml とマニフェスト。",
            allow_files = True,
            mandatory = True,
            configurable = False,
        ),
        "overlay": attr.string(
            doc = "レンダリングする overlay の、このパッケージからの相対パス。",
            mandatory = True,
            configurable = False,
        ),
        "image_digests": attr.label_list(
            doc = "マニフェストで使われるはずのイメージの digest のファイル。",
            allow_files = True,
            configurable = False,
        ),
        "_kustomize": attr.label(default = "@multitool//tools/kustomize", configurable = False),
        "_kubeconform": attr.label(default = "@multitool//tools/kubeconform", configurable = False),
        "_kubeconform_test": attr.label(default = "//tools/build:kubeconform_test.sh", configurable = False),
        "_image_digest_test": attr.label(default = "//tools/build:image_digest_test.sh", configurable = False),
        "_schemas": attr.label_list(default = _K8S_SCHEMAS, configurable = False),
    },
)
