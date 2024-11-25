set -e
set -u
set -o pipefail

SRC_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJ_DIR="$(dirname "$(cd "$SRC_DIR" &> /dev/null && pwd)")/.."

pkgname="BusyBox Static"
# shellcheck disable=SC2034
dependencies=(
    "glibc-devel-static"
)

echo "PROJECT DIRECTORY: $PROJ_DIR"
source "$PROJ_DIR/src/termcolors.shlib"

function pkg_build() {
    echo "${bold}${aqua}${SCRIPT_NAME}: Building ${pkgname}${normal}"
    # out of source builds don't seem to work, so in-source we go
    pushd "$PROJ_DIR/3rdparty/busybox" >/dev/null
        make mrproper
        cp -v "$PROJ_DIR/3rdparty/BusyBox_Static.config" .config
        make oldconfig
        make
    popd >/dev/null
}

function pkg_install() {
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${pkgname}${normal}"
    pushd "$PROJ_DIR/3rdparty/busybox" >/dev/null
        install -v -m 4755 -o root -g root busybox "$PROJ_DIR/rootfs/System/bin/busybox-static"
        # the static version of busybox is for use in the initramfs, so don't install extra stuff
        make mrproper
        rm -v -f docs/BusyBox.html
        rm -v -f docs/BusyBox.txt
        rm -v -f docs/busybox.1
        rm -v -r -f docs/busybox.net/
        rm -v -f docs/busybox.pod
        rm -v -f include/common_bufsiz.h.method
    popd >/dev/null
}

function pkg_clean() {
    echo "${bold}${aqua}${SCRIPT_NAME}: Cleaning ${pkgname}${normal}"
    git checkout -- "$PROJ_DIR/3rdparty/busybox-1.37.0/"
}
