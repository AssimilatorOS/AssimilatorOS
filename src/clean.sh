#!/bin/bash

set -e
set -u
set -o pipefail

SCRIPT_NAME="$(basename "$0")"

if [[ "${EUID}" -ne 0 ]]; then
    echo "${SCRIPT_NAME}: Please run as root. Exiting" >&2
    exit 13
else
    echo -e "${SCRIPT_NAME}: Running with elevated privileges\n" >&2
fi

source_dir="$(dirname "${BASH_SOURCE[0]}")"
proj_dir="$(dirname "$(cd "${source_dir}" &> /dev/null && pwd)")"

echo "${SCRIPT_NAME}: Cleaning ${proj_dir}"
umount -v /dev/loop0p1 ||:
umount -v /dev/loop0p2 ||:
losetup -v -D ||:
rm -fv "${proj_dir}/vdisk.img" ||:
rm -rfv "${proj_dir}/3rdparty/busybox/build" ||:

echo "${SCRIPT_NAME}: Clean up complete"
