<h1 align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="./.github/assets/gdb-static_logo_dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="./.github/assets/gdb-static_logo_light.svg">
    <img src="./.github/assets/gdb-static_logo_light.svg" alt="gdb-static" width="210px">
  </picture>
</h1>

<p align="center">
  <i align="center">Frozen static builds of everyone's favorite debugger!🧊</i>
</p>

<h4 align="center">
  <a href="https://github.com/guyush1/gdb-static/releases/latest">
    <img src="https://img.shields.io/github/v/release/guyush1/gdb-static?style=flat-square" alt="release" style="height: 20px;">
  </a>
  <a href="https://github.com/guyush1/gdb-static/graphs/contributors">
    <img src="https://img.shields.io/github/contributors-anon/guyush1/gdb-static?color=yellow&style=flat-square" alt="contributors" style="height: 20px;">
  </a>
  <img src="https://img.shields.io/badge/GDB-v17.1-orange?logo=gnu&logoColor=white&style=flat-square" alt="gdb" style="height: 20px;">
  <img src="https://img.shields.io/badge/Python-built--in-blue?logo=python&logoColor=white&style=flat-square" alt="python" style="height: 20px;">
</h4>

## TL;DR

- **Download**: Get the latest release from the [releases page](https://github.com/guyush1/gdb-static/releases/latest).

## Introduction

Who doesn't love GDB? It's such a powerful tool, with such a great package.  
But sometimes, you run into one of these problems:
- You can't install GDB on your machine
- You can't install an updated version of GDB on your machine
- Some other strange embedded reasons...

This is where `gdb-static` comes in! We provide static builds of `gdb` (and `gdbserver` of course), so you can run them on any machine, without any dependencies!

<details open>
<summary>
 Features
</summary> <br />

- **Static Builds**: No dependencies, no installation, just download and run!
- **Musl Based**: We use Musl in order to create distribution-independant binaries that can work anywhere.
- **Latest Versions**: We keep our builds up-to-date with the latest versions of GDB.
- **Builtin Python (Optional)**: We provide builds with Python support built-in.
- **XML Support**: Our builds come with XML support built-in, which is useful for some GDB commands.
- **Wide Architecture Support**: We support a wide range of architectures:
  - aarch64
  - arm
  - mips
  - mipsel
  - powerpc
  - x86_64

</details>

## Usage 

To get started with `gdb-static`, simply download the build for your architecture from the [releases page](https://github.com/guyush1/gdb-static/releases/latest), extract the archive, and copy the binary to your desired platform. <br />

You may choose to copy the `gdb` binary to the platform, or use `gdbserver` to debug remotely.

## Build types

We provide two types of builds:
1. Slim builds, that contains most of the features, beside the ones mentioned below.
2. Full builds that contains all of the slim build features, and also contains:
   * Python support
   * Cross-architecture debugging. <br />
   Note that in order to enable cross-architecture debugging, we have to disable the simulator feature, since not all targets have a simulator.

Slim builds are approximately ~10MB. Full builds are approximately ~70MB.

## Development

`gdb-static` is built with [Nix](https://nixos.org). There is no Docker and no
`make` — everything is derived from `flake.nix`, which cross-compiles fully
static musl binaries for every supported architecture.

<details open>
<summary>
Pre-requisites
</summary> <br />

- [Nix](https://nixos.org/download) with flakes enabled
  (`experimental-features = nix-command flakes`)
- Git

> [!NOTE]
> The flake consumes the forks as git submodules, so builds must pass
> `?submodules=1`. Make sure the submodules are initialized & synced first
> (`git submodule update --init --recursive`).
</details>

<details open>
<summary>
Building for a specific architecture
</summary> <br />

```bash
nix build '.?submodules=1#gdb-static-<ARCH>-<slim|full>'
```

Where `<ARCH>` is one of `x86_64`, `aarch64`, `arm`, `powerpc`, `mips`,
`mipsel`, and `slim`/`full` is the build type (see [here](#build-types)).
The executables land in `result/bin/` (`gdb`, `gdbserver`, and the binutils
tools).

</details>

<details open>
<summary>
Building everything / running the tests
</summary> <br />

```bash
# Build every artifact (6 arches × {slim, full}) and run the pytest suite
# for each under qemu-user:
nix flake check '.?submodules=1'
```

</details>

<details open>
<summary>
Binary cache
</summary> <br />

The `arm`, `powerpc`, `mips` and `mipsel` cross toolchains (gcc + musl) are not
in cache.nixos.org, so a cold build compiles them from source. `x86_64` and
`aarch64` are cached upstream and download as normal.

CI avoids the rebuild with the GitHub Actions cache: `seed-cache.yaml` builds
every architecture on `develop` and saves the Nix store per arch, and the PR
pipeline restores it read-only. No account, no secrets, nothing to configure.

That cache is internal to CI — there is no public substituter for this project,
so a local first build of the exotic architectures does pay the toolchain cost
once. It is then in your own `/nix/store` and never rebuilds.

</details>

<details open>
<summary>
Adding a custom architecture
</summary> <br />

Add an entry to the `archs` table in `flake.nix` with:

- `crossSystem` — the musl target triple (e.g. `aarch64-unknown-linux-musl`;
  set `gcc.float = "soft"` for soft-float targets like mips).
- `bfd` — the `--enable-targets` name used for full cross-debug builds.
- `testCC` / `qemu` — the compiler and emulator names the test suite expects
  (see `COMPILERS` / `EMULATORS` in `src/tests/misc.py`).

The `slim`, `full`, `cpython-static`, and `checks` outputs are generated over
that table automatically.

</details>

<a name="contributing_anchor"></a>
## Contributing

- Bug Report: If you see an error message or encounter an issue while using gdb-static, please create a [bug report](https://github.com/guyush1/gdb-static/issues/new?assignees=&labels=bug&title=%F0%9F%90%9B+Bug+Report%3A+).

- Feature Request: If you have an idea or if there is a capability that is missing and would make `gdb-static` more robust, please submit a [feature request](https://github.com/guyush1/gdb-static/issues/new?assignees=&labels=enhancement&title=%F0%9F%9A%80+Feature+Request%3A+).

## Contributors

<!---
npx contributor-faces --exclude "*bot*" --limit 70 --repo "https://github.com/guyush1/gdb-static"

change the height and width for each of the contributors from 80 to 50.
--->

[//]: contributor-faces
<a href="https://github.com/guyush1"><img src="https://avatars.githubusercontent.com/u/82650790?v=4" title="guyush1" width="80" height="80"></a>
<a href="https://github.com/roddyrap"><img src="https://avatars.githubusercontent.com/u/37045659?v=4" title="roddyrap" width="80" height="80"></a>
<a href="https://github.com/RoiKlevansky"><img src="https://avatars.githubusercontent.com/u/78471889?v=4" title="RoiKlevansky" width="80" height="80"></a>
<a href="https://github.com/sabae-valve"><img src="https://avatars.githubusercontent.com/u/185842408?v=4" title="sabae-valve" width="80" height="80"></a>

[//]: contributor-faces
