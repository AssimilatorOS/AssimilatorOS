#!/bin/bash

set -e
set -u
set -o pipefail

SCRIPT_NAME="$(basename "$0")"

SRC_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJ_DIR="$(dirname "$(cd "$SRC_DIR" &> /dev/null && pwd)")"

export IGNORE_IMAGE_FILE=0
export BUILD_BUSYBOX=1
export BUILD_KERNEL=1
export BUILD_GRUB=1
export BUILD_EFIBOOTMGR=1
export BUILD_LINUXPAM=1
export BUILD_JQ=1
export BUILD_SQLITE3=1
export BUILD_RSYNC=1
export BUILD_NANO=1
export BUILD_PARTCLONE=1
export BUILD_XFSPROGS=1
export BUILD_DIALOG=1

function process_cmd_flags() {
    retval=0
    tmpflags=$(getopt -o 'ibkgepjsrncxd' --long 'ignore-image,skip-busybox,skip-kernel,skip-grub,skip-efibootmgr,skip-pam,skip-jq,skip-sqlite3,skip-rsync,skip-nano,skip-pclone,skip-xfs,skip-dialog' -n 'gen_rootfs' -- "$@") || retval=$?
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
            '--skip-nano')       BUILD_NANO=0                  && shift && continue ;;
            '--skip-pclone')     BUILD_PARTCLONE=0             && shift && continue ;;
            '--skip-xfs')        BUILD_XFSPROGS=0              && shift && continue ;;
            '--skip-dialog')     BUILD_DIALOG=0                && shift && continue ;;
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
        install -v -d -m 755 -o root -g root services.d
        install -v -d -m 755 -o root -g root opt
        install -v -d -m 755 -o root -g root skel
        ln -sv ../opt/local/etc local
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
    # out of source builds don't seem to work, so in-source we go
    pushd "$PROJ_DIR/3rdparty/busybox" >/dev/null
        make mrproper
        cp -v "$PROJ_DIR/3rdparty/BusyBox.config" .config
        make oldconfig
        make
    popd >/dev/null
}

function install_busybox() {
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
    pushd 3rdparty/grub >/dev/null
        cd build
            make DESTDIR="$PROJ_DIR/rootfs" install
            install -v -m 644 -o root -g root grub.efi "$PROJ_DIR/rootfs/System/lib/grub2/x86_64-efi/"
        cd -
        rm -v -r -f build
        # create default directory in /System/cfg
        install -d -v -m 755 -o root -g root "$PROJ_DIR/rootfs/System/cfg/default"
        # install extra scripts
        install -v -m 644 -o root -g root vendor-configs/20_memtest86+ "$PROJ_DIR/rootfs/System/cfg/grub.d/"
        install -v -m 644 -o root -g root vendor-configs/90_persistent "$PROJ_DIR/rootfs/System/cfg/grub.d/"
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
    pushd "$PROJ_DIR/3rdparty/efivar" >/dev/null
        make -j4
    popd >/dev/null
}

function install_efivar() {
    pushd "$PROJ_DIR/3rdparty/efivar" >/dev/null
        make DESTDIR="$PROJ_DIR/rootfs" \
             BINDIR="/System/bin" \
             LIBDIR="/System/lib64" \
             DATADIR="/System/share" \
             INCLUDEDIR="/System/include" install
    popd >/dev/null
}

function build_efibootmgr() {
    pushd "$PROJ_DIR/3rdparty/efibootmgr" >/dev/null
        sed -e '/extern int efi_set_verbose/d' -i "src/efibootmgr.c"
        LOADER="grub.efi"  # default loader
        VENDOR="AssimilatorOS"
        OPT_FLAGS="-O2 -g -m64 -fmessage-length=0 -D_FORTIFY_SOURCE=2 -fstack-protector -funwind-tables -fasynchronous-unwind-tables"
        make -j4 CFLAGS="$OPT_FLAGS -flto -fPIE -pie" OS_VENDOR="$VENDOR" EFI_LOADER="$LOADER" EFIDIR="$VENDOR"
    popd >/dev/null
}

function install_efibootmgr() {
    true
}

function build_linuxpam() {
    true
}

function install_linuxpam() {
    true
}

function build_jq() {
    true
}

function install_jq() {
    true
}

function build_sqlite3() {
    true
}

function install_sqlite3() {
    true
}

function build_rsync() {
    true
}

function install_rsync() {
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

    # build and install GNU Grub2 bootloader
    if [[ $BUILD_GRUB == 1 ]]; then
        build_grub
        install_grub
    fi

    # efibootmgr needs a new enough version of efivar
    if [[ $BUILD_EFIBOOTMGR == 1 ]]; then
        build_efivar
        install_efivar
        exit
        build_efibootmgr
        install_efibootmgr
    fi
    exit

    # build Linux PAM
    build_linuxpam
    install_linuxpam

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

    # build and install dialog
    build_dialog
    install_dialog
}

function build_src() {
    true
}

function install_host_libs() {
    true
    pushd "${PROJ_DIR}/rootfs" >/dev/null
        for binary in "bin/busybox" "bin/jq"; do
            ldd $binary | while read -r line; do
                echo "LINE: $line"
            done
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
    popd
}

main "$@"
