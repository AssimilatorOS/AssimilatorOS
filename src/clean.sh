#!/bin/bash

set -e
set -u
set -o pipefail

umount /dev/loop0p1 ||:
umount /dev/loop0p2 ||:
losetup -D

