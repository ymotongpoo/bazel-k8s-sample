"""イメージの digest を Kustomize の Component に書き出すルール。"""

def _kustomize_image_digests_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + "/kustomization.yaml")

    args = ctx.actions.args()
    args.add("-out", out)
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
    """,
    implementation = _kustomize_image_digests_impl,
    attrs = {
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
