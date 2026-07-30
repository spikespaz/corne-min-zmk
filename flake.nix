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
      inherit (pkgs) buildKeyboard;

      src = lib.sourceFilesBySuffices self [
        ".board" ".cmake" ".conf" ".defconfig" ".dts" ".dtsi"
        ".json" ".keymap" ".overlay" ".shield" ".yml" "_defconfig"
      ];

      zephyrDepsHash = "sha256-qB4DEL4UldZoZc6C60reewAcwfbfR7SLuK2grfyMZuY=";

      # nanopb generator uses pkg_resources (removed in Python 3.12); shim it
      # with importlib.resources so the ZMK Studio protobuf codegen doesn't fail.
      nanopbCompatSed =
        ''s|\([[:space:]]*\)import pkg_resources$''
        + ''|\1import importlib.resources as _ilr, types as _t\n''
        + ''\1pkg_resources = _t.SimpleNamespace(''
        + ''resource_filename=lambda pkg, path: str(_ilr.files(pkg) / path))|'';

      buildCorneMin = board: {
        name ? board,
        shield,
        enableStudio ? false,
        enableBLE ? true
      }: buildKeyboard {
        inherit name src zephyrDepsHash board shield;
        enableZmkStudio = enableStudio;
        postConfigure = lib.optionalString enableStudio ''
          for f in ../modules/lib/nanopb/generator/proto/__init__.py \
                   ../modules/lib/nanopb/generator/proto/_utils.py; do
            [ -f "$f" ] && sed -i '${nanopbCompatSed}' "$f"
          done
        '';
        extraCmakeFlags =
          lib.optional enableStudio  "-DCONFIG_ZMK_STUDIO_LOCKING=n"
          ++ lib.optional enableBLE  "-DCONFIG_ZMK_BLE_EXPERIMENTAL_CONN=y";
      };

    in {
      # nix build .#left
      # nix build .#right
      left  = buildCorneMin "corne_min_left"  { shield = "rgbled_adapter"; enableStudio = true; };
      right = buildCorneMin "corne_min_right" { shield = "rgbled_adapter"; };

      # nix build .#dongle
      dongle = buildCorneMin "seeeduino_xiao_ble" {
        name = "prospector_for_corne_min";
        shield = "corne_min_dongle prospector_adapter";
        enableStudio = true;
      };

      # nix build .#reset  (clears BLE pairing state)
      reset = buildCorneMin "corne_min_left" {
        name = "corne_min_settings_reset";
        shield = "settings_reset";
        enableBLE = false;
      };

      default = self.packages.${system}.left;
      flash   = pkgs.callPackage "${zmk-nix}/nix/flash.nix" { firmware = self.packages.${system}.default; };
      update  = pkgs.callPackage "${zmk-nix}/nix/update.nix" {};
    });

    devShells = eachSystem (system: {
      default = pkgsFor.${system}.callPackage "${zmk-nix}/nix/shell.nix" {};
    });
  };
}
