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
        (final: _: { zmkBuilders = zmk-nix.lib.buildersFor final; })
        self.overlays.default
      ];
    });

  in {
    overlays = {
      default = final: _: let
        inherit (final.zmkBuilders) buildKeyboard buildSplitKeyboard;

        src = lib.sourceFilesBySuffices self [
          ".board" ".cmake" ".conf" ".defconfig" ".dts" ".dtsi"
          ".json" ".keymap" ".overlay" ".shield" ".yml" "_defconfig"
        ];

        zephyrDepsHash = "sha256-qB4DEL4UldZoZc6C60reewAcwfbfR7SLuK2grfyMZuY=";

        # grpcio-tools ≥1.82 dropped setuptools from propagatedBuildInputs;
        # setuptools ≥82 removed pkg_resources. Inject setuptools 80.9.0 via
        # nativeBuildInputs so the nanopb generator can import pkg_resources.
        setuptools-compat = final.python3Packages.setuptools.overridePythonAttrs (_: rec {
          version = "80.9.0";
          src = final.python3Packages.fetchPypi {
            pname = "setuptools";
            inherit version;
            hash = "sha256-82tHQC7N52jb+vxG6OQge0NgxlTx87uER18KKGKPsZw=";
          };
        });

        firmware = buildSplitKeyboard {
          inherit src zephyrDepsHash;
          name = "corne_min";
          board = "corne_min_%PART%";
          shield = "rgbled_adapter";
          enableZmkStudio = true;
          nativeBuildInputs = [ setuptools-compat ];
          passthru = { reset = resetFirmware; };
        };

        # nix build .#reset  (clears BLE pairing state)
        resetFirmware = buildKeyboard {
          inherit src zephyrDepsHash;
          name = "corne_min_settings_reset";
          board = "corne_min_left";
          shield = "settings_reset";
        };

      in {
        corne-min-firmware = firmware;
      };
    };

    packages = eachSystem (system: let
      pkgs = pkgsFor.${system};
    in {
      # nix build .#firmware  (both halves; left is central)
      firmware = pkgs.corne-min-firmware;

      # nix build .#left / .#right  (individual halves)
      # nix build .#reset (clears left half BLE pairing state)
      inherit (pkgs.corne-min-firmware) left right reset;

      flash   = pkgs.callPackage "${zmk-nix}/nix/flash.nix" { firmware = pkgs.corne-min-firmware; };
      update  = pkgs.callPackage "${zmk-nix}/nix/update.nix" {};

      # nix build .#default  (both halves; left is central)
      default = pkgs.corne-min-firmware;
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
