set -e
set -u
set -o pipefail

SRC_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJ_DIR="$(dirname "$(cd "$SRC_DIR" &> /dev/null && pwd)")/.."

pkgname="Linux Kernel"
# shellcheck disable=SC2034
dependencies=(
    "coreutils"
    "git-core"
    "glibc-devel"
    "make"
    "patterns-devel-base-devel_kernel"
)

echo "PROJECT DIRECTORY: $PROJ_DIR"
source "$PROJ_DIR/src/termcolors.shlib"

function pkg_build() {
    echo "${bold}${aqua}${SCRIPT_NAME}: Building ${pkgname}${normal}"
    pushd "$PROJ_DIR/3rdparty/linux" >/dev/null
        # ensure we are working with a clean tree
        rm -v -r -f build
        # now lets build this out-of-source
        mkdir -v build
        cd build
        make KBUILD_SRC=../ -f ../Makefile mrproper
        cp -v "$PROJ_DIR/configs/LinuxKernel.config" .config
        make KBUILD_SRC=../ -f ../Makefile oldconfig
        make -j4
        cd -
    popd >/dev/null
}

function pkg_install() {
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${pkgname}${normal}"
    pushd "$PROJ_DIR/3rdparty/linux" >/dev/null
        cd build
        make INSTALL_PATH=../../../rootfs/System/boot install ||:
        make INSTALL_MOD_PATH=../../../rootfs/System modules_install ||:
        cd -
        # clean up after ourselves
        rm -v -r -f build
    popd >/dev/null
}

function pkg_clean() {
    echo "${bold}${aqua}${SCRIPT_NAME}: Cleaning ${pkgname}${normal}"
    git checkout -- "$PROJ_DIR/3rdparty/linux-5.10.226/"
}
