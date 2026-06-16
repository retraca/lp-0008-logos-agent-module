{
  description = "agent_module — LP-0008 autonomous AI agent Logos Core Qt plugin";

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

        # Build-time deps
        buildInputs = with pkgs; [
          qt6.qtbase
          qt6.qtremoteobjects
          nlohmann_json
          cmake
          ninja
        ];

        nativeBuildInputs = with pkgs; [
          cmake
          ninja
          pkg-config
        ];

      in rec {
        # ---------- nix build ----------
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "agent_module";
          version = "0.0.1";

          src = ./.;

          inherit buildInputs nativeBuildInputs;

          QT_PLUGIN_PATH = "${pkgs.qt6.qtbase}/${pkgs.qt6.qtbase.qtPluginPrefix}";

          cmakeFlags = [
            "-DLOGOS_MODULE_BUILDER_DIR=${logos-module-builder}"
            "-GNinja"
          ];

          configurePhase = ''
            cmake -S "$src" -B build \
              -DLOGOS_MODULE_BUILDER_DIR="${logos-module-builder}" \
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
            description = "LP-0008 agent_module Qt plugin for Logos Core";
            homepage = "https://github.com/logos-co/logos-module-builder";
            platforms = pkgs.lib.platforms.linux ++ pkgs.lib.platforms.darwin;
          };
        };

        # Alias: nix build .#lib
        packages.lib = packages.default;

        # ---------- nix develop ----------
        devShells.default = pkgs.mkShell {
          inherit buildInputs nativeBuildInputs;

          # logos-module-builder provides: logos-cpp-generator, LogosModule.cmake,
          # LOGOS_SDK_INCLUDE_DIR, LOGOS_MODULE_BUILDER_DIR.
          inputsFrom = [ logos-module-builder.devShells.${system}.default or {} ];

          shellHook = ''
            export LOGOS_MODULE_BUILDER_DIR="${logos-module-builder}"
            export Qt6_DIR="${pkgs.qt6.qtbase}/lib/cmake/Qt6"
            export PATH="${pkgs.qt6.qtbase}/bin:$PATH"

            echo ""
            echo "agent_module dev shell ready."
            echo "Build:"
            echo "  cmake -B build -GNinja"
            echo "  ninja -C build"
            echo ""
            echo "Inspect:"
            echo "  lm methods ./build/agent_module_plugin.so --json"
            echo ""
          '';
        };
      }
    );
}
