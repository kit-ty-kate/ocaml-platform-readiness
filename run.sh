#!/bin/bash

function send_msg_aux {
    curl -X POST -H 'Content-type: application/json' --data "{\"text\":\"$1\"}" "$2"
}

function send_debug_msg {
    send_msg "$1" "$(cat debug-service.txt)"
}

function send_msg {
    send_msg "$1" "$(cat service.txt)"
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

for pkg in $PACKAGES; do
    pkgname=$(echo "$pkg" | cut -d';' -f1)
    repo=$(echo "$pkg" | cut -d';' -f2)

    build="
        git -C opam-repository pull origin master
        opam update
        opam depext -iv '$pkgname'
        if [ \$? = 20 ]; then
            opam pin add "$repo"
            if [ \$? = 20 ]; then
                opam repository add alpha git://github.com/kit-ty-kate/opam-alpha-repository.git
                opam depext -iv '$pkgname'
                if [ \$? = 20 ]; then
                    opam pin remove "$repo"
                    opam depext -iv '$pkgname'
                    echo step-4=\$?
                    exit 0
                fi
                echo step-3=\$?
                exit 0
            fi
            echo step-2=\$?
            exit 0
        fi
        echo step-1=\$?
        exit 0
    "

    for ver in $VERSIONS; do
        ver_name=$(echo "$ver" | cut -d: -f1)
        ver=$(echo "$ver" | cut -d: -f2)

        log=$(echo "$build" | docker run --rm -i ocurrent/opam:$distro-ocaml-$ver bash -ex)
        state=$(echo "$log" | grep "echo step-")
        state_num=$(echo "$state" | cut -d- -f2)
        state=$(echo "$state" | cut -d= -f2)

        case "$state/$state_num" in
            0,1) msg="$pkgname has a stable version compatible with OCaml $ver ($ver_name)";;
            0,2) msg="$pkgname has its master branch compatible with OCaml $ver ($ver_name)";;
            0,3) msg="$pkgname has its master branch compatible with OCaml $ver ($ver_name) but some of its dependencies are still to be released. See https://github.com/kit-ty-kate/opam-alpha-repository.git for more details.";;
            0,4) msg="$pkgname has some PR opened compatible with OCaml $ver ($ver_name). See https://github.com/kit-ty-kate/opam-alpha-repository.git for more details.";;
           31,*)
                if grep -q "^+- The following actions were aborted$"; then
                    msg="Some dependencies of $pkgname failed with OCaml $ver ($ver_name)"
                else
                    msg="$pkgname failed to build with OCaml $ver ($ver_name)"
                fi;;
            *) send_debug_msg "Something went wrong while testing $pkgname on OCaml $ver"; exit 1;;
        esac

        send_msg "$msg"
    done
done
