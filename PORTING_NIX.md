# Porting gdb-static to Nix — Plan

## Decisions (locked)
- **Sources:** keep git submodules. Flake consumes forks via local path
  (`./src/submodule_packages/...`), so the flake needs `submodules = true` and a
  dirty-tree story (`nix build '.?submodules=1'` or committed submodule state).
  No fork repos as flake inputs.
- **Dep versions:** use nixpkgs stock for gmp/mpfr/ncurses/iconv/xz/zlib/expat/libffi.
  Only add a versioned override if the gdb fork actually rejects the stock version.
- **Scope now:** plan only. No `flake.nix` yet.

## Goal
Replace `Makefile + Docker + build.sh` with a `flake.nix` that produces the same
12 artifacts (`{x86_64,arm,aarch64,powerpc,mips,mipsel}` × `{slim,full}`) as
statically-linked musl binaries, reproducibly, without Docker.

Target UX:
```
nix build .#gdb-static-aarch64-full
nix build .#all            # everything
nix flake check            # pytest + qemu tests
```

## Current-state audit (what maps to what)

| Today | Nix replacement |
|---|---|
| Dockerfile (Ubuntu + apt) | gone — nixpkgs provides everything |
| `download_musl_toolchains.py` + musl-cross-make releases | `pkgsCross.<arch>.pkgsStatic` (native nixpkgs musl cross) |
| `download_packages.sh` (iconv/gmp/mpfr/ncurses tarballs) | nixpkgs `gmp mpfr ncurses libiconv` (static overrides) |
| `install_autoconf.sh`, `autogen.sh` calls | nixpkgs `autoconf/automake/libtool` in nativeBuildInputs |
| `build_iconv/gmp/mpfr/ncurses/expat/lzma/zlib/libffi` | nixpkgs static packages — deleted |
| `binutils-gdb` submodule (fork) | local submodule source → custom gdb derivation |
| `cpython-static` submodule (fork) | local submodule source → custom python derivation (freeze step) |
| `pygments` submodule | local submodule source (frozen into python) |
| `libexpat`, `xz`, `libffi`, `zlib` submodules | nixpkgs stock static (submodules unused for these) |
| `Makefile` targets | flake `packages.*` attrs + thin Makefile wrapper (optional) |
| `pack-*` (tar.gz) | derivation postBuild or `apps.pack` |
| `static-python.site` `ac_cv_*` | `configureFlags` / `preConfigure` env in python derivation |
| pytest + qemu-user + cross g++ | `flake check` using nixpkgs `qemu` + `pkgsCross.*.stdenv.cc` |

## Build graph per (arch, type) — unchanged logically
```
musl-cross-toolchain (arch)         # nixpkgs pkgsCross.<arch>.pkgsStatic
  ├─ libiconv, gmp, mpfr(gmp), ncursesw, expat, xz/lzma, zlib   # nixpkgs static
  ├─ [full] libffi (+pkg-config)
  ├─ [full] cpython-static  ← frozen(gdb/python/lib, pygments)  # THE hard one
  └─ gdb (fork) ─ static, links all of the above
```

## Key derivations to write

### 1. `gdb` (fork)
Override or hand-roll from the `binutils-gdb` fork input. Reuse the exact configure
flags from `build.sh:build_gdb`:
```
--enable-static --with-static-standard-libraries --disable-inprocess-agent
--with-libiconv-type=static --with-gmp --with-mpfr
--with-expat --with-libexpat-type=static
--with-lzma=yes --with-liblzma-type=static
--enable-tui --with-system-zlib
# full only:
--enable-targets=<bfd archs> --enable-64-bit-bfd --disable-sim
--with-python=<python3-config>   # else --without-python
```
Runtime paths (`--with-gdb-datadir=/usr/share/gdb`, gdbinit dirs, jit-reader-dir)
kept identical so relocatable-binary behavior matches releases.
`CFLAGS=-Os`, `LDFLAGS=-s` (strip) — trivial in nix.

### 2. `cpython-static` (fork) — full build only
Hardest piece. Must reproduce `build.sh:build_python`:
- Cross-build static libpython from the fork (`--disable-shared --with-ensurepip=no
  --without-decimal-contextvar --disable-ipv6`), `--with-build-python` = a **native**
  python of the same version (nixpkgs gives this for free as the build-host python).
- Fold `static-python.site` `ac_cv_*` values into `configureFlags`/env
  (`ac_static_libhacl=yes`, curses/panel/zlib module forces, `with_system_expat`).
- Frozen modules: set `EXTRA_FROZEN_MODULES` from `frozen_python_modules.txt` **plus**
  `gdb = <gdb fork>/gdb/python/lib` and `pygments = <pygments input>`, then run
  `Tools/build/freeze_modules.py` + `make regen-frozen` before `make`.
- `libffi` (static) wired via pkg-config, matching `setup_libffi_env`.

This is the one derivation that needs real iteration — budget most of the time here.

### 3. Static deps
Prefer `nixpkgs` `pkgsStatic` versions. Pin exact versions only if the fork/gdb
needs them (iconv 1.19, gmp 6.3.0, mpfr 4.2.2, ncurses 6.6). ncurses must be
`--enable-widec` with `--with-default-terminfo-dir=/usr/share/terminfo` (runtime
path — keep).

## Architecture risk register
- **x86_64 / aarch64 / arm** — `pkgsCross.*.pkgsStatic` well-supported. Low risk.
- **powerpc (32-bit BE musl)** — may need a custom `crossSystem` def. Medium risk.
- **mips / mipsel soft-float** — nixpkgs default mips is hard-float; must define
  custom `crossSystem` with `gcc.arch`/`float = "soft"` to match current `-muslsf`.
  **Highest risk** — validate ABI early (qemu run a hello-world).
- Verify each custom crossSystem actually yields a musl static toolchain, not glibc.

## Migration phases (incremental, each independently shippable)
0. **Scaffold** — `flake.nix`, convert submodules → flake inputs (pin same commits).
1. **slim x86_64** — prove the gdb-fork derivation + static deps. Diff binary vs
   current release (size, `file`, `ldd` → not a dynamic executable).
2. **slim cross** — aarch64 + arm. Prove cross-static path.
3. **exotic arches** — powerpc, mips/mipsel soft-float custom crossSystems.
4. **full build** — libffi + frozen cpython + `--enable-targets` BFD. The long pole.
5. **tests** — port `src/tests` into `flake check` (qemu-user + cross g++ from nix).
6. **CI + cleanup** — swap `pipeline.yaml` to `nix build`/`nix flake check` on a
   nixpkgs matrix; delete Dockerfile, `download_*`, `install_autoconf.sh`, `build.sh`,
   `utils.sh`, `full_build_conf.sh`. Keep `static-python.site` values inside the flake.

## Definition of done
- All 12 `nix build .#gdb-static-<arch>-<type>` succeed on a clean machine with only
  Nix installed (no Docker, no apt).
- `file` reports statically linked; qemu runs `gdb --version` per arch.
- pytest suite passes under `nix flake check`.
- Byte-for-behavior parity with current release artifacts (feature set: TUI, python,
  cross-arch debugging in full; base in slim).

## What we keep vs delete
Delete: `Dockerfile`, `src/docker_utils/`, `download_packages.sh`,
`install_autoconf.sh`, `build.sh`, `utils.sh`, `full_build_conf.sh`.
Keep (fold into flake): `frozen_python_modules.txt`, `static-python.site` values,
`src/tests/*`, `compilation.md` (as docs), the fork submodules (as inputs).
Optional: thin `Makefile` that shells out to `nix build` for muscle memory.
