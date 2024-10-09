#!/bin/bash

set -e
set -u
set -o pipefail

SCRIPT_NAME="$(basename "$0")"

SRC_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJ_DIR="$(dirname "$(cd "$SRC_DIR" &> /dev/null && pwd)")"

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
export BUILD_XFSPROGS=1
export BUILD_DIALOG=1

function show_help() {
    echo "${SCRIPT_NAME} - Generate an Assimilator OS root filesystem"
    echo "==========================================================="
    echo ""
    echo "OPTIONS:"
    echo "  --ignore-image      Don't bail out script if image file is present"
    echo "  --skip-busybox      Don't build busybox"
    echo "  --skip-kernel       Don't build the Linux kernel"
    echo "  --skip-grub         Don't build GNU Grub v2"
    echo "  --skip-efibootmgr   Don't build the EFI tools (efivar and efibootmgr)"
    echo "  --skip-pam          Don't build Linux PAM"
    echo "  --skip-jq           Don't build JQ"
    echo "  --skip-sqlite3      Don't build SQLite3 DB"
    echo "  --skip-rsync        Don't build RSync"
    echo "  --skip-ncurses      Don't build NCurses"
    echo "  --skip-nano         Don't build GNU Nano editor"
    echo "  --skip-partclone    Don't build the PartClone tools"
    echo "  --skip-xfsprogs     Don't build the XFS programs"
    echo "  --skip-dialog       Don't build the Dialog tool"
    echo ""
    echo "Report all bugs to https://github.com/greeneg/AssimilatorOS/issues"
}

function show_version() {
    echo "${SCRIPT_NAME} - Generate an Assimilator OS root filesystem"
    echo "==========================================================="
    echo "Author: Gary L. Greene, Jr."
    echo "Version: 1.0"
    echo "License: GPL version 2"
    echo ""
    echo "Report all bugs to https://github.com/greeneg/AssimilatorOS/issues"
}

function process_cmd_flags() {
    retval=0
    tmpflags=$( \
        getopt \
            -o 'hv' \
            --long 'ignore-image,skip-busybox,skip-kernel,skip-grub,skip-efibootmgr,skip-pam,skip-jq,skip-sqlite3,skip-rsync,skip-nano,skip-partclone,skip-xfsprogs,skip-dialog' \
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
            '--ignore-image')    IGNORE_IMAGE_FILE=1           && shift && continue ;;
            '--skip-busybox')    BUILD_BUSYBOX=0               && shift && continue ;;
            '--skip-kernel')     BUILD_KERNEL=0                && shift && continue ;;
            '--skip-grub')       BUILD_GRUB=0                  && shift && continue ;;
            '--skip-efibootmgr') BUILD_EFIBOOTMGR=0            && shift && continue ;;
            '--skip-pam')        BUILD_LINUXPAM=0              && shift && continue ;;
            '--skip-jq')         BUILD_JQ=0                    && shift && continue ;;
            '--skip-sqlite3')    BUILD_SQLITE3=0               && shift && continue ;;
            '--skip-rsync')      BUILD_RSYNC=0                 && shift && continue ;;
            '--skip-ncurses')    BUILD_NCURSES=0               && shift && continue ;;
            '--skip-nano')       BUILD_NANO=0                  && shift && continue ;;
            '--skip-partclone')  BUILD_PARTCLONE=0             && shift && continue ;;
            '--skip-xfsprogs')   BUILD_XFSPROGS=0              && shift && continue ;;
            '--skip-dialog')     BUILD_DIALOG=0                && shift && continue ;;
            '-v')                show_version                           && exit 0   ;;
            '-h')                show_help                              && exit 0   ;;
            '--')                                                 shift && break    ;;
            *)                echo 'Invalid flag! Exiting' >&2 && exit 1 ;;
        esac
    done
}

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
    echo "${SCRIPT_NAME}: Test for ManDoc tool" >&2
    if ! command -v mandoc >/dev/null;   then echo "ManDoc not installed" >&2 && exit 2; fi
    echo "${SCRIPT_NAME}: All needed tools are present" >&2
}

function create_vdisk() {
    if [[ $IGNORE_IMAGE_FILE -ne 1 ]]; then
        echo "${SCRIPT_NAME}: Creating loopback filesystem"
        if [[ ! -f vdisk.img ]]; then
            qemu-img create vdisk.img 4G
        else
            echo "${SCRIPT_NAME}: File already exists! Exiting"
            exit 17
        fi
        # create temp loop dev
        losetup /dev/loop0 "$PROJ_DIR/vdisk.img"
        # partition device
        sfdisk /dev/loop0 < "$PROJ_DIR/vdisk.sfdisk"
        sleep 5
        partprobe -s
        losetup -v -D /dev/loop0
        losetup -v -P /dev/loop0 "$PROJ_DIR/vdisk.img"
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
    else
        echo "${SCRIPT_NAME}: Using existing image"
    fi
}

function mount_image() {
    if [[ $IGNORE_IMAGE_FILE -ne 1 ]]; then
        mount -v -t xfs -L Assimilator "$PROJ_DIR/rootfs"
        # create mount point for ESP
        install -v -d -m 755 -o root -g root "$PROJ_DIR/rootfs/System/boot"
        # mount ESP
        mount -v -t vfat -L ESP "$PROJ_DIR/rootfs/System/boot"
    else
        echo "${SCRIPT_NAME}: Image is already mounted. Skipping"
    fi
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
        install -v -d -m 755 -o root -g root svcmgr/services.d
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
    pushd "$PROJ_DIR/rootfs" >/dev/null
        touch etc/hostname
        ln -sv hostname etc/HOSTNAME
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
    popd >/dev/null
}

function create_dir_tree() {
    pushd "$PROJ_DIR/rootfs" >/dev/null
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
    local tool="BusyBox"
    echo "${bold}${aqua}${SCRIPT_NAME}: Building ${tool}${normal}"
    # out of source builds don't seem to work, so in-source we go
    pushd "$PROJ_DIR/3rdparty/busybox" >/dev/null
        make mrproper
        cp -v "$PROJ_DIR/3rdparty/BusyBox.config" .config
        make oldconfig
        make
    popd >/dev/null
}

function install_busybox() {
    local tool="BusyBox"
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/busybox" >/dev/null
        # we use some applets that require setuid rights
        install -v -m 4755 -o root -g root busybox "$PROJ_DIR/rootfs/System/bin/"
        install -v -m 644 -o root -g root docs/busybox.1 "$PROJ_DIR/rootfs/System/share/man/man1/"
        pushd "$PROJ_DIR/rootfs/System/share/man/man1" >/dev/null
            gzip -v -9 busybox.1
        popd >/dev/null
        # now make our symlinks
        pushd "$PROJ_DIR/rootfs/System/bin" >/dev/null
            for binary in $(./busybox --list); do
                ln -sv busybox "${binary}"
            done
        popd >/dev/null
        # now that things are installed, clean up the busybox source tree
        make mrproper
        rm -v -f docs/BusyBox.html
        rm -v -f docs/BusyBox.txt
        rm -v -f docs/busybox.1
        rm -v -r -f docs/busybox.net/
        rm -v -f docs/busybox.pod
        rm -v -f include/common_bufsiz.h.method
    popd >/dev/null
}

function build_kernel() {
    local tool="Linux Kernel"
    echo "${bold}${aqua}${SCRIPT_NAME}: Building ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/linux" >/dev/null
        # ensure we are working with a clean tree
        rm -v -r -f build
        # now lets build this out-of-source
        mkdir -v build
        cd build
        make KBUILD_SRC=../ -f ../Makefile mrproper
        cp -v "$PROJ_DIR/3rdparty/LinuxKernel.config" .config
        make KBUILD_SRC=../ -f ../Makefile oldconfig
        make -j4
        cd -
    popd >/dev/null
}

function install_kernel() {
    local tool="Linux Kernel"
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/linux" >/dev/null
        cd build
        make INSTALL_PATH=../../../rootfs/System/boot install ||:
        make INSTALL_MOD_PATH=../../../rootfs/System/lib/modules modules_install ||:
        cd -
        # clean up after ourselves
        rm -v -r -f build
    popd >/dev/null
}

function build_grub() {
    local tool="GNU Grub v2"
    echo "${bold}${aqua}${SCRIPT_NAME}: Building ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/grub" >/dev/null
        ulimit -a
        touch docs/grub.texi
        cp docs/grub.texi docs/grub2.texi
        rm -v -r -f build
        ./autogen.sh
        export CFLAGS="-fno-strict-aliasing -fno-inline-functions-called-once "
        export CXXFLAGS=" "
        export FFLAGS=" "
        mkdir -v build
        cd build
        FS_MODULES="btrfs ext2 xfs jfs reiserfs"
        CD_MODULES="all_video boot cat configfile echo true font gfxmenu gfxterm gzio halt iso9660 jpeg minicmd normal \
                    part_apple part_msdos part_gpt password password_pbkdf2 png reboot search search_fs_uuid \
                    search_fs_file search_label sleep test video fat loadenv loopback chain efifwsetup efinet read tpm \
                    tpm2 memdisk tar squash4 xzio linuxefi"
        PXE_MODULES="tftp http efinet"
        CRYPTO_MODULES="luks luks2 gcry_rijndael gcry_sha1 gcry_sha256 gcry_sha512 crypttab"
        GRUB_MODULES="${CD_MODULES} ${FS_MODULES} ${PXE_MODULES} ${CRYPTO_MODULES} mdraid09 mdraid1x lvm serial"
        ../configure \
            TARGET_LDFLAGS="-static" \
            --prefix=/System \
            --sysconfdir=/System/cfg \
            --target=x86_64-pc-linux-gnu \
            --with-platform=efi \
            --program-transform-name=s,grub,grub2,
        make -j4
        # we don't do secure boot for now
        # create the shim image
        # echo "sbat,1,SBAT Version,sbat,1,https://github.com/rhboot/shim/blob/main/SBAT.md" > sbat.csv
        # echo "grub,4,Free Software Foundation,grub,2.12,https://www.gnu.org/software/grub/" >> sbat.csv
        # echo "grub.assimilatoros,1,Assimilator OS,grub,2.12,https://github.com/greeneg/AssimilatorOS" >> sbat.csv
        mkdir -pv ./fonts
        cp -v /usr/share/grub2/themes/*/*.pf2 ./fonts
        cp -v ./unicode.pf2 ./fonts
        tar --sort=name -cvf - ./fonts | mksquashfs - memdisk.sqsh -tar -comp xz

        # again, not doing secure boot for now
        # ./grub-mkimage -v -O x86_64-efi -o grub.efi --memdisk=./memdisk.sqsh --prefix= -d grub-core --sbat=sbat.csv \
        #    "${GRUB_MODULES}"
        # shellcheck disable=SC2086
        ./grub-mkimage -v -O x86_64-efi -o grub.efi --memdisk=./memdisk.sqsh --prefix= -d grub-core \
            ${GRUB_MODULES}
        cd -
    popd >/dev/null
}

function install_grub() {
    local tool="GNU Grub v2"
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/grub" >/dev/null
        cd build
            make DESTDIR="$PROJ_DIR/rootfs" install
            install -v -m 644 -o root -g root grub.efi "$PROJ_DIR/rootfs/System/lib/grub2/x86_64-efi/"
        cd -
        rm -v -r -f build
        # compress the man pages
        pushd "$PROJ_DIR/rootfs/System/share/man" >/dev/null
            for SECTION in 1 8; do
                find . -type f -name "grub2*.$SECTION" -exec gzip -v -9 {} \;
            done
        popd >/dev/null
        # create default directory in /System/cfg
        install -d -v -m 755 -o root -g root "$PROJ_DIR/rootfs/System/cfg/default"
        # install extra scripts
        install -v -m 755 -o root -g root vendor-configs/20_memtest86+ "$PROJ_DIR/rootfs/System/cfg/grub.d/"
        install -v -m 755 -o root -g root vendor-configs/90_persistent "$PROJ_DIR/rootfs/System/cfg/grub.d/"
        # install defaults
        install -v -m 644 -o root -g root vendor-configs/grub.default "$PROJ_DIR/rootfs/System/cfg/default/grub"
        # we don't ship XEN nor PPC
        rm -v "$PROJ_DIR/rootfs/etc/grub.d/20_linux_xen" "$PROJ_DIR/rootfs/etc/grub.d/20_ppc_terminfo"
        # strip binaries
        # note that strip errors due to a couple files being scripts, so we ignore the error case
        # shellcheck disable=SC2086
        strip -s -v $PROJ_DIR/rootfs/bin/grub2-* ||:
        # shellcheck disable=SC2086
        strip -s -v $PROJ_DIR/rootfs/lib/grub2/x86_64-efi/* ||:
        # now copy module directory to ESP
        cp -v -a "$PROJ_DIR/rootfs/lib/grub2" "$PROJ_DIR/rootfs/boot/"
    popd >/dev/null
}

function build_efivar() {
    local tool="EFI Var tools"
    echo "${bold}${aqua}${SCRIPT_NAME}: Building ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/efivar" >/dev/null
        make -j4
    popd >/dev/null
}

function install_efivar() {
    local tool="EFI Var tools"
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/efivar" >/dev/null
        make DESTDIR="$PROJ_DIR/rootfs" \
             BINDIR="/System/bin" \
             LIBDIR="/System/lib64" \
             DATADIR="/System/share" \
             INCLUDEDIR="/System/include" install
    popd >/dev/null
    # compress the man pages
    pushd "$PROJ_DIR/rootfs/System/share/man" >/dev/null
        for SECTION in 1 3; do
            find . -type f -name "efi*.$SECTION" -exec gzip -v -9 {} \;
        done
    popd >/dev/null
    strip -v -s "$PROJ_DIR/rootfs/bin/efisecdb"
    strip -v -s "$PROJ_DIR/rootfs/bin/efivar"
    # shellcheck disable=SC2086
    strip -v -s $PROJ_DIR/rootfs/lib64/libefi*
}

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

function build_linuxpam() {
    local tool="Linux PAM"
    echo "${bold}${aqua}${SCRIPT_NAME}: Building ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/pam" >/dev/null
        mkdir -p -v build
        pushd build >/dev/null
            ../configure --prefix=/System \
                         --bindir=/System/bin \
                         --sbindir=/System/sbin \
                         --sysconfdir=/System/cfg \
                         --docdir=/System/share/doc/Linux-PAM \
                         --includedir=/System/include/security \
                         --libdir=/System/lib64 \
                         --enable-isadir=/System/lib64/security \
                         --enable-securedir=/System/lib64/security \
                         --enable-read-both-confs \
                         --disable-doc \
                         --disable-examples \
                         --disable-prelude \
                         --disable-db \
                         --disable-nis \
                         --disable-logind \
                         --disable-econf \
                         --disable-rpath \
                         --disable-selinux
            make -j4
            gcc -fwhole-program -fpie -pie -D_FILE_OFFSET_BITS=64 -D_GNU_SOURCE -O2 -g -m64 -fmessage-length=0 \
                -D_FORTIFY_SOURCE=2 -fstack-protector -funwind-tables -fasynchronous-unwind-tables \
                -I../libpam/include ../unix2_chkpwd.c -o ./unix2_chkpwd -L../libpam/.libs -lpam
        popd >/dev/null
    popd >/dev/null
}

function install_linuxpam() {
    local tool="Linux PAM"
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/pam" >/dev/null
        # first create our required directories
        install -v -d -m 755 -o root -g root "$PROJ_DIR/rootfs/System/cfg/pam.d"
        install -v -d -m 755 -o root -g root "$PROJ_DIR/rootfs/System/cfg/security"
        install -v -d -m 755 -o root -g root "$PROJ_DIR/rootfs/System/cfg/security/limits.d"
        install -v -d -m 755 -o root -g root "$PROJ_DIR/rootfs/System/cfg/security/namespace.d"
        install -v -d -m 755 -o root -g root "$PROJ_DIR/rootfs/System/lib/motd.d"
        install -v -d -m 755 -o root -g root "$PROJ_DIR/rootfs/System/lib/tmpfiles.d"
        # now lets install Linux PAM
        pushd build >/dev/null
            make DESTDIR="$PROJ_DIR/rootfs" install
        popd >/dev/null
        # docs
        pushd modules >/dev/null
            install -v -d -m 755 -o root -g root "$PROJ_DIR/rootfs/System/share/doc/Linux-PAM/modules"
            for mod in pam_*/README; do
                install -v -m 644 -o root -g root "$mod" "$PROJ_DIR/rootfs/System/share/doc/Linux-PAM/modules/README.${mod%/*}"
            done
        popd >/dev/null
        # install our pam configuration files
        for pam_conf in "common-account" "common-auth" "common-password" "common-session" "other" \
                        "postlogin-account" "postlogin-auth" "postlogin-password" "postlogin-session"; do
            install -v -m 644 "$PROJ_DIR/configs/pam.d/$pam_conf" "$PROJ_DIR/rootfs/System/cfg/pam.d/"
        done
        install -v -m 755 -o root -g root build/unix2_chkpwd "$PROJ_DIR/rootfs/System/bin/"
        gzip -v -c -9 ./unix2_chkpwd.8 > build/unix2_chkpwd.8.gz
        install -v -m 644 -o root -g root build/unix2_chkpwd.8.gz "$PROJ_DIR/rootfs/System/share/man/man8/"
        install -v -m 644 -o root -g root "$PROJ_DIR/configs/pam.tmpfiles" "$PROJ_DIR/rootfs/System/lib/tmpfiles.d/"
        # nuke all the .la files
        find "$PROJ_DIR/rootfs/" -type f -name "*.la" -exec rm -vf {} \;
        strip -v -s "$PROJ_DIR/rootfs/bin/faillock"
        strip -v -s "$PROJ_DIR/rootfs/bin/mkhomedir_helper"
        strip -v -s "$PROJ_DIR/rootfs/bin/pam_timestamp_check"
        strip -v -s "$PROJ_DIR/rootfs/bin/unix_chkpwd"
        strip -v -s "$PROJ_DIR/rootfs/bin/unix2_chkpwd"
        # shellcheck disable=SC2086
        strip -v -s $PROJ_DIR/rootfs/System/lib64/security/pam*.so
        strip -v -s "$PROJ_DIR/rootfs/System/lib64/security/pam_filter/upperLOWER"
        strip -v -s "$PROJ_DIR/rootfs/System/lib64/libpam.so.0.85.1"
        strip -v -s "$PROJ_DIR/rootfs/System/lib64/libpamc.so.0.82.1"
        strip -v -s "$PROJ_DIR/rootfs/System/lib64/libpam_misc.so.0.82.1"
    popd >/dev/null
}

function build_jq() {
    local tool="JQ"
    echo "${bold}${aqua}${SCRIPT_NAME}: Building ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/jq" >/dev/null
        mkdir -pv build
        pushd build >/dev/null
            ../configure --prefix=/System \
                         --bindir=/System/bin \
                         --libdir=/System/lib64 \
                         --sysconfdir=/System/cfg \
                         --disable-docs
            make -j4
        popd >/dev/null
    popd >/dev/null
}

function install_jq() {
    local tool="JQ"
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/jq" >/dev/null
        pushd build >/dev/null
            make DESTDIR="$PROJ_DIR/rootfs" install
        popd >/dev/null
    popd >/dev/null
    rm -vf "$PROJ_DIR/rootfs/lib64/libjq.a"
    rm -vf "$PROJ_DIR/rootfs/lib64/libjq.la"
    # compress the man page for jq
    pushd "$PROJ_DIR/rootfs/System/share/man/man1" >/dev/null
        gzip -v -9 jq.1
    popd >/dev/null
    strip -v -s "$PROJ_DIR/rootfs/bin/jq"
    strip -v -s "$PROJ_DIR/rootfs/lib64/libjq.so.1.0.4"
}

function build_sqlite3() {
    local tool="SQLite3"
    echo "${bold}${aqua}${SCRIPT_NAME}: Building ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/sqlite3" >/dev/null
        mkdir -pv build
        pushd build >/dev/null
            ../configure --prefix=/System \
                         --bindir=/System/bin \
                         --libdir=/System/lib64 \
                         --sysconfdir=/System/cfg \
                         --enable-readline \
                         --enable-session
            make -j4
        popd >/dev/null
    popd >/dev/null
}

function install_sqlite3() {
    local tool="SQLite3"
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/sqlite3" >/dev/null
        pushd build >/dev/null
            make DESTDIR="$PROJ_DIR/rootfs" install
        popd >/dev/null
        rm -vf "$PROJ_DIR/rootfs/lib64/libsqlite3.a"
        rm -vf "$PROJ_DIR/rootfs/lib64/libsqlite3.la"
        strip -v -s "$PROJ_DIR/rootfs/bin/sqlite3"
        strip -v -s "$PROJ_DIR/rootfs/lib64/libsqlite3.so.0.8.6"
    popd >/dev/null
    pushd "$PROJ_DIR/rootfs/System/share/man/man1" >/dev/null
        gzip -v -9 sqlite3.1
    popd >/dev/null
}

function build_rsync() {
    local tool="RSync"
    echo "${bold}${aqua}${SCRIPT_NAME}: Building ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/rsync" >/dev/null
        mkdir -pv build
        pushd build >/dev/null
            ../configure --prefix=/System \
                         --bindir=/System/bin \
                         --libdir=/System/lib64 \
                         --sysconfdir=/System/cfg
            make -j4
        popd >/dev/null
    popd >/dev/null
}

function install_rsync() {
    local tool="RSync"
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/rsync" >/dev/null
        pushd build >/dev/null
            make DESTDIR="$PROJ_DIR/rootfs" install
        popd >/dev/null
        strip -v -s "$PROJ_DIR/rootfs/bin/rsync"
    popd >/dev/null
    pushd "$PROJ_DIR/rootfs/System/share/man" >/dev/null
        for SECTION in 1 5; do
            find . -type f -name "rsync*.$SECTION" -exec gzip -v -9 {} \;
        done
    popd >/dev/null
}

function build_nano() {
    local tool="GNU Nano"
    echo "${bold}${aqua}${SCRIPT_NAME}: Building ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/nano" >/dev/null
        mkdir -pv build
        pushd build >/dev/null
            LDFLAGS="-L${PROJ_DIR}/rootfs/System/lib64" \
            CPPFLAGS="-I${PROJ_DIR}/rootfs/System/include/ncursesw -I${PROJ_DIR}/rootfs/System/include" \
            PKG_CONFIG_PATH="${PROJ_DIR}/rootfs/lib64/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig" \
            ../configure --prefix=/System \
                         --bindir=/System/bin \
                         --libdir=/System/lib64 \
                         --sysconfdir=/System/cfg \
                         --enable-utf8 \
                         --enable-year2038
            make -j4
        popd >/dev/null
    popd >/dev/null
}

function install_nano() {
    local tool="GNU Nano"
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/nano" >/dev/null
        pushd build >/dev/null
            make DESTDIR="$PROJ_DIR/rootfs" install
        popd >/dev/null
        strip -v -s "$PROJ_DIR/rootfs/bin/nano"
    popd >/dev/null
    pushd "$PROJ_DIR/rootfs/System/share/man" >/dev/null
        for SECTION in 1 5; do
            find . -type f -name "nano*.$SECTION" -exec gzip -v -9 {} \;
        done
        gzip -v -9 man1/rnano.1
    popd >/dev/null
    # install the system-wide nanorc
    install -v -m 644 -o root -g root "$PROJ_DIR/configs/nanorc" "$PROJ_DIR/rootfs/System/cfg/nanorc"
}

function build_xfsprogs() {
    local tool="XFS Programs"
    echo "${bold}${aqua}${SCRIPT_NAME}: Building ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/xfsprogs" >/dev/null
        # XFS progs REALLY doesn't know how to do out-of-source builds, so copy tree into temp dir
        mkdir -pv ../build
        cp -a ./* ../build/
        pushd ../build >/dev/null
            export OPTIMIZER="-fPIC"
            export DEBUG=-DNDEBUG
            export LIBUUID=/usr/lib64/libuuid.a
            ./configure --prefix=/System \
                        --bindir=/System/bin \
                        --sbindir=/System/sbin \
                        --sysconfdir=/System/cfg \
                        --libdir=/System/lib64 \
                        --libexecdir=/System/lib \
                        --enable-editline=yes \
                        --enable-libicu=yes
            make -j4
        popd >/dev/null
    popd >/dev/null
}

function install_xfsprogs() {
    local tool="XFS Programs"
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/xfsprogs" >/dev/null
        pushd ../build >/dev/null
            make DESTDIR="$PROJ_DIR/rootfs" install
        popd >/dev/null
        strip -v -s "$PROJ_DIR/rootfs/bin/mkfs.xfs"
        # shellcheck disable=SC2086
        strip -v -s "$PROJ_DIR/rootfs/bin/xfs_copy"
        strip -v -s "$PROJ_DIR/rootfs/bin/xfs_db"
        strip -v -s "$PROJ_DIR/rootfs/bin/xfs_estimate"
        strip -v -s "$PROJ_DIR/rootfs/bin/xfs_fsr"
        strip -v -s "$PROJ_DIR/rootfs/bin/xfs_growfs"
        strip -v -s "$PROJ_DIR/rootfs/bin/xfs_io"
        strip -v -s "$PROJ_DIR/rootfs/bin/xfs_logprint"
        strip -v -s "$PROJ_DIR/rootfs/bin/xfs_quota"
        strip -v -s "$PROJ_DIR/rootfs/bin/xfs_mdrestore"
        strip -v -s "$PROJ_DIR/rootfs/bin/xfs_repair"
        strip -v -s "$PROJ_DIR/rootfs/bin/xfs_rtcp"
        strip -v -s "$PROJ_DIR/rootfs/bin/xfs_spaceman"
        strip -v -s "$PROJ_DIR/rootfs/bin/xfs_scrub"
    popd >/dev/null
    pushd "$PROJ_DIR/rootfs/System/share/man" >/dev/null
        for SECTION in 5 8; do
            find . -type f -name "*.$SECTION" -exec gzip -v -9 {} \;
        done
    popd >/dev/null
}

function build_dialog() {
    local tool="Dialog"
    echo "${bold}${aqua}${SCRIPT_NAME}: Building ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/dialog" >/dev/null
        mkdir -pv build
        pushd build >/dev/null
            LDFLAGS="-L${PROJ_DIR}/rootfs/System/lib64" \
            CPPFLAGS="-I${PROJ_DIR}/rootfs/System/include/ncursesw -I${PROJ_DIR}/rootfs/System/include" \
            PKG_CONFIG_PATH="${PROJ_DIR}/rootfs/lib64/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig" \
            ../configure --prefix=/System \
                         --bindir=/System/bin \
                         --libdir=/System/lib64 \
                         --sysconfdir=/System/cfg \
                         --with-ncursesw
            make -j4
        popd >/dev/null
    popd >/dev/null
}

function install_dialog() {
    local tool="Dialog"
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/dialog" >/dev/null
        pushd build >/dev/null
            make DESTDIR="$PROJ_DIR/rootfs" install
        popd >/dev/null
        strip -v -s "$PROJ_DIR/rootfs/bin/dialog"
    popd >/dev/null
    pushd "$PROJ_DIR/rootfs/System/share/man" >/dev/null
        gzip -v -9 man1/dialog.1
    popd >/dev/null
    # we don't want the static library
    rm -fv "$PROJ_DIR/rootfs/lib64/libdialog.a"
}

function build_ncurses() {
    local tool="NCurses"
    echo "${bold}${aqua}${SCRIPT_NAME}: Building ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/ncurses" >/dev/null
        # make configure find gawk
        sed -i s/mawk// configure

        # build tic
        mkdir -pv build_tic
        pushd build_tic >/dev/null
            ../configure
            make -C include
            make -C progs tic
        popd >/dev/null
        mkdir -pv build
        pushd build >/dev/null
            ../configure \
                --prefix=/System \
                --libdir=/System/lib64 \
                --mandir=/System/share/man \
                --with-manpage-format=normal \
                --with-shared \
                --without-normal \
                --with-cxx-shared \
                --without-debug \
                --without-ada \
                --enable-widec \
                --enable-pc-files
            make -j4
        popd >/dev/null
    popd >/dev/null
}

function install_ncurses() {
    local tool="NCurses"
    echo "${bold}${aqua}${SCRIPT_NAME}: Building ${tool}${normal}"
    pushd "$PROJ_DIR/3rdparty/ncurses" >/dev/null
        pushd build >/dev/null
            make DESTDIR="$PROJ_DIR/rootfs" TIC_PATH="${PROJ_DIR}/3rdparty/ncurses/build_tic/progs/tic" install
        popd >/dev/null
    popd >/dev/null
    pushd "$PROJ_DIR/rootfs/System/share/man" >/dev/null
        for SECTION in 1 1m 3 3x 5 7 8; do
            find . -type f -name "*.$SECTION" -exec gzip -v -9 {} \;
        done
    popd >/dev/null
    # fix links for compressed man pages
    for SECTION in 1 3; do
        pushd "$PROJ_DIR/rootfs/System/share/man/man${SECTION}" >/dev/null
            find . -type l | while read -r line; do
                # shellcheck disable=SC2012
                f=$(basename "$(ls -l "$line" | awk '{ print $9 }')")
                # shellcheck disable=SC2012
                t=$(ls -l "$line" | awk '{ print $11 }')
                echo "FILE: $f"
                echo "TARGET: $t"
                rm "$f"
                ln -sv "${t}.gz" "$f"
            done
        popd
    done
}

function build_partclone() {
    true
}

function install_partclone() {
    true
}

function build_3rdparty() {
    # build and install busybox
    if [[ $BUILD_BUSYBOX == 1 ]]; then
        build_busybox
        install_busybox
    fi

    # build and install kernel
    if [[ $BUILD_KERNEL == 1 ]]; then
        build_kernel
        install_kernel
    fi

    # build and install ncurses
    if [[ $BUILD_NCURSES == 1 ]]; then
        build_ncurses
        install_ncurses
    fi

    # build and install GNU Grub2 bootloader
    if [[ $BUILD_GRUB == 1 ]]; then
        build_grub
        install_grub
    fi

    # efibootmgr needs a new enough version of efivar
    if [[ $BUILD_EFIBOOTMGR == 1 ]]; then
        build_efivar
        install_efivar
        build_efibootmgr
        install_efibootmgr
    fi

    # build Linux PAM
    if [[ $BUILD_LINUXPAM == 1 ]]; then
        build_linuxpam
        install_linuxpam
    fi

    # build and install JQ
    if [[ $BUILD_JQ == 1 ]]; then
        build_jq
        install_jq
    fi

    # build and install SQLite3
    if [[ $BUILD_SQLITE3 == 1 ]]; then
        build_sqlite3
        install_sqlite3
    fi

    # build and install Rsync
    if [[ $BUILD_RSYNC == 1 ]]; then
        build_rsync
        install_rsync
    fi

    # build and install GNU Nano
    if [[ $BUILD_NANO == 1 ]]; then
        build_nano
        install_nano
    fi

    # build and install XFS Programs
    if [[ $BUILD_XFSPROGS == 1 ]]; then
        build_xfsprogs
        install_xfsprogs
    fi

    # build and install dialog
    if [[ $BUILD_DIALOG == 1 ]]; then
        build_dialog
        install_dialog
    fi

    # build and install PartClone
    if [[ $BUILD_PARTCLONE ]]; then
        build_partclone
        install_partclone
    fi
}

function build_src() {
    true
}

function install_host_libs() {
    pushd "${PROJ_DIR}/rootfs/bin" >/dev/null
        echo "${bold}${aqua}${SCRIPT_NAME}: Installing system libraries... ${normal}"
        find . -type f | while read -r line; do
            f=$(basename "$line")
            t="$(file -i "$f" | awk '{ print $2 }' | sed 's/;//' | sed 's/\//_/' | sed 's/-/_/')"
            if [[ "$t" == 'application_x_executable' ]] || \
               [[ "$t" == 'application_x_sharedlib' ]]; then
                ldd "$f" | while read -r lib; do
                    if [[ "$lib" =~ linux-vdso.so.1 ]]; then
                        echo "${bold}${white}VDSO is baked into the Kernel. Skipping${normal}"
                        continue
                    fi
                    if [[ "$lib" =~ ld-linux-x86-64.so.2 ]]; then
                        echo "${bold}${white}ld-linux is handled later. Skipping for now${normal}"
                        continue
                    fi
                    l=$(echo "$lib" | awk '{ print $1 }')
                    p=$(echo "$lib" | awk '{ print $3 }')
                    # get our target's dir name for later
                    d=$(dirname "$p")
                    if [[ ! -f "$PROJ_DIR/rootfs/lib64/$l" ]]; then
                        # is $l a valid library?
                        echo "${bold}${yellow}FILE: $l" >&2
                        if [[ "$l" =~ ^lib[a-z0-9|_-]+.so* ]]; then
                            # check if library is already present in tree
                            if [[ -e "${PROJ_DIR}/rootfs/lib64/$l" ]]; then
                                echo "${bold}${white}Library already exists inside the image. Skipping${normal}"
                                continue
                            fi
                            echo "${bold}${aqua}Installing library: ${l}${normal}"
                            cp -av "$p" "$PROJ_DIR/rootfs/lib64/$l"
                            # now determine if path is a symlink
                            lt="$(file -i "$p" | awk '{ print $2 }' | sed 's/;//' | sed 's/\//_/')"
                            if [[ "$lt" =~ inode_symlink ]]; then
                                echo "${bold}${white}File is a symlink${normal}"
                                # get our target to install
                                # shellcheck disable=SC2012
                                link_target=$(ls -l "$p" | awk '{ print $11 }')
                                ltarget_file=$(basename "$link_target")
                                echo "${bold}${aqua}Installing library: ${ltarget_file}${normal}"
                                echo "TARGET DIRECTORY: $d"
                                echo "LINK TARGET: $link_target"
                                # Gah! There are times that the entry in /lib64 is a LINK to the stupid thing in /usr/lib64.
                                #      Need to work around this by checking if this link name is identical to the target
                                #      name, nuke the link, and then copy in the real file.
                                if [[ "${l}" == "${ltarget_file}" ]]; then
                                    # nuke the link, then copy file into place
                                    echo "${bold}${yellow}Found collision!!!${normal}"
                                    echo "${bold}${white}Removing offending symlink that collids with the target file${normal}"
                                    rm -v "$PROJ_DIR/rootfs/lib64/$ltarget_file"
                                    cp -av "$link_target" "${PROJ_DIR}/rootfs/lib64/$ltarget_file"
                                else
                                    cp -av "$d/$link_target" "$PROJ_DIR/rootfs/lib64/$ltarget_file"
                                fi
                            fi
                        else
                            echo "${bold}${yellow}Not a library!${normal}"
                            continue
                        fi
                    fi
                done
            else
                echo "${bold}${white}Not a dynamically linked executable. Skipping${normal}"
                continue
            fi
        done
        # special case, libcom_err.so.2.1 isn't being imported into the rootfs correctly.
        cp -av /usr/lib64/libcom_err.so.2.1 "${PROJ_DIR}/rootfs/lib64/"
    popd >/dev/null
    pushd "${PROJ_DIR}/rootfs/lib64" >/dev/null
        # now install ld-linux-x86-64.so.2
        echo "${bold}${aqua}Installing library: ld-linux-x86-64.so.2${normal}"
        cp -av /lib64/ld-linux-x86-64.so.2 "$PROJ_DIR/rootfs/lib64/"
        ln -sv ld-linux-x86-64.so.2 ld-lsb-x86-64.so.2
        ln -sv ld-linux-x86-64.so.2 ld-lsb-x86-64.so.3
    popd >/dev/null
    # now strip all the libs
    pushd "${PROJ_DIR}/rootfs/lib64" >/dev/null
        echo "${bold}${aqua}stripping libraries${normal}"
        find . -type f -exec file {} \; | while read -r lib_string; do
            if [[ "${lib_string}" =~ 'not stripped' ]]; then
                # get our lib from the string
                lib=$(basename "$(echo "${lib_string}" | awk '{ print $1 }')" | sed 's/://')
                echo "${bold}${white}LIBRARY: ${lib}${normal}"
                strip -s -v "${lib}"
            fi
        done
        # enforce permissions
        find . -type f -name "*.so*" | while read -r lib; do
            chmod -v 755 "${lib}"
        done
    popd >/dev/null
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
