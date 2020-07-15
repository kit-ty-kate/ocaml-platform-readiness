#!/bin/bash

function send_msg_aux {
    curl -s -X POST -H 'Content-type: application/json' --data "{\"type\":\"mrkdwn\", \"text\":\"$1\"}" "$2"
}

function send_debug_msg {
    send_msg_aux "$1" "$(cat debug-service.txt)"
}

function send_msg {
    send_msg_aux "$1" "$(cat service.txt)"
}

msg=

function add_msg {
    msg+="${msg:+\n}$1"
}

distro=debian-10

VERSIONS="
    beta:4.11
    trunk:4.12
"

PACKAGES="
    opam-devel;git://github.com/ocaml/opam.git
    dune;git://github.com/ocaml/dune.git
    merlin;git://github.com/ocaml/merlin.git
    ocaml-lsp-server;git://github.com/ocaml/ocaml-lsp.git
    odoc;git://github.com/ocaml/odoc.git
    ocamlformat;git://github.com/ocaml-ppx/ocamlformat.git
    ocp-indent;git://github.com/OCamlPro/ocp-indent.git
    ocamlfind;git://github.com/ocaml/ocamlfind.git
    ocamlbuild;git://github.com/ocaml/ocamlbuild.git
    ppxlib;git://github.com/ocaml-ppx/ppxlib.git
    ocaml-migrate-parsetree;git://github.com/ocaml-ppx/ocaml-migrate-parsetree.git
    mdx;git://github.com/realworldocaml/mdx.git
    utop;git://github.com/ocaml-community/utop.git
    dune-release;git://github.com/ocamllabs/dune-release.git
    opam-publish;git://github.com/ocaml/opam-publish.git
"

# TODO: Test the infrastructure section
# TODO: Test git://github.com/ocamllabs/vscode-ocaml-platform.git (doesn't use dune)

for ver in $VERSIONS; do
    ver_name=$(echo "$ver" | cut -d: -f1)
    ver=$(echo "$ver" | cut -d: -f2)

    add_msg ""
    add_msg ""
    add_msg "On OCaml $ver ($ver_name):"

    for pkg in $PACKAGES; do
        pkgname=$(echo "$pkg" | cut -d';' -f1)
        repo=$(echo "$pkg" | cut -d';' -f2)

        build="
            git -C opam-repository pull origin master
            opam update
            opam depext -ivj72 '$pkgname' && res=0 || res=\$?
            if [ \$res = 20 ]; then
                opam pin add -yn "$repo"
                opam depext -ivj72 '$pkgname' && res=0 || res=\$?
                if [ \$res = 20 ]; then
                    opam repository add -a alpha git://github.com/kit-ty-kate/opam-alpha-repository.git
                    opam depext -ivj72 '$pkgname' && res=0 || res=\$?
                    if [ \$res = 20 ]; then
                        opam pin remove "$repo"
                        opam depext -ivj72 '$pkgname' && res=0 || res=\$?
                        echo step=4=\$res
                        exit 0
                    fi
                    echo step=3=\$res
                    exit 0
                fi
                echo step=2=\$res
                exit 0
            fi
            echo step=1=\$res
            exit 0
        "

        log="$pkgname-$ver.log"

        echo "Checking $pkgname on OCaml $ver..."

        echo "$build" | docker run --rm -i ocurrent/opam:$distro-ocaml-$ver bash -ex &> "$log"

        state=$(cat "$log" | grep "echo step=")
        state_num=$(echo "$state" | cut -d= -f2)
        state=$(echo "$state" | cut -d= -f3)

        case "$state,$state_num" in
            0,1) add_msg "      - :green_heart: \`$pkgname\` has a stable version compatible.";;
            0,2) add_msg "      - :yellow_heart: \`$pkgname\` has its master branch compatible.";;
            0,3) add_msg "      - :yellow_heart: \`$pkgname\` has its master branch compatible but some of its dependencies are still to be released. See https://github.com/kit-ty-kate/opam-alpha-repository.git for more details.";;
            0,4) add_msg "      - :vertical_traffic_light: \`$pkgname\` has some PR opened compatible. See https://github.com/kit-ty-kate/opam-alpha-repository.git for more details.";;
           20,*) add_msg "      - :construction: \`$pkgname\` is not compatible yet.";;
           31,*)
                if grep -q "^+- The following actions were aborted$" "$log"; then
                    add_msg "      - :triangular_flag_on_post: Some dependencies of \`$pkgname\` failed."
                else
                    add_msg "      - :triangular_flag_on_post: \`$pkgname\` failed to build."
                fi;;
            *) send_debug_msg "Something went wrong while testing $pkgname on OCaml $ver."; exit 1;;
        esac
    done
done

send_msg "$msg"
