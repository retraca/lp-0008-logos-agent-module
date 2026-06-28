{
  description = "lez_wallet_module — Logos Core Qt plugin wrapping the shielded LEZ wallet (LP-0008)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/e9f00bd893984bc8ce46c895c3bf7cac95331127";  # Qt 6.9.2
    logos-module-builder = {
      url = "github:logos-co/logos-module-builder";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Build the wallet as a real loadable Logos Core module via mkLogosModule
  # (same path the agent uses), linking the prebuilt lez-bridge Rust core in
  # ./corelib/liblez_wallet_core.a. The FFI header (lez_wallet_ffi.h) is committed.
  outputs = inputs@{ self, nixpkgs, logos-module-builder }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
      preConfigure = ''
        export LEZ_WALLET_CORE_DIR="$PWD/corelib"
        echo "LEZ_WALLET_CORE_DIR=$LEZ_WALLET_CORE_DIR"
        ls -la "$LEZ_WALLET_CORE_DIR" || true
      '';
      postInstall = ''
        cp ${./metadata.json} $out/metadata.json
      '';
    };
}
