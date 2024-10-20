set -e
set -u
set -o pipefail

SRC_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJ_DIR="$(dirname "$(cd "$SRC_DIR" &> /dev/null && pwd)")"

source "$PROJ_DIR/src/termcolors.shlib"

function build_dialog() {
    local tool="Dialog"
    echo "${bold}${aqua}${SCRIPT_NAME}: Building ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/dialog" >/dev/null
        mkdir -pv build
        pushd build >/dev/null
            LDFLAGS="-L${PROJ_DIR}/rootfs/System/lib64" \
            CPPFLAGS="-I${PROJ_DIR}/rootfs/System/include/ncursesw -I${PROJ_DIR}/rootfs/System/include" \
            PKG_CONFIG_PATH="${PROJ_DIR}/rootfs/lib64/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig" \
            ../configure --prefix=/System \
                         --bindir=/System/bin \
                         --libdir=/System/lib64 \
                         --sysconfdir=/System/cfg \
                         --with-ncursesw
            make -j4
        popd >/dev/null
    popd >/dev/null
}

function install_dialog() {
    local tool="Dialog"
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/dialog" >/dev/null
        pushd build >/dev/null
            make DESTDIR="$PROJ_DIR/rootfs" install
        popd >/dev/null
        strip -v -s "$PROJ_DIR/rootfs/bin/dialog"
    popd >/dev/null
    pushd "$PROJ_DIR/rootfs/System/share/man" >/dev/null
        gzip -v -9 man1/dialog.1
    popd >/dev/null
    # we don't want the static library
    rm -fv "$PROJ_DIR/rootfs/lib64/libdialog.a"
}

function clean_dialog() {
    local tool="Dialog"
    echo "${bold}${aqua}${SCRIPT_NAME}: Cleaning ${tool}${normal}"
    rm -rfv "${PROJ_DIR}/3rdparty/dialog/build"
    git checkout -- "$PROJ_DIR/3rdparty/dialog-1.3-20240619/"
}
