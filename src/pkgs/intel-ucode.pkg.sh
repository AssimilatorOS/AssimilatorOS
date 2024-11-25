set -e
set -u
set -o pipefail

SRC_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJ_DIR="$(dirname "$(cd "$SRC_DIR" &> /dev/null && pwd)")/.."

pkgname="Intel Microcode Firmware"
# shellcheck disable=SC2034
dependencies=(
    "coreutils"
)

echo "PROJECT DIRECTORY: $PROJ_DIR"
source "$PROJ_DIR/src/termcolors.shlib"

function pkg_build() {
    true
}

function pkg_install() {
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${pkgname}${normal}"
    if [[ ! -d "$PROJ_DIR/rootfs/lib/firmware" ]]; then
        install -d -v -m 755 -o root -g root "$PROJ_DIR/rootfs/lib/firmware"
    fi
    # copy the firmware into place
    cp -av "$PROJ_DIR/3rdparty/Intel-ucode/intel-ucode" "$PROJ_DIR/rootfs/lib/firmware/"
    chown -Rv root:root "$PROJ_DIR/rootfs/lib/firmware"
}

function pkg_clean() {
    true
}
