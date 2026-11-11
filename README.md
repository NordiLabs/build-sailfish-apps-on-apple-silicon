# Native Sailfish OS app builds on Apple Silicon

Build Sailfish OS aarch64 apps **natively on an Apple Silicon Mac**: the compiler runs as native arm64 code instead of under emulation. The resulting RPMs are **byte-for-byte identical** to the official `mb2 build` output.

| | Official `mb2 build` on Apple Silicon (emulated) | Native (this method) |
|---|---|---|
| Full RPM, real app (176 objects, `-j4`) | 38 min 47 s | **57 s** (~40× faster) |
| RPM bytes vs `mb2` | n/a | **identical** (same SHA-256) |

*Measured on an M1 Max Mac with OrbStack, Sailfish OS SDK target 5.1.0.11 (aarch64), November 2026.*

## Why

On an Apple Silicon Mac, the Sailfish SDK build engine runs its i486 tooling and cross compiler under qemu-user. Apple Silicon has no 32-bit x86 mode, and Rosetta only translates x86-64, so every compiler process is emulated. A medium-sized Qt/QML app takes 40 minutes to over an hour per RPM, which makes iterating on code painful.

Jolla already publishes a **native aarch64 GCC** (`gcc-13.4.0+git2 … jolla`) built from the same source package as the SDK's cross compiler. On an arm64 host, the SDK's **aarch64 target rootfs plus Jolla's native toolchain** gives a container that *is* the target, with no emulation for compiling.

## How it works

```
Apple Silicon Mac (arm64)
└── Docker / OrbStack, linux/arm64 container   (no qemu for compiling)
    ├── Sailfish SDK aarch64 target rootfs      (official tarball: same headers, Qt 5.6.3, libraries)
    ├── + Jolla's native aarch64 gcc/g++/binutils/make/ccache   (official RPMs)
    ├── rpmbuild with the exact arguments mb2 passes             (native)
    └── link step through the SDK's own i486 ld under qemu-i386  (~5 s, the only emulated step)
```

- **Compiler:** `gcc 13.4.0 (Sailfish OS gcc 13.4.0-1)`, target `aarch64-meego-linux-gnu`, the same source package and configuration as the SDK cross compiler. 897 of 897 object files were byte-identical across five builds.
- **Linker:** the native aarch64 GNU ld 2.45 produces the same sections, but with the symbol tables in a different order. Linking with the SDK's own i486 `ld`, which costs about 5 s under qemu-i386, gives a binary with zero differing bytes. If you don't need bit-for-bit parity, the pure native `ld` works too.
- **Packaging:** the target's own `rpmbuild` 4.16.1.3 runs natively. The spec's `lupdate`, `lrelease`, `strip` and the `brp-*` scripts give identical results.

Details and the full evidence: **[docs/PARITY.md](docs/PARITY.md)**.

## Quick start

Requirements: an Apple Silicon Mac, [OrbStack](https://orbstack.dev) (Docker Desktop should work but is untested), `curl` and `tar`. The scripts download everything from `releases.sailfishos.org` and `releases.jolla.com`; no SDK binaries are stored in this repository.

```sh
# 1. Build the native container (about 270 MB of downloads; verifies the target tarball's MD5)
scripts/create_native_container.sh --name sfos-m1-native --cpus 8 --memory 10g

# 2. Optional, for byte-identical RPMs: install the SDK's i486 linker
#    (from a running SDK build engine container, or a directory with bin/ld, lib/ld-linux.so.2 and lib/libc.so.6)
scripts/install_x86_ld.sh sfos-m1-native <sdk-build-engine-container-or-dir>
```

Then copy your project into the container and build the RPM with the same arguments `mb2` uses:

```sh
D="docker -H unix://$HOME/.orbstack/run/docker.sock"
$D cp ./myapp sfos-m1-native:/home/sdk/myapp
$D exec sfos-m1-native chown -R sdk /home/sdk/myapp
$D exec -u sdk -w /home/sdk/myapp sfos-m1-native sh -c '
  export COMPILER_PATH=/opt/x86ld/wrap      # only if you installed the i486 linker
  rpmbuild --build-in-place --target=aarch64-meego-linux-gnu \
    --define "debug_package %{nil}" --define "_smp_mflags -j8" \
    --define "_rpmdir $PWD/RPMS" --define "_sourcedir $PWD/rpm" \
    --define "_rpmfilename %%{name}-%%{version}-%%{release}.%%{arch}.rpm" \
    --define "__patch patch" --buildroot="$PWD/installroot" \
    -bb rpm/*.spec'
$D cp sfos-m1-native:/home/sdk/myapp/RPMS/. ./RPMS/
```

For byte-identical output against `mb2`, set `SOURCE_DATE_EPOCH` and the `clamp_mtime_to_source_date_epoch`, `use_source_date_epoch_as_buildtime` and `_buildhost` macros **on both sides**. Without them, two builds differ only in build time, host and file mtimes, as any two builds do.

For a fast edit-compile loop without packaging, run `qmake` and `make` as a shadow build inside the container with `ccache` (`CC="ccache gcc" CXX="ccache g++"`). On our project a no-change rebuild takes about 1 s, and an edited `.cpp` about 3 s.

## What it does not replace

- **Runtime testing.** The Mac cannot run Silica/QML apps; you still test on a device.
- **The official route for release provenance.** We used native builds for development and device testing. Each candidate was compared against `mb2` before trusting it, and `mb2` stayed authoritative for releases.
- **Other targets.** Measured on SDK target 5.1.0.11 aarch64 only. When the target changes, rebuild the container with the new tarball and RPM versions in `create_native_container.sh`.

## Ideas for the Sailfish SDK

- An **arm64-native build engine** (or target + native toolchain image) as an official SDK option for Apple Silicon and other arm64 hosts. The pieces already exist in Jolla's repositories.
- Find out why aarch64-hosted GNU ld 2.45 orders symbols differently from the i486-hosted one. With that fixed, the build would need no emulation at all.

## Background

This came out of building **SailTune**, a native Silica music player for Sailfish OS ([releases](https://github.com/NordiLabs/SailTune/releases)), where emulated builds made every iteration take most of an hour.

## License

The scripts and documentation in this repository are released under the MIT License (see [LICENSE](LICENSE)). The Sailfish OS SDK, the target rootfs and Jolla's packages are downloaded from their official sources and remain under their own licenses.
