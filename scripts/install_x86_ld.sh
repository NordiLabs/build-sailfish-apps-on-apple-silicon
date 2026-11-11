#!/bin/bash
# Install the SDK's i486 cross linker (run under the kernel's qemu-i386 binfmt) into the native container as /opt/x86ld,
# so parity builds can link exactly like the official toolchain. Compile stays native; only `ld` is emulated (about 5 s).
#   install_x86_ld.sh <container> <source>
# source is either the SDK build engine container (files under /srv/mer/toolings/<release>, the same ones `mb2` uses)
# or a local directory with bin/ld, lib/ld-linux.so.2 and lib/libc.so.6.
# The tooling tarball
# Sailfish_OS-<rel>-Sailfish_SDK_Tooling-i486.tar.7z (476 MB) holds the same files if neither is available.
set -eu
NAT=${1:-sfos-m1-native}; SRC=${2:?usage: install_x86_ld.sh <container> <sdk-build-engine-container-or-dir>}; REL=5.1.0.11
T=/srv/mer/toolings/SailfishOS-$REL
dk() { docker -H "${DOCKER_SOCK:-unix://$HOME/.orbstack/run/docker.sock}" "$@"; }
W=$(mktemp -d "${TMPDIR:-/tmp}/x86ld.XXXXXX"); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/lib" "$W/wrap"
if [ -d "$SRC" ]; then
  cp "$SRC/bin/ld" "$W/bin/ld"
  for f in ld-linux.so.2 libc.so.6; do cp "$SRC/lib/$f" "$W/lib/$f"; done
else
  dk cp "$SRC:$T/opt/cross/bin/aarch64-meego-linux-gnu-ld" "$W/bin/ld"
  for f in ld-linux.so.2 libc.so.6; do dk cp "$SRC:$T/lib/$f" "$W/lib/$f"; done
fi
cat > "$W/wrap/ld" <<'E'
#!/bin/sh
exec /opt/x86ld/lib/ld-linux.so.2 --library-path /opt/x86ld/lib /opt/x86ld/bin/ld --sysroot=/ -rpath-link /usr/lib64:/lib64:/usr/lib:/lib "$@"
E
chmod +x "$W/bin/ld" "$W/lib/ld-linux.so.2" "$W/wrap/ld"
dk exec "$NAT" rm -rf /opt/x86ld
dk cp "$W" "$NAT:/opt/x86ld"
dk exec "$NAT" sh -c 'chmod -R a+rX /opt/x86ld; /opt/x86ld/wrap/ld --version | head -1'
echo "installed. Use: export COMPILER_PATH=/opt/x86ld/wrap before linking (parity_check.sh does this by default)."
