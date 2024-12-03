set -e
set -u
set -o pipefail

SRC_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJ_DIR="$(dirname "$(cd "$SRC_DIR" &> /dev/null && pwd)")/.."

pkgname="XFS Programs"
# shellcheck disable=SC2034
dependencies=(
    "autoconf"
    "automake"
    "bash"
    "binutils"
    "coreutils"
    "findutils"
    "glibc-devel"
    "git-core"
    "gzip"
    "libblkid-devel"
    "libedit-devel"
    "libicu-devel"
    "libinih-devel"
    "libtool"
    "liburcu-devel"
    "libuuid-devel"
    "make"
)

echo "PROJECT DIRECTORY: $PROJ_DIR"
source "$PROJ_DIR/src/termcolors.shlib"

function pkg_build() {
    echo "${bold}${aqua}${SCRIPT_NAME}: Building ${pkgname}${normal}"
    pushd "$PROJ_DIR/3rdparty/xfsprogs" >/dev/null
        # XFS progs REALLY doesn't know how to do out-of-source builds, so copy tree into temp dir
        mkdir -pv ../build
        cp -av ./* ../build/
        pushd ../build >/dev/null
            # there is no configure in the tarball, so generate one from the included configure.ac
            libtoolize -c -i -f -v
            cp -v include/install-sh .
            aclocal -I m4 --verbose
            autoconf -v
            export OPTIMIZER="-fPIC"
            export DEBUG=-DNDEBUG
            export LIBUUID=/usr/lib64/libuuid.a
            ./configure --prefix=/System \
                        --bindir=/System/bin \
                        --sbindir=/System/sbin \
                        --sysconfdir=/System/cfg \
                        --libdir=/System/lib64 \
                        --libexecdir=/System/lib \
                        --enable-prefix="" \
                        --enable-editline=yes
            make -j4
        popd >/dev/null
    popd >/dev/null
}

function pkg_install() {
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${pkgname}${normal}"
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

function pkg_clean() {
    echo "${bold}${aqua}${SCRIPT_NAME}: Cleaning ${pkgname}${normal}"
    rm -rfv "${PROJ_DIR}/3rdparty/xfsprogs/../build"
    git checkout -- "$PROJ_DIR/3rdparty/xfsprogs-6.10.1/"
}
