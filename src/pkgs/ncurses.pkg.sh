set -e
set -u
set -o pipefail

SRC_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJ_DIR="$(dirname "$(cd "$SRC_DIR" &> /dev/null && pwd)")"

source "$PROJ_DIR/src/termcolors.shlib"

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
    echo "${bold}${aqua}${SCRIPT_NAME}: Installing ${tool}${normal}"
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

function clean_ncurses() {
    local tool="NCurses"
    echo "${bold}${aqua}${SCRIPT_NAME}: Cleaning ${tool}${normal}"
    rm -rfv "${PROJ_DIR}/3rdparty/ncurses/build_tic"
    rm -rfv "${PROJ_DIR}/3rdparty/ncurses/build"
    git checkout -- "$PROJ_DIR/3rdparty/ncurses-6.5/"
}
