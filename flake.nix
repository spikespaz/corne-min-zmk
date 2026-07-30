{
  description = "ZMK firmware for corne-min";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    zmk-nix = {
      url = "github:lilyinstarlight/zmk-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, zmk-nix }: let
    inherit (nixpkgs) lib;
    eachSystem = lib.genAttrs [ "aarch64-linux" "x86_64-linux" ];
    pkgsFor = eachSystem (system: import nixpkgs {
      localSystem.system = system;
      overlays = [ zmk-nix.overlays.default ];
    });
  in {
    packages = eachSystem (system: let
      pkgs = pkgsFor.${system};
      inherit (pkgs) buildKeyboard buildSplitKeyboard;

      src = lib.sourceFilesBySuffices self [
        ".board" ".cmake" ".conf" ".defconfig" ".dts" ".dtsi"
        ".json" ".keymap" ".overlay" ".shield" ".yml" "_defconfig"
      ];

      zephyrDepsHash = "sha256-qB4DEL4UldZoZc6C60reewAcwfbfR7SLuK2grfyMZuY=";

      # nanopb generator imports pkg_resources (removed in setuptools ≥82);
      # shim it so protobuf codegen for ZMK Studio works.
      nanopbCompatSed =
        ''s|\([[:space:]]*\)import pkg_resources$''
        + ''|\1import importlib.resources as _ilr, types as _t\n''
        + ''\1pkg_resources = _t.SimpleNamespace(''
        + ''resource_filename=lambda pkg, path: str(_ilr.files(pkg) / path))|'';

    in {
      # nix build .#firmware  (both halves; left is central with ZMK Studio)
      # nix build .#left / .#right  (individual halves)
      firmware = lib.makeOverridable buildSplitKeyboard {
        inherit src zephyrDepsHash;
        name = "corne_min";
        board = "corne_min_%PART%";
        shield = "rgbled_adapter";
        enableZmkStudio = true;
        postConfigure = ''
          if [ -d ../modules/lib/nanopb/generator ]; then
            find ../modules/lib/nanopb/generator -name "*.py" \
              -exec sed -i '${nanopbCompatSed}' {} +
          fi
        '';
      };

      inherit (self.packages.${system}.firmware) left right;

      # nix build .#reset  (clears BLE pairing state)
      reset = buildKeyboard {
        inherit src zephyrDepsHash;
        name = "corne_min_settings_reset";
        board = "corne_min_left";
        shield = "settings_reset";
      };

      flash   = pkgs.callPackage "${zmk-nix}/nix/flash.nix" { firmware = self.packages.${system}.firmware; };
      update  = pkgs.callPackage "${zmk-nix}/nix/update.nix" {};

      default = self.packages.${system}.firmware;
    });

    devShells = eachSystem (system: {
      default = pkgsFor.${system}.callPackage "${zmk-nix}/nix/shell.nix" {};
    });
  };
}
