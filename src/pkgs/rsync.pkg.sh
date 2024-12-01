set -e
set -u
set -o pipefail

SRC_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJ_DIR="$(dirname "$(cd "$SRC_DIR" &> /dev/null && pwd)")/.."

pkgname="RSync"
# shellcheck disable=SC2034
dependencies=(
    "bash"
    "binutils"
    "coreutils"
    "glibc-devel"
    "git-core"
    "grep"
    "gzip"
    "libacl-devel"
    "libattr-devel"
    "liblz4-devel"
    "libopenssl-3-devel"
    "libzstd-devel"
    "make"
    "openslp-devel"
    "popt-devel"
    "python3-CommonMark"
    "python3-cmarkgfm"
    "sed"
    "xxhash-devel"
    "zlib-devel"
    "zstd"
)

echo "PROJECT DIRECTORY: $PROJ_DIR"
source "$PROJ_DIR/src/termcolors.shlib"

function pkg_build() {
    echo "${bold}${aqua}${SCRIPT_NAME}: Building ${pkgname}${normal}"
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

function pkg_install() {
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${pkgname}${normal}"
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

function pkg_clean() {
    echo "${bold}${aqua}${SCRIPT_NAME}: Cleaning ${pkgname}${normal}"
    rm -rfv "${PROJ_DIR}/3rdparty/rsync/build"
    git checkout -- "$PROJ_DIR/3rdparty/rsync-3.3.0/"
}
