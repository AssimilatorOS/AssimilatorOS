set -e
set -u
set -o pipefail

SRC_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJ_DIR="$(dirname "$(cd "$SRC_DIR" &> /dev/null && pwd)")/.."

source "$PROJ_DIR/src/termcolors.shlib"

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

function clean_grub() {
    local tool="GNU Grub v2"
    echo "${bold}${aqua}${SCRIPT_NAME}: Cleaning ${tool}${normal}"
    rm -rfv "${PROJ_DIR}/3rdparty/grub/build"
    pushd "${PROJ_DIR}/3rdparty/grub" >/dev/null
        rm -rfv __pycache__/
        rm -fv docs/grub2.info
        rm -fv docs/grub2.info-1
        rm -fv docs/grub2.info-2
        rm -fv docs/grub2.texi
        rm -fv po/*.po~
        rm -fv po/grub2.pot
    popd >/dev/null
    git checkout -- "$PROJ_DIR/3rdparty/grub-2.12/"
}
