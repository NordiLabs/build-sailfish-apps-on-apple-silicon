# Parity with the official `mb2 build`

Measured in November 2026 on an M1 Max Mac (OrbStack), Sailfish OS SDK target **5.1.0.11 aarch64**. The official side ran in the SDK build engine container (`mb2 -t SailfishOS-5.1.0.11-aarch64 build`). Both sides built at the same absolute path. `SOURCE_DATE_EPOCH=1700000000`, `clamp_mtime_to_source_date_epoch`, `use_source_date_epoch_as_buildtime` and `_buildhost` were set on both sides.

## Gates

| Gate | Mini app (6 objects) | Real app, minimal profile (176 objects) | Real app, standard profile (176) | Release candidate (292) | Harbour profile (247) |
|---|---|---|---|---|---|
| Makefile, DEFINES/CXXFLAGS/INCPATH/LFLAGS/LIBS, object list | identical | identical | identical | identical | identical |
| Every `.o` | 6/6 | 176/176 | 176/176 | 292/292 | 247/247 |
| Linked binary (with the SDK's i486 `ld`) | identical | identical | identical | identical | identical |
| `moc_*.cpp`, `qrc_*.cpp` | 3/3 | 61/61 | 61/61 | 78/78 | 78/78 |
| `.qm` translations | identical | identical | identical | identical | identical |
| RPM bytes (SHA-256) | identical | identical | identical | identical | identical |
| File list, modes, owners, digests, requires, provides, scripts, header tags | identical | identical | identical | identical | identical |
| Harbour validator (`rpmvalidation`) output | identical | identical | identical | identical | identical |

In total, 897 of 897 object files were byte-identical across five builds.

**Other checks**
- Building natively in a different directory still gives byte-identical RPMs (no build path is embedded without `-g`).
- A fresh container restored from a saved image reproduced both RPMs with the official SHA-256.
- Without pinning the volatile fields, the RPMs differ only in build time, build host and file mtimes.

## Why the toolchains match

- **Compiler.** The SDK cross compiler (`cross-aarch64-gcc-13.4.0+git2`, an i486 binary) and Jolla's native `gcc-13.4.0+git2-1.9.2.jolla` come from the same source package: both report `gcc version 13.4.0 20250605 (Sailfish OS gcc 13.4.0-1)`, target `aarch64-meego-linux-gnu`, `--with-arch=armv8-a`. Their `Configured with:` lines differ only in host, prefix, sysroot and packaging options. They are different binaries, so equivalent code generation is shown by measurement, not assumed.
- **The cross gcc cannot run natively on Apple Silicon.** It is a 32-bit x86 ELF; Apple Silicon has no 32-bit mode and Rosetta only handles x86-64. A native equivalent already exists in Jolla's repositories, so nothing had to be rebuilt.
- **Linker.** Both sides use GNU ld 2.45. The aarch64-hosted ld produces the same sections but different bytes in `.note.gnu.build-id`, `.hash`, `.dynsym`, `.dynstr`, `.symtab` and `.strtab`: the same symbol set in a different order. The cause is not proven; host word size (32-bit vs 64-bit) in ld's hashing and table ordering is the likely one. Linking through the SDK's own i486 `ld` (under qemu-i386, about 5 s) gives zero differing bytes. It needs `LD_AS_NEEDED=1`, which the Mer rpm macros export, and `--sysroot=/ -rpath-link /usr/lib64:/lib64:/usr/lib:/lib`, which the wrapper installed by `scripts/install_x86_ld.sh` adds.
- **Packaging.** The target's `rpmbuild` 4.16.1.3 runs natively with the arguments `mb2` passes (see the README). The official side runs the same steps through sb2 with qemu for host tools and target programs.

## Speed

| Run | Native | Official (emulated) |
|---|---|---|
| Standard profile, full RPM, `-j4`, run alone | **57 s** | **38 min 47 s** wall (138 min CPU) |
| Release candidate (292 objects), with other builds running | 110 s | 114 min 53 s |
| Mini app | 2 s | 3 min |

## Not covered

- Inputs built natively vs through sb2 (for example a third-party library built in the native container instead of under sb2). We used the same staged inputs on both sides.
- Debug builds (`--enable-debug`), signing, and rpmlint (the SDK build engine ships no rpmlint, so there is no official result to compare against).
- Every possible project. GCC code generation is expected to be host-independent, and every object we compared matched, but this is a measurement, not a guarantee. Compare a candidate against `mb2` before relying on it.

## Quirks of `mb2` we hit along the way

- `mb2 build … -- <rpmbuild args>` passes the arguments after `--` to rpmbuild as file names. Put `--define` and `--with/--without` after the `mb2` options, without `--`.
- `mb2` can exit 1 although the RPM was written, when its post-build `rpmspec` query on the i486 host hits an `%ifnarch aarch64` condition in the spec.
- `rpmvalidation` rejects an RPM whose file name differs from `<name>-<version>-<release>.<arch>.rpm`, and could not read files under `/tmp`.
