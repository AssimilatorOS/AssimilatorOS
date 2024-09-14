#!/bin/bash

set -e
set -u
set -o pipefail

function main() {
    # check if needed tools are installed

    # get command line flags

    # create loopback file
    qemu-img create virtual-disk 4G
    losetup /dev/loop0 virtual-disk
    
}

main "$@"
