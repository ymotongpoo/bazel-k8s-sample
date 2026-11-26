"""Go のサービスの実行ファイルと、その共通のテストを定義するマクロ。"""

load("@rules_go//go:def.bzl", "go_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

def _go_service_impl(name, visibility, embed, _healthz_test):
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

go_service = macro(
    doc = """Go のサービスを定義する。

    name の go_binary と、それを起動して GET /healthz を確かめる name_healthz_test を作る。
    サービスは --addr で待ち受けるアドレスを受け取り、待ち受けたアドレスを
    "listening on ADDR" の形でログに出す必要がある。
    """,
    implementation = _go_service_impl,
    attrs = {
        "embed": attr.label_list(
            doc = "サービスの main パッケージの go_library。",
            mandatory = True,
            configurable = False,
        ),
        "_healthz_test": attr.label(
            default = "//tools/build:healthz_test.sh",
            configurable = False,
        ),
    },
)
