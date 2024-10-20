set -e
set -u
set -o pipefail

SRC_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJ_DIR="$(dirname "$(cd "$SRC_DIR" &> /dev/null && pwd)")/.."

source "$PROJ_DIR/src/termcolors.shlib"

function build_sqlite3() {
    local tool="SQLite3"
    echo "${bold}${aqua}${SCRIPT_NAME}: Building ${tool}${normal}"
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

function install_sqlite3() {
    local tool="SQLite3"
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${tool}${normal}"
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

function clean_sqlite3() {
    local tool="SQLite3"
    echo "${bold}${aqua}${SCRIPT_NAME}: Cleaning ${tool}${normal}"
    rm -rfv "${PROJ_DIR}/3rdparty/sqlite3/build"
    git checkout -- "$PROJ_DIR/3rdparty/sqlite-autoconf-3460100/"
}
