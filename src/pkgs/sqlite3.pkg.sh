set -e
set -u
set -o pipefail

SRC_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJ_DIR="$(dirname "$(cd "$SRC_DIR" &> /dev/null && pwd)")/.."

pkgname="SQLite3"
# shellcheck disable=SC2034
dependencies=(
    "binutils"
    "coreutils"
    "glibc-devel"
    "git-core"
    "gzip"
    "make"
    "readline-devel"
    "zlib-devel"
)

echo "PROJECT DIRECTORY: $PROJ_DIR"
source "$PROJ_DIR/src/termcolors.shlib"

function pkg_build() {
    echo "${bold}${aqua}${SCRIPT_NAME}: Building ${pkgname}${normal}"
    pushd "$PROJ_DIR/3rdparty/sqlite3" >/dev/null
        mkdir -pv build
        pushd build >/dev/null
            ../configure --prefix=/System \
                         --bindir=/System/bin \
                         --libdir=/System/lib64 \
                         --sysconfdir=/System/cfg \
                         --enable-readline \
                         --enable-session
            make -j4
        popd >/dev/null
    popd >/dev/null
}

function pkg_install() {
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${pkgname}${normal}"
    pushd "$PROJ_DIR/3rdparty/sqlite3" >/dev/null
        pushd build >/dev/null
            make DESTDIR="$PROJ_DIR/rootfs" install
        popd >/dev/null
        rm -vf "$PROJ_DIR/rootfs/lib64/libsqlite3.a"
        rm -vf "$PROJ_DIR/rootfs/lib64/libsqlite3.la"
        strip -v -s "$PROJ_DIR/rootfs/bin/sqlite3"
        strip -v -s "$PROJ_DIR/rootfs/lib64/libsqlite3.so.0.8.6"
    popd >/dev/null
    pushd "$PROJ_DIR/rootfs/System/share/man/man1" >/dev/null
        gzip -v -9 sqlite3.1
    popd >/dev/null
}

function pkg_clean() {
    echo "${bold}${aqua}${SCRIPT_NAME}: Cleaning ${pkgname}${normal}"
    rm -rfv "${PROJ_DIR}/3rdparty/sqlite3/build"
    git checkout -- "$PROJ_DIR/3rdparty/sqlite-autoconf-3460100/"
}
