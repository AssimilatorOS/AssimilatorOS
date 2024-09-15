#!/bin/bash

set -e
set -u
set -o pipefail

SCRIPT_NAME=$(basename $0)

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
    pushd opt/local
        install -v -d -m 755 -o root -g root bin
        install -v -d -m 755 -o root -g root etc
        install -v -d -m 755 -o root -g root sbin
        install -v -d -m 755 -o root -g root lib
        install -v -d -m 755 -o root -g root lib64
        install -v -d -m 755 -o root -g root share
        install -v -d -m 755 -o root -g root var
    popd
}

function create_cfg_tree() {
    install -v -d -m 755 -o root -g root cfg
    pushd cfg
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
    popd
    ln -sv cfg etc
}

function create_man_tree() {
    install -v -d -m 755 -o root -g root man
    pushd man
        install -v -d -m 755 -o root -g root man1
        install -v -d -m 755 -o root -g root man2
        install -v -d -m 755 -o root -g root man3
        install -v -d -m 755 -o root -g root man4
        install -v -d -m 755 -o root -g root man5
        install -v -d -m 755 -o root -g root man6
        install -v -d -m 755 -o root -g root man7
        install -v -d -m 755 -o root -g root man8
    popd
}

function create_share_tree() {
    install -v -d -m 755 -o root -g root share
    pushd share
        install -v -d -m 755 -o root -g root doc
        install -v -d -m 755 -o root -g root info
        install -v -d -m 755 -o root -g root locale
        create_man_tree
        install -v -d -m 755 -o root -g root misc
        install -v -d -m 755 -o root -g root nls
        install -v -d -m 755 -o root -g root terminfo
        install -v -d -m 755 -o root -g root zoneinfo
    popd
}

function create_var_tree() {
    install -v -d -m 755 -o root -g root var
    pushd var
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
        install -v -d -m 711 -o root -g root spool/cron
        install -v -d -m 1777 -o root -g root spool/mail
        ln -sv spool/mail mail
        install -v -d -m 1777 -o root -g root tmp
    popd
}

function create_system_tree() {
    pushd System
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
    popd
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
    pushd rootfs
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
        pushd System/cfg
            ln -sv assimilatoros-release os-release
        popd
        install -v -m 644 -o root -g root ../configs/dnsd.conf etc/
        install -v -m 644 -o root -g root ../configs/inetd.conf etc/
        install -v -m 644 -o root -g root ../configs/inittab etc/
        install -v -m 644 -o root -g root ../configs/mdev.conf etc/

        # shell configuration
        install -v -m 644 -o root -g root ../shellcfg/profile etc/
        install -v -m 644 -o root -g root ../shellcfg/umask.sh etc/profile.d/
    popd
}

function create_dir_tree() {
    pushd rootfs
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
        pushd Users
            install -v -d -m 700 -o root -g root root
        popd
    popd
}

function main() {
    # check if running as root
    root_chk

    # get where script lives
    local proj_dir="$(dirname $(cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd))"
    echo "${SCRIPT_NAME}: project directory: ${proj_dir}" >&2

    # chdir to proj_dir
    pushd $proj_dir >/dev/null
        # check if needed tools are installed
        check_tools

        # create image
        create_vdisk
        # mount rootfs and ESP
        mount_image

        # create directory tree for the OS
        create_dir_tree
    popd
}

main "$@"
