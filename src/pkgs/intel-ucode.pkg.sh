set -e
set -u
set -o pipefail

SRC_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJ_DIR="$(dirname "$(cd "$SRC_DIR" &> /dev/null && pwd)")/.."

echo "PROJECT DIRECTORY: $PROJ_DIR"
source "$PROJ_DIR/src/termcolors.shlib"

function install_intel_fw() {
    local tool="Intel Microcode Firmware"
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${tool}${normal}"
    if [[ ! -d "$PROJ_DIR/rootfs/lib/firmware" ]]; then
        install -d -m 755 -o root -g root "$PROJ_DIR/rootfs/lib/firmware"
    fi
    # copy the firmware into place
    cp -av "$PROJ_DIR/3rdparty/Intel-ucode/intel-ucode" "$PROJ_DIR/rootfs/lib/firmware/"
    chown -R root:root "$PROJ_DIR/rootfs/lib/firmware"
}
