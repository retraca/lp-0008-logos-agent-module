{
  description = "lez_wallet_module — Logos Core Qt plugin wrapping the shielded LEZ wallet (LP-0008)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    logos-module-builder = {
      url = "github:logos-co/logos-module-builder";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, logos-module-builder }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ] (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # logos-module-builder exposes its Nix helpers under .lib
        lmb = logos-module-builder.lib.${system};

        # Path to the compiled lez-wallet-core Rust static lib.
        # Required at build time via LEZ_WALLET_CORE_DIR env var.
        lez_wallet_core_dir = builtins.getEnv "LEZ_WALLET_CORE_DIR";

        # rust-cbindgen is the nixpkgs package; the binary it ships is `cbindgen`
        cbindgenPkg = pkgs.rust-cbindgen;

        buildInputs = with pkgs; [
          qt6.qtbase
          qt6.qtremoteobjects
          cbindgenPkg
        ];

        nativeBuildInputs = with pkgs; [
          cmake
          ninja
          cbindgenPkg
          pkg-config
        ];

      in rec {
        # ---------- nix build ----------
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "lez_wallet_module";
          version = "0.1.0";

          src = ./.;

          inherit buildInputs nativeBuildInputs;

          QT_PLUGIN_PATH = "${pkgs.qt6.qtbase}/${pkgs.qt6.qtbase.qtPluginPrefix}";

          # LEZ_WALLET_CORE_DIR is validated at build time, not evaluation time.
          # Pass as env var; configurePhase reads it.
          LEZ_WALLET_CORE_DIR = if lez_wallet_core_dir != "" then lez_wallet_core_dir else "";

          configurePhase = ''
            if [ -z "$LEZ_WALLET_CORE_DIR" ]; then
              echo "ERROR: set LEZ_WALLET_CORE_DIR to the lez-wallet-core release dir before building" >&2
              exit 1
            fi

            echo "Running cbindgen to generate lez_wallet_ffi.h..."
            # cbindgen must run from the crate root (where Cargo.toml lives)
            LEZ_CORE_SRC="$(dirname "$LEZ_WALLET_CORE_DIR")"
            (cd "$LEZ_CORE_SRC" && cbindgen --lang C --output "$src/lez_wallet_ffi.h") 2>/dev/null || true

            cmake -S "$src" -B build \
              -DLOGOS_MODULE_BUILDER_DIR="${logos-module-builder}" \
              -DLEZ_WALLET_CORE_DIR="$LEZ_WALLET_CORE_DIR" \
              -GNinja
          '';

          buildPhase = ''
            ninja -C build
          '';

          installPhase = ''
            mkdir -p $out/lib
            find build -maxdepth 2 \( -name "*.so" -o -name "*.dylib" \) \
              -exec cp {} $out/lib/ \;
            cp metadata.json $out/
          '';

          meta = {
            description = "lez_wallet_module Qt plugin for Logos Core (LP-0008)";
            homepage = "https://github.com/logos-co/logos-module-builder";
            platforms = pkgs.lib.platforms.linux ++ pkgs.lib.platforms.darwin;
          };
        };

        packages.lib = packages.default;

        # ---------- nix develop ----------
        devShells.default = pkgs.mkShell {
          # Pull in logos-cpp-generator (and other Logos SDK tools) from upstream devShell.
          inputsFrom = [ logos-module-builder.devShells.${system}.default ];
          inherit buildInputs nativeBuildInputs;

          shellHook = ''
            export LOGOS_MODULE_BUILDER_DIR="${logos-module-builder}"
            export Qt6_DIR="${pkgs.qt6.qtbase}/lib/cmake/Qt6"
            export PATH="${pkgs.qt6.qtbase}/bin:$PATH"

            if [ -z "$LEZ_WALLET_CORE_DIR" ]; then
              echo ""
              echo "  NOTE: set LEZ_WALLET_CORE_DIR before building:"
              echo "    export LEZ_WALLET_CORE_DIR=\$(pwd)/../lez-wallet-core/target/release"
              echo ""
            fi
          '';
        };
      }
    );
}
