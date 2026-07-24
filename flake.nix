{
  description = "gdb-static — statically-linked, musl, cross-arch GDB builds (Nix port)";

  # No extra substituter is declared. CI restores the cross toolchains from the
  # GitHub Actions cache (.github/workflows/seed-cache.yaml) rather than from a
  # hosted binary cache, so there is nothing for a clone to opt into: a local
  # cold build compiles gcc + musl for arm/powerpc/mips from source. x86_64 and
  # aarch64 musl static toolchains come from cache.nixos.org as usual.

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Fork sources are git submodules consumed as local paths, NOT remote flake
    # inputs. Build with `nix build '.?submodules=1#...'` so `self` includes the
    # submodule working trees. See PORTING_NIX.md "Decisions (locked)".
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";

      # ---- Per-architecture cross configuration --------------------------
      # `crossSystem` mirrors the musl target triples from build.sh's HOST map.
      # `bfd` is the gdb --enable-targets name used for full cross-debug builds.
      # `testCC`/`qemu` are the compiler + emulator names src/tests expects
      # (COMPILERS / EMULATORS maps in misc.py); qemu = null runs natively.
      # mips/mipsel are soft-float (muslsf) to match `-muslsf` toolchains.
      archs = {
        x86_64 = {
          crossSystem.config = "x86_64-unknown-linux-musl";
          bfd = "x86_64-linux";
          testCC = "g++";
          qemu = null;
        };
        aarch64 = {
          crossSystem.config = "aarch64-unknown-linux-musl";
          bfd = "aarch64-linux";
          testCC = "aarch64-linux-gnu-g++";
          qemu = "qemu-aarch64";
        };
        arm = {
          # armv5tel → nixpkgs system "armv5tel-linux" (musl-supported); baseline
          # soft-float ARM matching build.sh's arm-linux-musleabi. Bare "arm-*"
          # elaborates to "arm-linux" which musl.meta.platforms rejects.
          crossSystem.config = "armv5tel-unknown-linux-musleabi";
          bfd = "arm-linux";
          testCC = "arm-linux-gnueabi-g++";
          qemu = "qemu-arm";
        };
        powerpc = {
          crossSystem.config = "powerpc-unknown-linux-musl";
          bfd = "powerpc-linux";
          testCC = "powerpc-linux-gnu-g++";
          qemu = "qemu-ppc";
        };
        mips = {
          crossSystem = {
            config = "mips-unknown-linux-musl";
            gcc.float = "soft";
          };
          bfd = "mips-linux";
          testCC = "mips-linux-gnu-g++";
          qemu = "qemu-mips";
        };
        mipsel = {
          crossSystem = {
            config = "mipsel-unknown-linux-musl";
            gcc.float = "soft";
          };
          bfd = "mipsel-linux";
          testCC = "mipsel-linux-gnu-g++";
          qemu = "qemu-mipsel";
        };
      };

      # Comma-joined BFD target list for full builds (--enable-targets).
      bfdArchs =
        nixpkgs.lib.concatStringsSep "," (map (a: a.bfd) (builtins.attrValues archs));

      # pkgsStatic cross package set for a given arch.
      pkgsForArch = arch:
        (import nixpkgs {
          localSystem = system;
          crossSystem = archs.${arch}.crossSystem;
        }).pkgsStatic;

      # ---- static CPython (Phase 4b) -------------------------------------
      # Cross-compiles the guyush1/cpython-static fork as a fully static
      # libpython, with gdb's own python lib and pygments *frozen* into the
      # interpreter (EXTRA_FROZEN_MODULES). Mirrors build.sh:build_python.
      # Output ships a working cross python3-config that gdb --with-python
      # consumes. libffi is a buildInput for the ctypes module.
      mkCpython = { arch }:
        let
          pkgs = pkgsForArch arch;
          pyVer = "3.14";
          buildPython = pkgs.buildPackages.python314;
          # gdb's bundled python support lib and pygments, frozen into libpython.
          gdbPyLib = builtins.path {
            path = ./src/submodule_packages/binutils-gdb/gdb/python/lib;
            name = "gdb-python-lib";
          };
          pygments = builtins.path {
            path = ./src/submodule_packages/pygments;
            name = "pygments-src";
          };
        in
        pkgs.stdenv.mkDerivation {
          pname = "cpython-static-${arch}";
          version = "3.14.5";
          src = builtins.path {
            path = ./src/submodule_packages/cpython-static;
            name = "cpython-static-src";
          };

          nativeBuildInputs = with pkgs.buildPackages; [
            buildPython pkg-config autoconf ncurses.dev
          ];
          depsBuildBuild = [ pkgs.buildPackages.stdenv.cc ];
          # Deliberately NO bzip2/openssl: adding them makes CPython compile the
          # _bz2/_ssl modules into libpython.a, but python-config --embed --ldflags
          # doesn't emit -lbz2/-lssl/-lcrypto, so gdb --with-python fails to link
          # on their undefined symbols. Upstream build.sh omits them too.
          buildInputs = with pkgs; [
            libffi ncurses expat xz zlib
          ];

          # Custom CONFIG_SITE + freeze knobs. Static everything.
          CONFIG_SITE = ./src/compilation/static-python.site;
          MODULE_BUILDTYPE = "static";
          LINKFORSHARED = " ";

          configureFlags = [
            "--disable-test-modules"
            "--with-ensurepip=no"
            "--without-decimal-contextvar"
            "--with-build-python=${buildPython}/bin/python${pyVer}"
            "--disable-ipv6"
            "--disable-shared"
          ];

          # build.sh passes these through the environment; static libs must be
          # named explicitly so they get linked into libpython's static modules.
          preConfigure = ''
            export CFLAGS="''${CFLAGS:-} -static"
            export LDFLAGS="''${LDFLAGS:-} -static"
            export CURSES_LIBS="-lncursesw"
            export PANEL_LIBS="-lpanelw"
            export ZLIB_LIBS="-lz"
            export LIBS="''${LIBS:-} -lexpat -lffi -llzma -lpanelw -lncursesw -lz"
          '';

          # Between configure and build: freeze the stdlib subset plus gdb and
          # pygments into the interpreter, then regenerate the frozen tables.
          postConfigure = ''
            frozen="$(tr '\n' ';' < ${./src/compilation/frozen_python_modules.txt})"
            export EXTRA_FROZEN_MODULES="$frozen<gdb.**.*>: gdb = ${gdbPyLib};<pygments.**.*>: pygments = ${pygments}"
            echo "Frozen modules: $EXTRA_FROZEN_MODULES"
            ${buildPython}/bin/python${pyVer} ./Tools/build/freeze_modules.py
            make regen-frozen
          '';

          # The HACL* crypto (_sha*/_md5/_blake2 modules) build as standalone
          # static archives that python3-config references via -L$out/Modules/_hacl
          # but `make install` doesn't ship. gdb --with-python links them, so
          # install them where the recorded -L path expects.
          postInstall = ''
            mkdir -p "$out/Modules/_hacl"
            cp Modules/_hacl/*.a "$out/Modules/_hacl/"
          '';

          enableParallelBuilding = true;
          meta.description = "Static CPython ${pyVer} with frozen gdb+pygments (${arch})";
        };

      # ---- gdb derivation ------------------------------------------------
      # enablePython gates the static-CPython path (Phase 4b). Full builds
      # currently ship cross-arch debugging (--enable-targets) but not yet
      # embedded Python; the flag defaults off until cpython-static lands.
      mkGdb = { arch, buildType, enablePython ? false }:
        let
          pkgs = pkgsForArch arch;
          isFull = buildType == "full";
          withPython = isFull && enablePython;
          cpython = mkCpython { inherit arch; };
          # Full builds debug every supported arch, not just the native one.
          fullFlags = [
            "--enable-targets=${bfdArchs}"
            "--enable-64-bit-bfd"
            "--disable-sim"
          ];
          pythonFlag =
            if withPython
            then "--with-python=${cpython}/bin/python3.14-config"
            else "--without-python";
        in
        pkgs.stdenv.mkDerivation {
          pname = "gdb-static-${arch}-${buildType}";
          version = "17.2";
          src = builtins.path {
            path = ./src/submodule_packages/binutils-gdb;
            name = "binutils-gdb-src";
          };

          # Build-host tooling. The cross stdenv already supplies the
          # cross gcc/binutils; these are the autotools/regen helpers.
          nativeBuildInputs = with pkgs.buildPackages; [
            autoconf automake libtool m4 texinfo perl bison flex pkg-config
          ];

          # bfd/gdb build native helper tools (e.g. `chew`) with CC_FOR_BUILD.
          # Provide a build->build compiler so plain `gcc` exists in PATH.
          depsBuildBuild = [ pkgs.buildPackages.stdenv.cc ];

          # Target static libraries gdb links against.
          buildInputs = (with pkgs; [
            gmp mpfr ncurses expat xz zlib libiconv
          ]) ++ nixpkgs.lib.optionals withPython [ pkgs.libffi cpython ];

          # Match build.sh: -Os everywhere, strip at link.
          env = {
            NIX_CFLAGS_COMPILE = "-Os";
            NIX_CFLAGS_LINK = "-s";
          };

          configureFlags = [
            "--enable-static"
            "--with-static-standard-libraries"
            "--disable-inprocess-agent"
            "--with-gdb-datadir=/usr/share/gdb"
            "--with-separate-debug-dir=/usr/lib/debug"
            "--with-system-gdbinit=/etc/gdb/gdbinit"
            "--with-system-gdbinit-dir=/etc/gdb/gdbinit.d"
            "--with-jit-reader-dir=/usr/lib/gdb"
            "--with-libiconv-prefix=${pkgs.libiconv}"
            "--with-libiconv-type=static"
            "--with-gmp=${pkgs.gmp.dev or pkgs.gmp}"
            "--with-mpfr=${pkgs.mpfr.dev or pkgs.mpfr}"
            "--enable-tui"
            "--with-system-zlib"
            "--with-expat"
            "--with-libexpat-type=static"
            "--with-lzma=yes"
            "--with-liblzma-type=static"
            pythonFlag
          ] ++ nixpkgs.lib.optionals isFull fullFlags;

          enableParallelBuilding = true;

          # Mirror install_gdb(): `make install` into a throwaway DESTDIR (the
          # configure hardcodes absolute runtime paths like /usr/share/gdb that
          # are unwritable in the sandbox), then ship only the executables.
          installPhase = ''
            runHook preInstall
            dest="$NIX_BUILD_TOP/dest"
            make -j$NIX_BUILD_CORES DESTDIR="$dest" install
            mkdir -p "$out/bin"
            find "$dest" -type f -path '*/bin/*' -executable \
              -exec cp -p {} "$out/bin/" \;
            runHook postInstall
          '';

          postInstall = ''
            find "$out/bin" -type f -exec file {} \;
          '';

          meta.description = "Statically linked GDB (${arch}, ${buildType})";
        };

      # ---- test check (Phase 5) ------------------------------------------
      # Runs src/tests (pytest) against a built gdb: binary properties, a
      # qemu-hosted `disas main`, and python integration (full = pygments+
      # ctypes work; slim = scripting disabled). The musl-static cross g++ is
      # reused as the arch's test compiler (symlinked to the COMPILERS name),
      # avoiding a second gnu toolchain; qemu-user provides the EMULATORS.
      npkgs = import nixpkgs { localSystem = system; };
      testsSrc = builtins.path { path = ./src/tests; name = "gdb-static-tests"; };
      mkCheck = { arch, buildType }:
        let
          a = archs.${arch};
          pkgs = pkgsForArch arch;
          crossCC = pkgs.stdenv.cc;
          ccBin = "${crossCC.targetPrefix}g++";
          gdb = self.packages.${system}."gdb-static-${arch}-${buildType}";
          pytestPy = npkgs.python3.withPackages (ps: [ ps.pytest ]);
        in
        npkgs.runCommand "check-gdb-static-${arch}-${buildType}"
          {
            nativeBuildInputs = [ pytestPy npkgs.file crossCC ]
              ++ nixpkgs.lib.optional (a.qemu != null) npkgs.qemu;
          }
          ''
            export HOME="$TMPDIR"
            # Recreate the src/tests layout conftest.py resolves root_dir from.
            mkdir -p src build/artifacts/${arch}_${buildType}
            cp -r --no-preserve=mode ${testsSrc} src/tests
            cp ${gdb}/bin/gdb           build/artifacts/${arch}_${buildType}/gdb
            cp ${gdb}/bin/gdbserver     build/artifacts/${arch}_${buildType}/gdbserver
            # Expose the arch's expected compiler name (COMPILERS[arch]) on PATH.
            mkdir shim
            ln -s ${crossCC}/bin/${ccBin} shim/${a.testCC}
            export PATH="$PWD/shim:$PATH"
            python -m pytest src/tests \
              --arch ${arch} --build-type ${buildType} -v
            touch "$out"
          '';
    in
    {
      packages.${system} =
        # slim + full variant for every arch. Full = cross-arch debugging
        # (--enable-targets over every bfd arch); embedded Python is Phase 4b.
        (nixpkgs.lib.mapAttrs'
          (arch: _:
            nixpkgs.lib.nameValuePair
              "gdb-static-${arch}-slim"
              (mkGdb { inherit arch; buildType = "slim"; }))
          archs)
        // (nixpkgs.lib.mapAttrs'
          (arch: _:
            nixpkgs.lib.nameValuePair
              "gdb-static-${arch}-full"
              (mkGdb { inherit arch; buildType = "full"; enablePython = true; }))
          archs)
        // (nixpkgs.lib.mapAttrs'
          (arch: _:
            nixpkgs.lib.nameValuePair
              "cpython-static-${arch}"
              (mkCpython { inherit arch; }))
          archs);

      # `nix flake check` runs the pytest suite for every arch × {slim,full}.
      checks.${system} =
        builtins.listToAttrs (nixpkgs.lib.flatten (map
          (arch: map
            (buildType: {
              name = "gdb-static-${arch}-${buildType}";
              value = mkCheck { inherit arch buildType; };
            })
            [ "slim" "full" ])
          (builtins.attrNames archs)));
    };
}
