#!/bin/bash
# Recreate the persistent native build container from scratch (about 270 MB of downloads).
#   create_native_container.sh [--name sfos-m1-native] [--cpus 8] [--memory 10g]
# Needs: OrbStack/Docker on an arm64 host, curl, tar, shasum. Idempotent for the image; refuses to replace a running
# container of the same name unless it is removed first. Does not stage vendor/taglib or vendor/icu (see README.md).
set -eu
NAME=sfos-m1-native; CPUS=8; MEM=10g; REL=5.1.0.11
while [ $# -gt 0 ]; do case "$1" in --name) NAME="$2"; shift 2;; --cpus) CPUS="$2"; shift 2;; --memory) MEM="$2"; shift 2;; *) echo "bad arg $1"; exit 2;; esac; done
dk() { docker -H "${DOCKER_SOCK:-unix://$HOME/.orbstack/run/docker.sock}" "$@"; }
IMAGE="$NAME:$REL"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/sfos-create.XXXXXX"); trap 'rm -rf "$WORK"' EXIT
dk image inspect "$IMAGE" >/dev/null 2>&1 && { echo "image $IMAGE exists; reusing it"; REUSE=1; } || REUSE=0
if [ "$REUSE" = 0 ]; then
  T=https://releases.sailfishos.org/sdk/targets/Sailfish_OS-$REL-Sailfish_SDK_Target-aarch64.tar.7z
  R=https://releases.jolla.com/releases/$REL/jolla/aarch64/oss/aarch64
  mkdir -p "$WORK/dl"; cd "$WORK/dl"
  curl -fsS -O "$T"; curl -fsS "$T.md5sum" > target.md5
  [ "$(md5 -q Sailfish_OS-$REL-Sailfish_SDK_Target-aarch64.tar.7z 2>/dev/null || md5sum Sailfish_OS-$REL-Sailfish_SDK_Target-aarch64.tar.7z | cut -d' ' -f1)" = "$(cut -d' ' -f1 target.md5)" ] || { echo "target md5 mismatch"; exit 1; }
  # Native toolchain RPMs (versions as published for 5.1.0.11; update when the release changes).
  for r in binutils-2.45+git2-1.9.2.jolla cpp-13.4.0+git2-1.9.2.jolla gcc-13.4.0+git2-1.9.2.jolla gcc-c++-13.4.0+git2-1.9.2.jolla \
           libstdc++-devel-13.4.0+git2-1.9.2.jolla libgomp-13.4.0+git2-1.9.2.jolla make-4.4.1-1.6.2.jolla mpfr-4.2.1-1.7.2.jolla \
           gmp-6.3.0-1.7.2.jolla mpc-1.3.1+git1-1.13.3.jolla ccache-4.9.1+git1-1.6.2.jolla; do curl -fsS -O "$R/$r.aarch64.rpm"; done
  # An Alpine arm64 helper does the extraction (7z, bsdtar) so nothing is needed on the Mac.
  dk run --rm --platform linux/arm64 -v "$WORK/dl:/dl:ro" alpine:3.22.2 sh -c '
    set -e; apk add --no-cache 7zip libarchive-tools >/dev/null 2>&1; mkdir /rootfs; cd /rootfs
    7z x -so /dl/Sailfish_OS-'$REL'-Sailfish_SDK_Target-aarch64.tar.7z | tar -x
    for r in /dl/*.rpm; do bsdtar -xpf "$r" -C /rootfs; done
    chroot /rootfs /usr/sbin/useradd -m -u 1000 -s /bin/bash sdk >/dev/null 2>&1 || true
    mkdir -p /rootfs/usr/local/bin
    printf "#!/bin/sh\n# sb2 shim: the container IS the aarch64 target, run the command directly\nwhile [ \"\$1\" != \"\" ]; do case \"\$1\" in -t|-R|-eR|-m|-M) shift 2;; --) shift; break;; -*) shift;; *) break;; esac; done\nexec \"\$@\"\n" > /rootfs/usr/local/bin/sb2
    chmod +x /rootfs/usr/local/bin/sb2
    tar -C /rootfs --exclude=./proc/* --exclude=./sys/* -c .' | dk import --platform linux/arm64 - "$IMAGE"
fi
dk volume create "$NAME-builds" >/dev/null; dk volume create "$NAME-ccache" >/dev/null
dk run -d --name "$NAME" --restart unless-stopped --cpus "$CPUS" --memory "$MEM" --platform linux/arm64 \
  -v "$NAME-builds:/builds" -v "$NAME-ccache:/ccache" --entrypoint /usr/bin/sleep "$IMAGE" infinity >/dev/null
dk exec "$NAME" sh -c 'chown 1000:100000 /builds /ccache; chmod 777 /builds /ccache'
dk exec -u sdk "$NAME" sh -c 'g++ --version | head -1; qmake -query QT_VERSION; uname -m'
echo "container $NAME ready. Next: scripts/install_x86_ld.sh, then build your RPM (README.md)."
