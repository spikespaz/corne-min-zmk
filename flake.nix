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
      overlays = [
        # This is a workaround to replace the default zmk-nix overlay,
        # which uses `prev` to instantiate the builders. That's a bug.
        # Also questionable is introducing two Zephyr helpers where the scope of
        # the flake is supposed to be ZMK keyboards, so here the scope is `zmkBuilders`.
        (final: _: { zmkBuilders = zmk-nix.lib.buildersFor final; })
      ];
    });
  in {
    packages = eachSystem (system: let
      pkgs = pkgsFor.${system};
      inherit (pkgs.zmkBuilders) buildKeyboard buildSplitKeyboard;

      src = lib.sourceFilesBySuffices self [
        ".board" ".cmake" ".conf" ".defconfig" ".dts" ".dtsi"
        ".json" ".keymap" ".overlay" ".shield" ".yml" "_defconfig"
      ];

      zephyrDepsHash = "sha256-qB4DEL4UldZoZc6C60reewAcwfbfR7SLuK2grfyMZuY=";

      # grpcio-tools ≥1.82 dropped setuptools from propagatedBuildInputs;
      # setuptools ≥82 removed pkg_resources. Inject setuptools 81.0.0 via
      # nativeBuildInputs so the nanopb generator can import pkg_resources.
      setuptools-compat = pkgs.python3Packages.setuptools.overridePythonAttrs (_: rec {
        version = "81.0.0";
        src = pkgs.python3Packages.fetchPypi {
          pname = "setuptools";
          inherit version;
          hash = "sha256-SHtTkV9SUB8Kecz9DALBZf/gZjFEOohnQLka9LelhFo=";
        };
      });

    in {
      # nix build .#firmware  (both halves; left is central with ZMK Studio)
      # nix build .#left / .#right  (individual halves)
      firmware = lib.makeOverridable buildSplitKeyboard {
        inherit src zephyrDepsHash;
        name = "corne_min";
        board = "corne_min_%PART%";
        shield = "rgbled_adapter";
        enableZmkStudio = true;
        nativeBuildInputs = [ setuptools-compat ];
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

    apps = eachSystem (system: {
      flash  = { type = "app"; program = lib.getExe self.packages.${system}.flash; };
      update = { type = "app"; program = lib.getExe self.packages.${system}.update; };

      default = self.apps.${system}.flash;
    });

    devShells = eachSystem (system: {
      default = pkgsFor.${system}.callPackage "${zmk-nix}/nix/shell.nix" {};
    });
  };
}
