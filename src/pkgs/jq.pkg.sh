set -e
set -u
set -o pipefail

SRC_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJ_DIR="$(dirname "$(cd "$SRC_DIR" &> /dev/null && pwd)")/.."

source "$PROJ_DIR/src/termcolors.shlib"

function build_jq() {
    local tool="JQ"
    echo "${bold}${aqua}${SCRIPT_NAME}: Building ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/jq" >/dev/null
        mkdir -pv build
        pushd build >/dev/null
            ../configure --prefix=/System \
                         --bindir=/System/bin \
                         --libdir=/System/lib64 \
                         --sysconfdir=/System/cfg \
                         --disable-docs
            make -j4
        popd >/dev/null
    popd >/dev/null
}

function install_jq() {
    local tool="JQ"
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/jq" >/dev/null
        pushd build >/dev/null
            make DESTDIR="$PROJ_DIR/rootfs" install
        popd >/dev/null
    popd >/dev/null
    rm -vf "$PROJ_DIR/rootfs/lib64/libjq.a"
    rm -vf "$PROJ_DIR/rootfs/lib64/libjq.la"
    # compress the man page for jq
    pushd "$PROJ_DIR/rootfs/System/share/man/man1" >/dev/null
        gzip -v -9 jq.1
    popd >/dev/null
    strip -v -s "$PROJ_DIR/rootfs/bin/jq"
    strip -v -s "$PROJ_DIR/rootfs/lib64/libjq.so.1.0.4"
}

function clean_jq() {
    local tool="JQ"
    echo "${bold}${aqua}${SCRIPT_NAME}: Cleaning ${tool}${normal}"
    rm -rfv "${PROJ_DIR}/3rdparty/jq/build"
    git checkout -- "$PROJ_DIR/3rdparty/jq-1.7.1/"
}
