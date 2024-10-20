#!/bin/bash

set -e
set -u
set -o pipefail

SCRIPT_NAME="$(basename "$0")"

SRC_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJ_DIR="$(dirname "$(cd "$SRC_DIR" &> /dev/null && pwd)")"

if [[ "${EUID}" -ne 0 ]]; then
    echo "${SCRIPT_NAME}: Please run as root. Exiting" >&2
    exit 13
else
    echo -e "${SCRIPT_NAME}: Running with elevated privileges\n" >&2
fi

echo "${SCRIPT_NAME}: Cleaning ${PROJ_DIR}"
umount -v /dev/loop0p1 ||:
umount -v /dev/loop0p2 ||:
losetup -v -D ||:
rm -fv "${PROJ_DIR}/vdisk.img" ||:
rm -rfv "${PROJ_DIR}/3rdparty/busybox/build"     ||:
rm -rfv "${PROJ_DIR}/3rdparty/grub/build"        ||:
rm -rfv "${PROJ_DIR}/3rdparty/pam/build"         ||:
rm -rfv "${PROJ_DIR}/3rdparty/jq/build"          ||:
rm -rfv "${PROJ_DIR}/3rdparty/sqlite3/build"     ||:
rm -rfv "${PROJ_DIR}/3rdparty/rsync/build"       ||:
rm -rfv "${PROJ_DIR}/3rdparty/nano/build"        ||:
# needed since XFS progs cannot be built outside of source
rm -rfv "${PROJ_DIR}/3rdparty/xfsprogs/../build" ||:
rm -rfv "${PROJ_DIR}/3rdparty/dialog/build"      ||:
rm -rfv "${PROJ_DIR}/3rdparty/ncurses/build_tic" ||:
rm -rfv "${PROJ_DIR}/3rdparty/ncurses/build"     ||:
pushd "${PROJ_DIR}/3rdparty/grub" >/dev/null
    rm -rfv __pycache__/
    rm -fv docs/grub2.info
    rm -fv docs/grub2.info-1
    rm -fv docs/grub2.info-2
    rm -fv docs/grub2.texi
    rm -fv po/*.po~
    rm -fv po/grub2.pot
popd >/dev/null
pushd "${PROJ_DIR}" >/dev/null
    pushd "$PROJ_DIR/3rdparty/efivar" >/dev/null
        make clean ||:
    popd >/dev/null
    pushd "$PROJ_DIR/3rdparty/efibootmgr" >/dev/null
        LOADER="grub.efi"  # default loader
        VENDOR="AssimilatorOS"
        make OS_VENDOR="$VENDOR" EFI_LOADER="$LOADER" EFIDIR="$VENDOR" clean ||:
        # remove extra stuff from compressing man pages
        rm -vf src/*.8.gz ||:
    popd >/dev/null
    git checkout -- "$PROJ_DIR/3rdparty/busybox-1.36.1/"
    git checkout -- "$PROJ_DIR/3rdparty/grub-2.12/"
    git checkout -- "$PROJ_DIR/3rdparty/linux-5.10.226/"
    git checkout -- "$PROJ_DIR/3rdparty/ncurses-6.5/"
popd >/dev/null

echo "${SCRIPT_NAME}: Clean up complete"
