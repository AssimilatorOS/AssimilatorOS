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
rm -rfv "${PROJ_DIR}/3rdparty/busybox/build" ||:
rm -rfv "${PROJ_DIR}/3rdparty/grub/build" ||:
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
    cd 3rdparty/efivar
    make clean ||:
    cd -
    git checkout -- "$PROJ_DIR/3rdparty/busybox-1.36.1/"
    git checkout -- "$PROJ_DIR/3rdparty/grub-2.12/"
    git checkout -- "$PROJ_DIR/3rdparty/linux-5.10.226/"
popd >/dev/null

echo "${SCRIPT_NAME}: Clean up complete"
