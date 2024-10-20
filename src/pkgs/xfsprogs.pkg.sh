set -e
set -u
set -o pipefail

SRC_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJ_DIR="$(dirname "$(cd "$SRC_DIR" &> /dev/null && pwd)")/.."

source "$PROJ_DIR/src/termcolors.shlib"

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

function clean_rsync() {
    local tool="XFS Programs"
    echo "${bold}${aqua}${SCRIPT_NAME}: Cleaning ${tool}${normal}"
    rm -rfv "${PROJ_DIR}/3rdparty/xfsprogs/../build"
    git checkout -- "$PROJ_DIR/3rdparty/xfsprogs-6.10.1/"
}
