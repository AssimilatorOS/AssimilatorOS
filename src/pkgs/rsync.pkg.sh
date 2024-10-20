set -e
set -u
set -o pipefail

SRC_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJ_DIR="$(dirname "$(cd "$SRC_DIR" &> /dev/null && pwd)")/.."

source "$PROJ_DIR/src/termcolors.shlib"

function build_rsync() {
    local tool="RSync"
    echo "${bold}${aqua}${SCRIPT_NAME}: Building ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/rsync" >/dev/null
        mkdir -pv build
        pushd build >/dev/null
            ../configure --prefix=/System \
                         --bindir=/System/bin \
                         --libdir=/System/lib64 \
                         --sysconfdir=/System/cfg
            make -j4
        popd >/dev/null
    popd >/dev/null
}

function install_rsync() {
    local tool="RSync"
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/rsync" >/dev/null
        pushd build >/dev/null
            make DESTDIR="$PROJ_DIR/rootfs" install
        popd >/dev/null
        strip -v -s "$PROJ_DIR/rootfs/bin/rsync"
    popd >/dev/null
    pushd "$PROJ_DIR/rootfs/System/share/man" >/dev/null
        for SECTION in 1 5; do
            find . -type f -name "rsync*.$SECTION" -exec gzip -v -9 {} \;
        done
    popd >/dev/null
}

function clean_rsync() {
    local tool="RSync"
    echo "${bold}${aqua}${SCRIPT_NAME}: Cleaning ${tool}${normal}"
    rm -rfv "${PROJ_DIR}/3rdparty/rsync/build"
    git checkout -- "$PROJ_DIR/3rdparty/rsync-3.3.0/"
}
