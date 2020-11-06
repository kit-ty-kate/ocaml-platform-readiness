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
    beta:4.12
"

PACKAGES="
    opam-devel;git://github.com/ocaml/opam.git
    dune;git://github.com/ocaml/dune.git
    merlin;git://github.com/ocaml/merlin.git
    ocaml-lsp-server;git://github.com/ocaml/ocaml-lsp.git
    vscode-ocaml-platform;git://github.com/ocamllabs/vscode-ocaml-platform.git
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

for ver in $VERSIONS; do
    ver_name=$(echo "$ver" | cut -d: -f1)
    ver=$(echo "$ver" | cut -d: -f2)

    docker_img=ocurrent/opam:$distro-ocaml-$ver
    docker pull -q "$docker_img" &> /dev/null

    add_msg ""
    add_msg ""
    add_msg "On OCaml $ver ($ver_name):"

    for pkg in $PACKAGES; do
        pkgname=$(echo "$pkg" | cut -d';' -f1)
        repo=$(echo "$pkg" | cut -d';' -f2)

        build="
            export OPAMSOLVERTIMEOUT=500
            git -C opam-repository pull origin master
            opam update
            if opam show '$pkgname'; then
                opam pin add -ynk version '$pkgname' \$(opam show -f version: '$pkgname' | sed 's/\"//g')
                opam depext -ivj72 '$pkgname' && res=0 || res=\$?
                step=1
            fi
            if [ \$res = 20 ]; then
                if opam show '$pkgname'; then
                    opam repository add -a alpha git://github.com/kit-ty-kate/opam-alpha-repository.git
                    opam depext -ivj72 '$pkgname' && res=0 || res=\$?
                    step=2
                fi
                if [ \$res = 20 ]; then
                    opam pin add -yn '$repo'
                    opam depext -ivj72 '$pkgname' && res=0 || res=\$?
                    step=3
                    if [ \$res = 20 ]; then
                        if [ \$(opam show -f repository '$pkgname') = alpha ]; then
                            opam pin add -ynk version '$pkgname' \$(opam show -f version: '$pkgname' | sed 's/\"//g')
                            opam depext -ivj72 '$pkgname' && res=0 || res=\$?
                            step=4
                        fi
                    fi
                fi
            fi
            if [ \$res = 0 ]; then
                opam depext -tv '$pkgname' || true
                opam reinstall -tv '$pkgname' && res_test=0 || res_test=\$?
            else
                res_test=31
            fi
            echo step=\$step
            echo step_res=\$res
            echo step_res_test=\$res_test
            exit 0
        "

        log="$pkgname-$ver.log"

        echo "Checking $pkgname on OCaml $ver..."

        echo "$build" | docker run --rm -i "$docker_img" bash -ex &> "$log"

        state_num=$(cat "$log" | grep "echo step=" | cut -d= -f2)
        state=$(cat "$log" | grep "echo step_res=" | cut -d= -f2)
        state_test=$(cat "$log" | grep "echo step_res_test=" | cut -d= -f2)

        opam_alpha_repository="<https://github.com/kit-ty-kate/opam-alpha-repository.git|opam-alpha-repository>"

        case "$state_test" in
            0) test_msg="succeeded :green_heart:";;
           20) test_msg="could not be tested :construction:";;
           31) test_msg="failed :triangular_flag_on_post:";;
            *) send_debug_msg "Something went wrong. Got state_test = $state_test..."; exit 1;;
        esac

        case "$state,$state_num" in
            0,1) add_msg "      - :green_heart: \`$pkgname\` has its latest stable version compatible (tests: $test_msg).";;
            0,2) add_msg "      - :yellow_heart: \`$pkgname\` has its latest stable version compatible but some of its dependencies are still to be released (tests: $test_msg)";;
            0,3) add_msg "      - :yellow_heart: \`$pkgname\` has its master branch compatible (tests: $test_msg)";;
            0,4) add_msg "      - :vertical_traffic_light: \`$pkgname\` has some PR opened compatible (tests: $test_msg). See $opam_alpha_repository for more details.";;
           20,*) add_msg "      - :construction: \`$pkgname\` is not compatible yet.";;
           31,*)
                case "$state_num" in
                1) location="using its latest stable versions.";;
                2) location="using its latest stable version.";;
                3) location="using its master branch and $opam_alpha_repository.";;
                4) location="using a supposedly compatible branch. See $opam_alpha_repository for more details.";;
                *) send_debug_msg "Something went wrong. Got state_num = $state_num..."; exit 1;;
                esac
                if grep -q "^+- The following actions were aborted$" "$log"; then
                    add_msg "      - :triangular_flag_on_post: Some dependencies of \`$pkgname\` failed $location."
                else
                    add_msg "      - :triangular_flag_on_post: \`$pkgname\` failed to build $location."
                fi;;
            *) send_debug_msg "Something went wrong while testing $pkgname on OCaml $ver."; exit 1;;
        esac
    done
done

send_msg "$msg"
