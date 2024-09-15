#!/bin/bash

set -e
set -u
set -o pipefail

source_dir="$(dirname "${BASH_SOURCE[0]}")"
proj_dir="$(dirname "$(cd "${source_dir}" &> /dev/null && pwd)")"

echo "Cleaning ${proj_dir}"
umount /dev/loop0p1 ||:
umount /dev/loop0p2 ||:
losetup -D ||:
rm -fv "${proj_dir}/vdisk.img" ||:
rm -rfv "${proj_dir}/3rdparty/busybox/build" ||:
