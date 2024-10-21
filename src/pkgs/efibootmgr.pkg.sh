set -e
set -u
set -o pipefail

SRC_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJ_DIR="$(dirname "$(cd "$SRC_DIR" &> /dev/null && pwd)")/.."

source "$PROJ_DIR/src/termcolors.shlib"

function build_efibootmgr() {
    local tool="EFI Boot Manager"
    echo "${bold}${aqua}${SCRIPT_NAME}: Building ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/efibootmgr" >/dev/null
        sed -e '/extern int efi_set_verbose/d' -i "src/efibootmgr.c"
        LOADER="grub.efi"  # default loader
        VENDOR="AssimilatorOS"
        LIBSRCHDIR="$PROJ_DIR/rootfs/System/lib64"
        HEADERSRCHDIR1="$PROJ_DIR/rootfs/System/include"
        HEADERSRCHDIR2="$PROJ_DIR/rootfs/System/include/efivar"
        OPT_FLAGS="-O2 -g -m64 -fmessage-length=0 -D_FORTIFY_SOURCE=2 -fstack-protector -funwind-tables -fasynchronous-unwind-tables"
        PKG_CONFIG_PATH="$PROJ_DIR/rootfs/System/lib64/pkgconfig/" \
        make CFLAGS="$OPT_FLAGS -flto -fPIE -pie -L$LIBSRCHDIR -I$HEADERSRCHDIR1 -I$HEADERSRCHDIR2" \
             CPPFLAGS="-I$HEADERSRCHDIR1 -I$HEADERSRCHDIR2" \
             OS_VENDOR="$VENDOR" EFI_LOADER="$LOADER" EFIDIR="$VENDOR" prefix=/System sbindir=/System/sbin
    popd >/dev/null
}

function install_efibootmgr() {
    local tool="EFI Boot Manager"
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/efibootmgr" >/dev/null
        install -v -m 755 -o root -g root src/efibootdump "$PROJ_DIR/rootfs/System/sbin/"
        install -v -m 755 -o root -g root src/efibootmgr  "$PROJ_DIR/rootfs/System/sbin/"
        gzip -v -9 src/efibootdump.8
        gzip -v -9 src/efibootmgr.8
        install -v -m 644 -o root -g root src/efibootdump.8.gz "$PROJ_DIR/rootfs/System/share/man/man8/"
        install -v -m 644 -o root -g root src/efibootmgr.8.gz  "$PROJ_DIR/rootfs/System/share/man/man8/"
        strip -v -s "$PROJ_DIR/rootfs/System/sbin/efibootdump"
        strip -v -s "$PROJ_DIR/rootfs/System/sbin/efibootmgr"
    popd >/dev/null
}

function clean_efibootmgr() {
    local tool="EFI Boot Manager"
    echo "${bold}${aqua}${SCRIPT_NAME}: Cleaning ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/efibootmgr" >/dev/null
        LOADER="grub.efi"  # default loader
        VENDOR="AssimilatorOS"
        make OS_VENDOR="$VENDOR" EFI_LOADER="$LOADER" EFIDIR="$VENDOR" clean
        # remove extra stuff from compressing man pages
        rm -vf src/*.8.gz
    popd >/dev/null
}
