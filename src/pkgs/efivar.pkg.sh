set -e
set -u
set -o pipefail

SRC_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJ_DIR="$(dirname "$(cd "$SRC_DIR" &> /dev/null && pwd)")/.."

source "$PROJ_DIR/src/termcolors.shlib"

function build_efivar() {
    local tool="EFI Var tools"
    echo "${bold}${aqua}${SCRIPT_NAME}: Building ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/efivar" >/dev/null
        make -j4
    popd >/dev/null
}

function install_efivar() {
    local tool="EFI Var tools"
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/efivar" >/dev/null
        make DESTDIR="$PROJ_DIR/rootfs" \
             BINDIR="/System/bin" \
             LIBDIR="/System/lib64" \
             DATADIR="/System/share" \
             INCLUDEDIR="/System/include" install
    popd >/dev/null
    # compress the man pages
    pushd "$PROJ_DIR/rootfs/System/share/man" >/dev/null
        for SECTION in 1 3; do
            find . -type f -name "efi*.$SECTION" -exec gzip -v -9 {} \;
        done
    popd >/dev/null
    strip -v -s "$PROJ_DIR/rootfs/bin/efisecdb"
    strip -v -s "$PROJ_DIR/rootfs/bin/efivar"
    # shellcheck disable=SC2086
    strip -v -s $PROJ_DIR/rootfs/lib64/libefi*
}

function clean_efivar() {
    local tool="EFI Var tools"
    echo "${bold}${aqua}${SCRIPT_NAME}: Cleaning ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/efivar" >/dev/null
        make clean
    popd >/dev/null
}
