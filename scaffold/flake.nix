{
  description = "agent_module — LP-0008 autonomous AI agent Logos Core Qt plugin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/e9f00bd893984bc8ce46c895c3bf7cac95331127";  # Qt 6.9.2 — logoscore rejects 6.11 ("incompatible Qt library")
    logos-module-builder = {
      url = "github:logos-co/logos-module-builder";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Platform-module dependencies (metadata.json `dependencies`). The builder
    # resolves each by input name and copies its generated API headers into the
    # build, so the generated logos_sdk.h's `#include "<dep>_module_api.h"` lines
    # resolve with versions that MATCH the generated client wrappers.
    chat_module = {
      url = "github:logos-co/logos-chat-module";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
    storage_module = {
      url = "github:logos-co/logos-storage-module";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
    delivery_module = {
      url = "github:logos-co/logos-delivery-module";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
  };

  outputs = inputs@{ self, nixpkgs, logos-module-builder, chat_module, storage_module, delivery_module }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
      # Ship metadata.json inside the plugin (#lib) output so the runtime loader
      # and CI (which copies result-agent/metadata.json) can find it next to the
      # built .so. The backend install only places the plugin lib, not metadata.
      postInstall = ''
        cp ${./metadata.json} $out/metadata.json
      '';
    };
}
