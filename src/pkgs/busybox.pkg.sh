set -e
set -u
set -o pipefail

SRC_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJ_DIR="$(dirname "$(cd "$SRC_DIR" &> /dev/null && pwd)")/.."

echo "PROJECT DIRECTORY: $PROJ_DIR"
source "$PROJ_DIR/src/termcolors.shlib"

function build_busybox() {
    local tool="BusyBox"
    echo "${bold}${aqua}${SCRIPT_NAME}: Building ${tool}${normal}"
    # out of source builds don't seem to work, so in-source we go
    pushd "$PROJ_DIR/3rdparty/busybox" >/dev/null
        make mrproper
        cp -v "$PROJ_DIR/3rdparty/BusyBox.config" .config
        make oldconfig
        make
    popd >/dev/null
}

function install_busybox() {
    local tool="BusyBox"
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/busybox" >/dev/null
        # we use some applets that require setuid rights
        install -v -m 4755 -o root -g root busybox "$PROJ_DIR/rootfs/System/bin/"
        install -v -m 644 -o root -g root docs/busybox.1 "$PROJ_DIR/rootfs/System/share/man/man1/"
        pushd "$PROJ_DIR/rootfs/System/share/man/man1" >/dev/null
            gzip -v -9 busybox.1
        popd >/dev/null
        # now make our symlinks
        pushd "$PROJ_DIR/rootfs/System/bin" >/dev/null
            for binary in $(./busybox --list); do
                ln -sv busybox "${binary}"
            done
        popd >/dev/null
        # now that things are installed, clean up the busybox source tree
        make mrproper
        rm -v -f docs/BusyBox.html
        rm -v -f docs/BusyBox.txt
        rm -v -f docs/busybox.1
        rm -v -r -f docs/busybox.net/
        rm -v -f docs/busybox.pod
        rm -v -f include/common_bufsiz.h.method
    popd >/dev/null
}

function clean_busybox() {
    local tool="BusyBox"
    echo "${bold}${aqua}${SCRIPT_NAME}: Cleaning ${tool}${normal}"
    rm -rfv "${PROJ_DIR}/3rdparty/busybox/build"
    git checkout -- "$PROJ_DIR/3rdparty/busybox-1.36.1/"
}
