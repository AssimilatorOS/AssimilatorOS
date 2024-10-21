#!/bin/bash

set -e
set -u
set -o pipefail

SCRIPT_NAME="$(basename "$0")"

SRC_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJ_DIR="$(dirname "$(cd "$SRC_DIR" &> /dev/null && pwd)")"

source "$PROJ_DIR/src/functions.shlib"
source "$PROJ_DIR/src/termcolors.shlib"

export IGNORE_IMAGE_FILE=0
export BUILD_BUSYBOX=1
export BUILD_KERNEL=1
export BUILD_GRUB=1
export BUILD_EFIBOOTMGR=1
export BUILD_LINUXPAM=1
export BUILD_JQ=1
export BUILD_SQLITE3=1
export BUILD_RSYNC=1
export BUILD_NCURSES=1
export BUILD_NANO=1
export BUILD_PARTCLONE=1
export BUILD_STATIC_BUSYBOX=1
export BUILD_XFSPROGS=1
export BUILD_DIALOG=1
export BUILD_INTEL_FW=1

function show_help() {
    echo "${SCRIPT_NAME} - Generate an Assimilator OS root filesystem"
    echo "==========================================================="
    echo ""
    echo "OPTIONS:"
    echo "  --ignore-image          Don't bail out script if image file is present"
    echo "  --skip-busybox          Don't build busybox"
    echo "  --skip-static-busybox   Don't build static busybox"
    echo "  --skip-kernel           Don't build the Linux kernel"
    echo "  --skip-grub             Don't build GNU Grub v2"
    echo "  --skip-efibootmgr       Don't build the EFI tools (efivar and efibootmgr)"
    echo "  --skip-pam              Don't build Linux PAM"
    echo "  --skip-jq               Don't build JQ"
    echo "  --skip-sqlite3          Don't build SQLite3 DB"
    echo "  --skip-rsync            Don't build RSync"
    echo "  --skip-ncurses          Don't build NCurses"
    echo "  --skip-nano             Don't build GNU Nano editor"
    echo "  --skip-partclone        Don't build the PartClone tools"
    echo "  --skip-xfsprogs         Don't build the XFS programs"
    echo "  --skip-dialog           Don't build the Dialog tool"
    echo ""
    echo "Report all bugs to https://github.com/AssimilatorOS/AssimilatorOS/issues"
}

function show_version() {
    echo "${SCRIPT_NAME} - Generate an Assimilator OS root filesystem"
    echo "==========================================================="
    echo "Author: Gary L. Greene, Jr."
    echo "Version: 1.0"
    echo "License: GPL version 2"
    echo ""
    echo "Report all bugs to https://github.com/AssimilatorOS/AssimilatorOS/issues"
}

function process_cmd_flags() {
    retval=0
    tmpflags=$( \
        getopt \
            -o 'hv' \
            --long 'ignore-image,skip-busybox,skip-static-busybox,skip-kernel,skip-grub,skip-efibootmgr,skip-pam,skip-jq,skip-sqlite3,skip-rsync,skip-nano,skip-partclone,skip-xfsprogs,skip-dialog' \
            -n 'gen_rootfs' -- "$@" \
    ) || retval=$?
    if [[ $retval -ne 0 ]]; then
        echo "Exit code $?: Exiting" >&2
        exit 1
    fi

    eval set -- "$tmpflags"
    unset tmpflags
    while true; do
        case "$1" in
            '--ignore-image')           IGNORE_IMAGE_FILE=1     && shift && continue ;;
            '--skip-busybox')           BUILD_BUSYBOX=0         && shift && continue ;;
            '--skip-static-busybox')    BUILD_STATIC_BUSYBOX=0  && shift && continue ;;
            '--skip-kernel')            BUILD_KERNEL=0          && shift && continue ;;
            '--skip-grub')              BUILD_GRUB=0            && shift && continue ;;
            '--skip-efibootmgr')        BUILD_EFIBOOTMGR=0      && shift && continue ;;
            '--skip-pam')               BUILD_LINUXPAM=0        && shift && continue ;;
            '--skip-jq')                BUILD_JQ=0              && shift && continue ;;
            '--skip-sqlite3')           BUILD_SQLITE3=0         && shift && continue ;;
            '--skip-rsync')             BUILD_RSYNC=0           && shift && continue ;;
            '--skip-ncurses')           BUILD_NCURSES=0         && shift && continue ;;
            '--skip-nano')              BUILD_NANO=0            && shift && continue ;;
            '--skip-partclone')         BUILD_PARTCLONE=0       && shift && continue ;;
            '--skip-xfsprogs')          BUILD_XFSPROGS=0        && shift && continue ;;
            '--skip-dialog')            BUILD_DIALOG=0          && shift && continue ;;
            '-v')                show_version                   && exit 0   ;;
            '-h')                show_help                      && exit 0   ;;
            '--')                                                  shift && break    ;;
            *)                 echo 'Invalid flag! Exiting' >&2 && exit 1 ;;
        esac
    done
}

function main() {
    # process flags
    process_cmd_flags "$@"

    # check if running as root
    root_chk

    echo "${SCRIPT_NAME}: project directory: ${PROJ_DIR}" >&2

    # chdir to proj_dir
    pushd "${PROJ_DIR}" >/dev/null
        # check if needed tools are installed
        check_tools

        # create image
        create_vdisk

        # mount rootfs and ESP
        mount_image

        # create directory tree for the OS
        create_dir_tree

        # build and install 3rdparty tools
        build_3rdparty

        # build OUR tools
        build_src

        # install libraries
        install_host_libs

        # now for configuration files
        install_configuration_files
    popd >/dev/null
}

main "$@"
