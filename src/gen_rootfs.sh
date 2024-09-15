#!/bin/bash

set -e
set -u
set -o pipefail

SCRIPT_NAME="$(basename "$0")"

function root_chk() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "${SCRIPT_NAME}: Please run as root. Exiting" >&2
        exit 13
    else
        echo -e "${SCRIPT_NAME}: Running with elevated privileges\n" >&2
    fi
}

function check_tools() {
    echo "${SCRIPT_NAME}: Testing if tools are installed" >&2
    echo "${SCRIPT_NAME}: Test for JQ"
    if ! command -v jq >/dev/null;       then echo "JQ not installed" >&2 && exit 2; fi
    echo "${SCRIPT_NAME}: Test for QEMU image tool" >&2
    if ! command -v qemu-img >/dev/null; then echo "QEMU image tool not installed" >&2 && exit 2; fi
    echo "${SCRIPT_NAME}: Test for Util Linux losetup" >&2
    if ! command -v losetup >/dev/null;  then echo "Util-Linux tools not installed" >&2 && exit 2; fi
    echo "${SCRIPT_NAME}: Test for Util Linux Scripted FDisk" >&2
    if ! command -v sfdisk >/dev/null;   then echo "Util-Linux tools not installed" >&2 && exit 2; fi
    echo "${SCRIPT_NAME}: Test for XFS mkfs.xfs tool" >&2
    if ! command -v mkfs.xfs >/dev/null; then echo "XFS Filesystem tools not installed" >&2 && exit 2; fi
    echo "${SCRIPT_NAME}: All needed tools are present" >&2
}

function create_vdisk() {
    echo "${SCRIPT_NAME}: Creating loopback filesystem"
    if [[ ! -f vdisk.img ]]; then
        qemu-img create vdisk.img 4G
    else
        echo "${SCRIPT_NAME}: File already exists! Exiting"
        exit 17
    fi
    # create temp loop dev
    losetup /dev/loop0 vdisk.img
    # partition device
    sfdisk /dev/loop0 < vdisk.sfdisk
    sleep 5
    partprobe -s
    losetup -v -D /dev/loop0
    losetup -v -P /dev/loop0 vdisk.img
    sleep 1
    # format ESP
    mkfs.vfat -v -n ESP -F 32 /dev/loop0p1
    fatlabel /dev/loop0p1 ESP
    sleep 1
    # format the root volume
    mkfs.xfs /dev/loop0p2
    xfs_admin -L Assimilator /dev/loop0p2
    sleep 1
    lsblk --fs
}

function mount_image() {
    mount -v -t xfs -L Assimilator rootfs
    # create mount point for ESP
    install -v -d -m 755 -o root -g root rootfs/System/boot
    # mount ESP
    mount -v -t vfat -L ESP rootfs/System/boot
}

function create_opt_local_tree() {
    pushd opt/local >/dev/null
        install -v -d -m 755 -o root -g root bin
        install -v -d -m 755 -o root -g root etc
        install -v -d -m 755 -o root -g root sbin
        install -v -d -m 755 -o root -g root lib
        install -v -d -m 755 -o root -g root lib64
        install -v -d -m 755 -o root -g root share
        install -v -d -m 755 -o root -g root var
    popd >/dev/null
}

function create_cfg_tree() {
    install -v -d -m 755 -o root -g root cfg
    pushd cfg >/dev/null
        install -v -d -m 755 -o root -g root cron.d
        install -v -d -m 755 -o root -g root cron.daily
        install -v -d -m 755 -o root -g root cron.hourly
        install -v -d -m 755 -o root -g root cron.monthly
        install -v -d -m 755 -o root -g root cron.weekly
        install -v -d -m 755 -o root -g root iproute2
        install -v -d -m 755 -o root -g root modprobe.d
        install -v -d -m 755 -o root -g root network
        install -v -d -m 755 -o root -g root network/if-down.d
        install -v -d -m 755 -o root -g root network/if-post-down.d
        install -v -d -m 755 -o root -g root network/if-pre-up.d
        install -v -d -m 755 -o root -g root network/if-up.d
        install -v -d -m 755 -o root -g root profile.d
        install -v -d -m 755 -o root -g root services.d
        install -v -d -m 755 -o root -g root opt
        install -v -d -m 755 -o root -g root skel
        ln -sv /opt/local/etc local
        ln -sv /proc/mounts mtab
    popd >/dev/null
    ln -sv cfg etc
}

function create_man_tree() {
    install -v -d -m 755 -o root -g root man
    pushd man >/dev/null
        install -v -d -m 755 -o root -g root man1
        install -v -d -m 755 -o root -g root man2
        install -v -d -m 755 -o root -g root man3
        install -v -d -m 755 -o root -g root man4
        install -v -d -m 755 -o root -g root man5
        install -v -d -m 755 -o root -g root man6
        install -v -d -m 755 -o root -g root man7
        install -v -d -m 755 -o root -g root man8
    popd >/dev/null
}

function create_share_tree() {
    install -v -d -m 755 -o root -g root share
    pushd share >/dev/null
        install -v -d -m 755 -o root -g root doc
        install -v -d -m 755 -o root -g root info
        install -v -d -m 755 -o root -g root locale
        create_man_tree
        install -v -d -m 755 -o root -g root misc
        install -v -d -m 755 -o root -g root nls
        install -v -d -m 755 -o root -g root terminfo
        install -v -d -m 755 -o root -g root zoneinfo
    popd >/dev/null
}

function create_var_tree() {
    install -v -d -m 755 -o root -g root var
    pushd var >/dev/null
        install -v -d -m 755 -o root -g root adm
        install -v -d -m 755 -o root -g root cache
        install -v -d -m 755 -o root -g root crash
        install -v -d -m 755 -o root -g root lib
        install -v -d -m 755 -o root -g root lib/empty
        install -v -d -m 755 -o root -g root lib/hwclock
        install -v -d -m 755 -o root -g root lib/misc
        ln -sv ../../opt/local/var local
        ln -sv ../../opt opt
        install -v -d -m 755 -o root -g root log
        install -v -d -m 755 -o root -g root run
        install -v -d -m 755 -o root -g root run/lock
        ln -sv run/lock lock
        install -v -d -m 755 -o root -g root spool
        install -v -d -m 700 -o root -g root spool/cron
        pushd spool/cron >/dev/null
            install -v -d -m 700 -o root -g root lastrun
            install -v -d -m 700 -o root -g root tabs
            # compatibility link
            ln -sv tabs crontabs
        popd >/dev/null
        install -v -d -m 1777 -o root -g root spool/mail
        ln -sv spool/mail mail
        install -v -d -m 1777 -o root -g root tmp
    popd >/dev/null
}

function create_system_tree() {
    pushd System >/dev/null
        install -v -d -m 755 -o root -g root bin
        ln -sv bin sbin
        install -v -d -m 755 -o root -g root boot/EFI/Boot
        create_cfg_tree
        install -v -d -m 755 -o root -g root lib
        install -v -d -m 755 -o root -g root lib/firmware
        install -v -d -m 755 -o root -g root lib/modules
        install -v -d -m 755 -o root -g root lib/security
        install -v -d -m 755 -o root -g root lib64
        install -v -d -m 755 -o root -g root lib64/security
        ln -sv ../opt/local local
        create_share_tree
        install -v -d -m 1777 -o root -g root tmp
        create_var_tree
    popd >/dev/null
}

function create_symlinks() {
    ln -sv System/bin bin
    ln -sv System/boot boot
    ln -sv System/cfg etc
    ln -sv Users home
    ln -sv System/lib lib
    ln -sv System/lib64 lib64
    ln -sv System/var/run run
    ln -sv System/bin sbin
    ln -sv System/tmp tmp
    ln -sv System usr
    ln -sv System/var var
}

function install_configuration_files() {
    # install configuration files
    pushd rootfs >/dev/null
        touch etc/hostname
        ln -sv etc/hostname etc/HOSTNAME
        touch etc/network/interfaces
        install -v -m 644 -o root -g root ../configs/acpi.map etc/
        install -v -m 644 -o root -g root ../configs/acpid.conf etc/
        install -v -m 600 -o root -g root ../configs/cron.deny etc/
        install -v -m 644 -o root -g root ../configs/ethers etc/
        install -v -m 644 -o root -g root ../configs/ethertypes etc/
        install -v -m 644 -o root -g root ../configs/exports etc/
        install -v -m 644 -o root -g root ../configs/filesystems etc/
        install -v -m 644 -o root -g root ../configs/fstab etc/
        install -v -m 644 -o root -g root ../configs/group etc/
        install -v -m 644 -o root -g root ../configs/hosts etc/
        install -v -m 644 -o root -g root ../configs/hosts.allow etc/
        install -v -m 644 -o root -g root ../configs/hosts.deny etc/
        install -v -m 644 -o root -g root ../configs/host.conf etc/
        install -v -m 644 -o root -g root ../configs/httpd.conf etc/
        install -v -m 644 -o root -g root ../configs/inputrc etc/
        install -v -m 644 -o root -g root ../configs/issue etc/
        install -v -m 644 -o root -g root ../configs/issue.net etc/
        install -v -m 644 -o root -g root ../configs/ld.so.conf etc/
        install -v -m 644 -o root -g root ../configs/login.defs etc/
        install -v -m 644 -o root -g root ../configs/mactab etc/
        install -v -m 644 -o root -g root ../configs/man.conf etc/
        install -v -m 644 -o root -g root ../configs/motd etc/
        install -v -m 644 -o root -g root ../configs/netconfig etc/
        install -v -m 644 -o root -g root ../configs/netgroup etc/
        install -v -m 644 -o root -g root ../configs/networks etc/
        install -v -m 644 -o root -g root ../configs/nsswitch.conf etc/
        install -v -m 644 -o root -g root ../configs/ntp.conf etc/
        install -v -m 644 -o root -g root ../configs/passwd etc/
        install -v -m 644 -o root -g root ../configs/protocols etc/
        install -v -m 644 -o root -g root ../configs/resolv.conf etc/
        install -v -m 644 -o root -g root ../configs/rpc etc/
        install -v -m 644 -o root -g root ../configs/securetty etc/
        install -v -m 644 -o root -g root ../configs/services etc/
        install -v -m 600 -o root -g root ../configs/shadow etc/
        install -v -m 644 -o root -g root ../configs/shells etc/
        install -v -m 644 -o root -g root ../configs/sysctl.conf etc/
        install -v -m 644 -o root -g root ../configs/syslog.conf etc/
        install -v -m 644 -o root -g root ../configs/assimilatoros-release etc/
        pushd System/cfg >/dev/null
            ln -sv assimilatoros-release os-release
        popd >/dev/null
        install -v -m 644 -o root -g root ../configs/dnsd.conf etc/
        install -v -m 644 -o root -g root ../configs/inetd.conf etc/
        install -v -m 644 -o root -g root ../configs/inittab etc/
        install -v -m 644 -o root -g root ../configs/mdev.conf etc/

        # shell configuration
        install -v -m 644 -o root -g root ../shellcfg/profile etc/
        install -v -m 644 -o root -g root ../shellcfg/umask.sh etc/profile.d/
    popd >/dev/null
}

function create_dir_tree() {
    pushd rootfs >/dev/null
        install -v -d -m 755 -o root -g root dev
        install -v -d -m 755 -o root -g root opt
        install -v -d -m 755 -o root -g root opt/local
        install -v -d -m 755 -o root -g root proc
        install -v -d -m 755 -o root -g root selinux
        install -v -d -m 755 -o root -g root sys
        install -v -d -m 755 -o root -g root Users
        install -v -d -m 755 -o root -g root Volumes
        create_opt_local_tree
        create_system_tree
        create_symlinks
        pushd Users >/dev/null
            install -v -d -m 700 -o root -g root root
        popd >/dev/null
    popd >/dev/null
}

function build_busybox() {
    # out of source builds don't seem to work, so in-source we go
    pushd 3rdparty/busybox >/dev/null
        make mrproper
        cp ../BusyBox.config .config
        make oldconfig
        make
    popd >/dev/null
}

function install_busybox() {
    pushd 3rdparty/busybox >/dev/null
        # we use some applets that require setuid rights
        install -v -m 4755 -o root -g root busybox ../../rootfs/System/bin/
        install -v -m 644 -o root -g root docs/busybox.1 ../../rootfs/System/share/man/man1/
        pushd ../../rootfs/System/share/man/man1 >/dev/null
            gzip -v -9 busybox.1
        popd >/dev/null
        # now make our symlinks
        pushd ../../rootfs/System/bin >/dev/null
            for binary in $(./busybox --list); do
                ln -sv busybox "${binary}"
            done
        popd >/dev/null
        # now that things are installed, clean up the busybox source tree
        make mrproper
        rm -v docs/BusyBox.html
        rm -v docs/BusyBox.txt
        rm -v docs/busybox.1
        rm -v docs/busybox.net/
        rm -v docs/busybox.pod
        rm -v include/common_bufsiz.h.method
    popd >/dev/null
}

function build_kernel() {
    true
}

function install_kernel() {
    true
}

function build_grub() {
    true
}

function install_grub() {
    true
}

function build_3rdparty() {
    # build and install busybox
    build_busybox
    install_busybox
    exit

    # build and install kernel
    build_kernel
    install_kernel

    # build and install GNU Grub2 bootloader
    build_grub
    install_grub

    # build and install JQ
    build_jq
    install_jq

    # build and install SQLite3
    build_sqlite3
    install_sqlite3

    # build and install Rsync
    build_rsync
    install_rsync

    # build and install PartClone
    build_partclone
    install_partclone

    # build and install GNU Nano
    build_nano
    install_nano

    # build and install XFS Programs
    build_xfsprogs
    install_xfsprogs
}

function install_host_libs() {
    true
    pushd "${proj_dir}/rootfs" >/dev/null
        for binary in "bin/busybox" "bin/jq"; do
            ldd $binary | while read -r line; do
                echo "LINE: $line"
            done
        done
    popd >/dev/null
}

function main() {
    # check if running as root
    root_chk

    # get where script lives
    local source_dir
    source_dir="$(dirname "${BASH_SOURCE[0]}")"

    local proj_dir
    proj_dir="$(dirname "$(cd "$source_dir" &> /dev/null && pwd)")"

    echo "${SCRIPT_NAME}: project directory: ${proj_dir}" >&2

    # chdir to proj_dir
    pushd "${proj_dir}" >/dev/null
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

        # install libraries
        install_host_libs
    popd
}

main "$@"
