set -e
set -u
set -o pipefail

SRC_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJ_DIR="$(dirname "$(cd "$SRC_DIR" &> /dev/null && pwd)")/.."

pkgname="GNU Nano"
# shellcheck disable=SC2034
dependencies=(
    "binutils"
    "coreutils"
    "file-devel"
    "findutils"
    "glibc-devel"
    "git-core"
    "gzip"
    "make"
    "ncurses-devel"
)

echo "PROJECT DIRECTORY: $PROJ_DIR"
source "$PROJ_DIR/src/termcolors.shlib"

function pkg_build() {
    echo "${bold}${aqua}${SCRIPT_NAME}: Building ${pkgname}${normal}"
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

function pkg_install() {
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${pkgname}${normal}"
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

function pkg_clean() {
    echo "${bold}${aqua}${SCRIPT_NAME}: Cleaning ${pkgname}${normal}"
    rm -rfv "${PROJ_DIR}/3rdparty/nano/build"
    git checkout -- "$PROJ_DIR/3rdparty/nano-8.2/"
}
