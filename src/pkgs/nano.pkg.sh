set -e
set -u
set -o pipefail

SRC_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJ_DIR="$(dirname "$(cd "$SRC_DIR" &> /dev/null && pwd)")/.."

source "$PROJ_DIR/src/termcolors.shlib"

function build_nano() {
    local tool="GNU Nano"
    echo "${bold}${aqua}${SCRIPT_NAME}: Building ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/nano" >/dev/null
        mkdir -pv build
        pushd build >/dev/null
            LDFLAGS="-L${PROJ_DIR}/rootfs/System/lib64" \
            CPPFLAGS="-I${PROJ_DIR}/rootfs/System/include/ncursesw -I${PROJ_DIR}/rootfs/System/include" \
            PKG_CONFIG_PATH="${PROJ_DIR}/rootfs/lib64/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig" \
            ../configure --prefix=/System \
                         --bindir=/System/bin \
                         --libdir=/System/lib64 \
                         --sysconfdir=/System/cfg \
                         --enable-utf8 \
                         --enable-year2038
            make -j4
        popd >/dev/null
    popd >/dev/null
}

function install_nano() {
    local tool="GNU Nano"
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/nano" >/dev/null
        pushd build >/dev/null
            make DESTDIR="$PROJ_DIR/rootfs" install
        popd >/dev/null
        strip -v -s "$PROJ_DIR/rootfs/bin/nano"
    popd >/dev/null
    pushd "$PROJ_DIR/rootfs/System/share/man" >/dev/null
        for SECTION in 1 5; do
            find . -type f -name "nano*.$SECTION" -exec gzip -v -9 {} \;
        done
        gzip -v -9 man1/rnano.1
    popd >/dev/null
    # install the system-wide nanorc
    install -v -m 644 -o root -g root "$PROJ_DIR/configs/nanorc" "$PROJ_DIR/rootfs/System/cfg/nanorc"
}

function clean_nano() {
    local tool="GNU Nano"
    echo "${bold}${aqua}${SCRIPT_NAME}: Cleaning ${tool}${normal}"
    rm -rfv "${PROJ_DIR}/3rdparty/nano/build"
    git checkout -- "$PROJ_DIR/3rdparty/nano-8.2/"
}
