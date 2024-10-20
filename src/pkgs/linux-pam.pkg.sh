set -e
set -u
set -o pipefail

SRC_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJ_DIR="$(dirname "$(cd "$SRC_DIR" &> /dev/null && pwd)")/.."

source "$PROJ_DIR/src/termcolors.shlib"

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

function clean_linuxpam() {
    local tool="Linux PAM"
    echo "${bold}${aqua}${SCRIPT_NAME}: Cleaning ${tool}${normal}"
    rm -rfv "${PROJ_DIR}/3rdparty/pam/build"
    git checkout -- "$PROJ_DIR/3rdparty/Linux-PAM-1.6.1/"
}
